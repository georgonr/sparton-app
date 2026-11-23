package eu.sparton.app;

import android.Manifest;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.graphics.drawable.Drawable;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.View;
import android.webkit.WebSettings;
import android.webkit.WebView;
import androidx.activity.OnBackPressedCallback;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AlertDialog;
import androidx.core.content.ContextCompat;
import androidx.core.graphics.ColorUtils;
import androidx.core.graphics.Insets;
import androidx.core.splashscreen.SplashScreen;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;
import com.getcapacitor.BridgeActivity;
import java.util.Collections;
import org.json.JSONObject;

/**
 * Appka spartON: webview s produkčným spartON (https://sparton.eu/app, príznak spartON-App v User-Agent – server
 * v appke skryje nákupy) + natívne časti: push (FCM), biometrický zámok, prihlásenie cez Google, hlboké odkazy,
 * obrazovka offline, tlačidlo Späť, od okraja po okraj s lištami vo farbe stránky.
 */
public class MainActivity extends BridgeActivity {

    static final String ACTION_SETTINGS = "eu.sparton.app.SETTINGS";

    private volatile boolean contentReady = false;
    private long createdAt;
    private boolean ready = false;
    private boolean dialogShownThisSession = false;

    @Nullable
    private String failedUrl;

    private boolean offlineShown = false;
    private boolean appPageLoaded = false;

    @Nullable
    private String currentUrl;

    private GoogleSignIn google;
    private PushRegistrar push;
    private BiometricLock lock;
    private BarsBackground bars;
    private ActivityResultLauncher<String> notifPermission;
    private ConnectivityManager.NetworkCallback netCallback;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        SplashScreen splash = SplashScreen.installSplashScreen(this);
        createdAt = SystemClock.elapsedRealtime();
        splash.setKeepOnScreenCondition(() -> !contentReady && SystemClock.elapsedRealtime() - createdAt < 4000);
        necessaryCookiesOnly();
        super.onCreate(savedInstanceState);
        if (bridge == null || bridge.getWebView() == null) return;

        google = new GoogleSignIn(this);
        push = new PushRegistrar(this);
        lock = new BiometricLock(this);
        notifPermission = registerForActivityResult(new ActivityResultContracts.RequestPermission(), granted -> {
            if (bridge != null) push.sync(bridge.getWebView());
        });

        WebView wv = bridge.getWebView();
        // len debug zostavenie (smoke test v GitHub Actions cez Chrome DevTools); vydanie nemá ladenie zapnuté
        if (BuildConfig.DEBUG) WebView.setWebContentsDebuggingEnabled(true);
        bridge.setWebViewClient(new SpartonWebViewClient(bridge, this));
        WebSettings s = wv.getSettings();
        s.setSupportMultipleWindows(false); // target=_blank → rovnaké webview → pravidlá odkazov
        s.setGeolocationEnabled(false);
        wv.setDownloadListener(this::download);

        setupEdgeToEdge(wv);
        setupNativeMessages(wv);
        setupBackButton();
        SpartonMessagingService.ensureChannel(this);
        String cached = push.token();
        if (cached != null) publishPushToken(cached);
        push.ensureToken(null);

        lock.onColdStart();
        ready = true;
        handleIntent(getIntent());
    }

    /**
     * Appka nepoužíva analytické ani marketingové cookies: súhlas „len nevyhnutné“ (formát webu, lib/consent.ts,
     * verzia 2) sa zapíše pri každom štarte, takže sa cookie lišta webu v appke nezobrazí. Požiadavky na analytiku
     * a reklamu navyše blokuje SpartonWebViewClient (pre prípad zmeny súhlasu v pätičke).
     */
    private static void necessaryCookiesOnly() {
        try {
            String day = new java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.ROOT).format(new java.util.Date());
            android.webkit.CookieManager cm = android.webkit.CookieManager.getInstance();
            cm.setCookie(Links.ORIGIN, "sparton_consent=2.000." + day + "; Max-Age=31536000; Path=/; Domain=.sparton.eu; Secure; SameSite=Lax");
            cm.flush();
        } catch (Exception ignored) {}
    }

    // ------------------------------------------------------------ od okraja po okraj

    private void setupEdgeToEdge(WebView wv) {
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        if (Build.VERSION.SDK_INT < 35) {
            getWindow().setStatusBarColor(Color.TRANSPARENT);
            getWindow().setNavigationBarColor(Color.TRANSPARENT);
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            getWindow().setNavigationBarContrastEnforced(false);
            getWindow().setStatusBarContrastEnforced(false);
        }
        int page = ContextCompat.getColor(this, R.color.sparton_page);
        View root = (View) wv.getParent();
        bars = new BarsBackground(page, page);
        root.setBackground(bars);
        wv.setBackgroundColor(page);
        ViewCompat.setOnApplyWindowInsetsListener(root, (v, insets) -> {
            Insets sys = insets.getInsets(WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
            Insets ime = insets.getInsets(WindowInsetsCompat.Type.ime());
            int bottom = Math.max(sys.bottom, ime.bottom);
            v.setPadding(sys.left, sys.top, sys.right, bottom);
            bars.setBands(sys.top, bottom);
            // obsah stránky je už mimo systémových líšt – webview dostane nulové okraje (env(safe-area-*) = 0)
            return new WindowInsetsCompat.Builder(insets)
                .setInsets(WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout(), Insets.NONE)
                .setInsets(WindowInsetsCompat.Type.ime(), Insets.NONE)
                .build();
        });
        applyBarColors(page, page);
    }

    private void applyBarColors(int top, int bottom) {
        bars.setColors(top, bottom);
        WindowInsetsControllerCompat c = WindowCompat.getInsetsController(getWindow(), getWindow().getDecorView());
        c.setAppearanceLightStatusBars(ColorUtils.calculateLuminance(top) > 0.5);
        c.setAppearanceLightNavigationBars(ColorUtils.calculateLuminance(bottom) > 0.5);
    }

    /** Farba hornej a dolnej hrany stránky → pozadie pod stavovým riadkom a gestami. */
    private void sampleBarColors() {
        if (bridge == null) return;
        String js =
            "(function(){function c(x,y){var e=document.elementFromPoint(x,y);while(e){var b=getComputedStyle(e).backgroundColor;" +
            "if(b&&b!=='transparent'&&!/,\\s*0\\)$/.test(b))return b;e=e.parentElement}" +
            "var d=document.body||document.documentElement;return d?getComputedStyle(d).backgroundColor:''}" +
            "var w=Math.max(1,Math.floor(innerWidth/2));return c(w,1)+'|'+c(w,Math.max(1,innerHeight-2))})()";
        bridge
            .getWebView()
            .evaluateJavascript(js, value -> {
                if (value == null) return;
                String[] parts = value.replace("\"", "").split("\\|");
                if (parts.length != 2) return;
                Integer top = parseCssColor(parts[0]);
                Integer bottom = parseCssColor(parts[1]);
                if (top != null && bottom != null) applyBarColors(top, bottom);
            });
    }

    @Nullable
    static Integer parseCssColor(String css) {
        try {
            String s = css.trim();
            if (!s.startsWith("rgb")) return null;
            String[] n = s.substring(s.indexOf('(') + 1, s.indexOf(')')).trim().split("[,\\s/]+");
            return Color.rgb(Math.round(Float.parseFloat(n[0])), Math.round(Float.parseFloat(n[1])), Math.round(Float.parseFloat(n[2])));
        } catch (Exception e) {
            return null;
        }
    }

    /** Pozadie koreňa: horná polovica vo farbe hornej hrany stránky, dolná vo farbe dolnej hrany. */
    static final class BarsBackground extends Drawable {

        private final Paint topPaint = new Paint();
        private final Paint bottomPaint = new Paint();

        BarsBackground(int top, int bottom) {
            topPaint.setColor(top);
            bottomPaint.setColor(bottom);
        }

        void setColors(int top, int bottom) {
            topPaint.setColor(top);
            bottomPaint.setColor(bottom);
            invalidateSelf();
        }

        void setBands(int top, int bottom) {
            invalidateSelf();
        }

        @Override
        public void draw(@NonNull Canvas canvas) {
            float w = getBounds().width();
            float h = getBounds().height();
            canvas.drawRect(0, 0, w, h / 2f, topPaint);
            canvas.drawRect(0, h / 2f, w, h, bottomPaint);
        }

        @Override
        public void setAlpha(int alpha) {}

        @Override
        public void setColorFilter(@Nullable ColorFilter colorFilter) {}

        @Override
        public int getOpacity() {
            return PixelFormat.OPAQUE;
        }
    }

    // ------------------------------------------------------------ správy zo stránky sparton.eu

    private void setupNativeMessages(WebView wv) {
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(wv, "spartonNative", Collections.singleton(Links.ORIGIN), (view, message, sourceOrigin, isMainFrame, reply) -> {
                if (!isMainFrame || message.getData() == null) return;
                handleMessage(message.getData());
            });
        }
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            // Odhlásenie: server odregistruje zariadenie, ak požiadavka nesie token FCM (hlavička X-Push-Token).
            String js =
                "(function(){if(window.__spartonFetch)return;window.__spartonFetch=1;var f=window.fetch;if(!f)return;" +
                "window.fetch=function(i,o){try{var t=window.__spartonPushToken;if(t){var u=new URL(typeof i==='string'?i:(i&&i.url)||String(i),location.href);" +
                "if(u.origin===location.origin){o=Object.assign({},o||{});var h=new Headers(o.headers||(i instanceof Request?i.headers:undefined));" +
                "h.set('X-Push-Token',t);o.headers=h}}}catch(e){}return f.call(this,i,o)}})();";
            WebViewCompat.addDocumentStartJavaScript(wv, js, Collections.singleton(Links.ORIGIN));
        }
    }

    private void handleMessage(String data) {
        try {
            JSONObject o = new JSONObject(data);
            switch (o.optString("type")) {
                case "gnonce":
                    google.onNonce(o.optString("nonce", ""));
                    break;
                case "pushReg":
                    push.onRegistered(o.optBoolean("ok"), o.optInt("status"), o.optString("key", null));
                    break;
                case "pushUnreg":
                    push.onUnregistered(o.optBoolean("ok"));
                    break;
                case "retry":
                    retry();
                    break;
                default:
                    break;
            }
        } catch (Exception ignored) {}
    }

    void publishPushToken(String token) {
        if (bridge == null) return;
        runOnUiThread(() -> {
            if (isOnAppPage()) bridge.getWebView().evaluateJavascript("window.__spartonPushToken=" + JSONObject.quote(token) + ";", null);
        });
    }

    /** Je v hlavnom rámci stránka https://sparton.eu? Len do nej appka vkladá token alebo prihlasovacie údaje. */
    boolean isOnAppPage() {
        if (bridge == null) return false;
        String u = bridge.getWebView().getUrl();
        return u != null && Links.isAppHost(Uri.parse(u));
    }

    GoogleSignIn googleSignIn() {
        return google;
    }

    // ------------------------------------------------------------ životný cyklus stránky

    void onPageStarted(String url) {
        currentUrl = url;
        appPageLoaded = false;
    }

    void onPageVisible(String url) {
        contentReady = true;
    }

    void onPageFinished(String url) {
        contentReady = true;
        currentUrl = url;
        String errorUrl = bridge.getErrorUrl();
        offlineShown = errorUrl != null && url != null && url.startsWith(errorUrl);
        if (!offlineShown) failedUrl = null;
        String tok = push.token();
        if (tok != null) publishPushToken(tok);
        sampleBarColors();
        appPageLoaded = url != null && Links.isAppHost(Uri.parse(url)) && !offlineShown;
        if (appPageLoaded && PushRegistrar.isLoggedIn()) {
            afterLoginPrompts();
            push.sync(bridge.getWebView());
        }
    }

    void onRouteChanged(String url) {
        currentUrl = url;
        bridge.getWebView().postDelayed(this::sampleBarColors, 250);
    }

    /** Po prihlásení raz: povolenie upozornení (Android 13+), pri ďalšom načítaní ponuka biometrického zámku. */
    private void afterLoginPrompts() {
        if (dialogShownThisSession || lock.isLocked()) return;
        SharedPreferences p = Prefs.get(this);
        if (
            Build.VERSION.SDK_INT >= 33 &&
            !p.getBoolean(Prefs.PUSH_ASKED, false) &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            p.edit().putBoolean(Prefs.PUSH_ASKED, true).apply();
            dialogShownThisSession = true;
            notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS);
            return;
        }
        if (!p.getBoolean(Prefs.BIO_ASKED, false) && lock.biometricsAvailable()) {
            p.edit().putBoolean(Prefs.BIO_ASKED, true).apply();
            dialogShownThisSession = true;
            new AlertDialog.Builder(this)
                .setTitle(R.string.bio_offer_title)
                .setMessage(R.string.bio_offer_text)
                .setPositiveButton(R.string.bio_offer_yes, (d, w) -> lock.prompt(() -> lock.setEnabled(true)))
                .setNegativeButton(R.string.bio_offer_no, (d, w) -> lock.setEnabled(false))
                .show();
        }
    }

    // ------------------------------------------------------------ sťahovanie súborov (dokumenty, výpisy, exporty)

    private void download(String url, String userAgent, String contentDisposition, String mimeType, long length) {
        Uri uri = Uri.parse(url);
        if (!Links.isAppHost(uri) || Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            // cudzí súbor alebo Android 9 a starší (bez povolenia úložiska) → systémový prehliadač
            try {
                startActivity(new Intent(Intent.ACTION_VIEW, uri));
            } catch (Exception ignored) {}
            return;
        }
        String name = android.webkit.URLUtil.guessFileName(url, contentDisposition, mimeType);
        android.widget.Toast.makeText(this, getString(R.string.download_started, name), android.widget.Toast.LENGTH_SHORT).show();
        new Thread(() -> {
            boolean ok = Downloads.save(this, url, userAgent, name, mimeType);
            runOnUiThread(() -> {
                if (!ok) android.widget.Toast.makeText(this, R.string.download_failed, android.widget.Toast.LENGTH_LONG).show();
                else android.widget.Toast.makeText(this, getString(R.string.download_done, name), android.widget.Toast.LENGTH_SHORT).show();
            });
        }, "sparton-download").start();
    }
    // ------------------------------------------------------------ offline

    void onOffline(String failed) {
        failedUrl = failed;
        offlineShown = true;
        watchNetwork();
    }

    private void retry() {
        bridge.getWebView().loadUrl(failedUrl != null ? failedUrl : Links.START_URL);
    }

    private void watchNetwork() {
        if (netCallback != null) return;
        ConnectivityManager cm = getSystemService(ConnectivityManager.class);
        if (cm == null) return;
        netCallback = new ConnectivityManager.NetworkCallback() {
            @Override
            public void onAvailable(@NonNull Network network) {
                runOnUiThread(() -> {
                    if (offlineShown) retry();
                });
            }
        };
        try {
            cm.registerNetworkCallback(new NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), netCallback);
        } catch (Exception e) {
            netCallback = null;
        }
    }

    // ------------------------------------------------------------ tlačidlo Späť

    private void setupBackButton() {
        getOnBackPressedDispatcher()
            .addCallback(
                this,
                new OnBackPressedCallback(true) {
                    @Override
                    public void handleOnBackPressed() {
                        WebView wv = bridge.getWebView();
                        if (lock.isLocked() || offlineShown || Links.isHome(currentUrl) || !wv.canGoBack()) {
                            moveTaskToBack(true);
                            return;
                        }
                        wv.goBack();
                    }
                }
            );
    }

    // ------------------------------------------------------------ odkazy, push, nastavenia

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (ready) handleIntent(intent);
    }

    private void handleIntent(@Nullable Intent intent) {
        if (intent == null || bridge == null) return;
        if (ACTION_SETTINGS.equals(intent.getAction())) {
            bridge.getWebView().post(this::showSettings);
            return;
        }
        String target = null;
        String pushUrl = intent.getStringExtra(SpartonMessagingService.EXTRA_URL);
        if (pushUrl != null) target = Links.fromRelative(pushUrl);
        if (target == null && Intent.ACTION_VIEW.equals(intent.getAction())) target = Links.resolveIncoming(intent.getData());
        if (target != null) {
            final String t = target;
            bridge.getWebView().post(() -> bridge.getWebView().loadUrl(t));
        }
    }

    /** Nastavenia appky (dlhé podržanie ikony → Nastavenia appky). */
    private void showSettings() {
        boolean on = lock.isEnabled();
        String[] items = { getString(on ? R.string.settings_bio_off : R.string.settings_bio_on), getString(R.string.settings_notifications) };
        new AlertDialog.Builder(this)
            .setTitle(R.string.settings_title)
            .setItems(items, (d, which) -> {
                if (which == 0) {
                    if (!lock.canAuthenticate()) {
                        new AlertDialog.Builder(this).setMessage(R.string.settings_bio_unavailable).setPositiveButton(android.R.string.ok, null).show();
                        return;
                    }
                    lock.prompt(() -> lock.setEnabled(!on));
                } else {
                    openNotificationSettings();
                }
            })
            .setNegativeButton(R.string.settings_close, null)
            .show();
    }

    private void openNotificationSettings() {
        try {
            startActivity(new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName()));
        } catch (Exception e) {
            startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + getPackageName())));
        }
    }

    @Override
    public void onResume() {
        super.onResume();
        if (lock != null) lock.onForeground();
        if (ready && bridge != null && appPageLoaded && PushRegistrar.isLoggedIn()) push.sync(bridge.getWebView());
    }

    @Override
    public void onStop() {
        super.onStop();
        if (lock != null) lock.onBackground();
    }

    @Override
    public void onDestroy() {
        if (netCallback != null) {
            try {
                ConnectivityManager cm = getSystemService(ConnectivityManager.class);
                if (cm != null) cm.unregisterNetworkCallback(netCallback);
            } catch (Exception ignored) {}
            netCallback = null;
        }
        super.onDestroy();
    }
}
