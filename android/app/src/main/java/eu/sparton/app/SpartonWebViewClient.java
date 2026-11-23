package eu.sparton.app;

import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import com.getcapacitor.Bridge;
import com.getcapacitor.BridgeWebViewClient;

/**
 * Navigácia vo webview appky:
 * - /auth/google/start → natívne prihlásenie cez Google,
 * - stránky appky na sparton.eu ostávajú v appke, ostatné adresy (marketing, cenník, cudzie weby, mailto:, tel:)
 *   sa otvoria v systémovom prehliadači / aplikácii,
 * - obrazovka „si offline“ len pri sieťovej chybe hlavného rámca (nie pri HTTP 404/500 – tie ukáže web sám).
 */
public class SpartonWebViewClient extends BridgeWebViewClient {

    private final MainActivity activity;
    private final Bridge bridge;

    public SpartonWebViewClient(Bridge bridge, MainActivity activity) {
        super(bridge);
        this.bridge = bridge;
        this.activity = activity;
    }

    /** Analytika a reklama (Google Analytics/Tag Manager, Google Ads, Meta) – v appke sa nenačítajú nikdy. */
    private static final String[] BLOCKED_HOSTS = {
        "googletagmanager.com",
        "google-analytics.com",
        "analytics.google.com",
        "googleadservices.com",
        "googlesyndication.com",
        "doubleclick.net",
        "connect.facebook.net",
        "facebook.com",
        "facebook.net",
    };

    static boolean isBlocked(Uri url) {
        String h = url.getHost();
        if (h == null) return false;
        h = h.toLowerCase(java.util.Locale.ROOT);
        for (String b : BLOCKED_HOSTS) {
            if (h.equals(b) || h.endsWith("." + b)) return true;
        }
        return false;
    }

    @Override
    public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
        if (isBlocked(request.getUrl())) {
            return new WebResourceResponse("text/plain", "utf-8", 204, "No Content", new java.util.HashMap<>(), new java.io.ByteArrayInputStream(new byte[0]));
        }
        return super.shouldInterceptRequest(view, request);
    }

    @Override
    public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
        Uri url = request.getUrl();
        if (!request.isForMainFrame()) {
            // vnorené rámce (Cloudflare Turnstile, platobné prvky) sa načítajú normálne – Capacitor by ich poslal do prehliadača
            return false;
        }
        if (Links.isGoogleStart(url)) {
            // len z hlavného rámca stránky spartON (nie z vnoreného rámca ani cudzej stránky)
            if (activity.isOnAppPage()) activity.googleSignIn().start(url);
            return true;
        }
        if (Links.isAppHost(url)) {
            if (Links.isInAppPath(url.getPath())) return false;
            openExternal(url);
            return true;
        }
        String scheme = url.getScheme();
        // hlavný rámec appky je vždy https://sparton.eu – data:, blob: a iné schémy sa v ňom nenačítajú
        if ("data".equals(scheme) || "blob".equals(scheme) || "about".equals(scheme) || "javascript".equals(scheme) || "file".equals(scheme)) return true;
        openExternal(url);
        return true;
    }

    private void openExternal(Uri url) {
        try {
            Intent i = new Intent(Intent.ACTION_VIEW, url).addCategory(Intent.CATEGORY_BROWSABLE);
            activity.startActivity(i);
        } catch (ActivityNotFoundException ignored) {
            // nič, čo by adresu otvorilo
        }
    }

    @Override
    public void onPageStarted(WebView view, String url, Bitmap favicon) {
        super.onPageStarted(view, url, favicon);
        activity.onPageStarted(url);
    }

    @Override
    public void onPageCommitVisible(WebView view, String url) {
        super.onPageCommitVisible(view, url);
        activity.onPageVisible(url);
    }

    @Override
    public void onPageFinished(WebView view, String url) {
        super.onPageFinished(view, url);
        activity.onPageFinished(url);
    }

    @Override
    public void doUpdateVisitedHistory(WebView view, String url, boolean isReload) {
        super.doUpdateVisitedHistory(view, url, isReload);
        activity.onRouteChanged(url);
    }

    @Override
    public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
        if (request.isForMainFrame()) {
            String failed = request.getUrl().toString();
            String errorUrl = bridge.getErrorUrl();
            if (errorUrl != null && !failed.startsWith(errorUrl)) {
                activity.onOffline(failed);
            }
        }
        // Capacitor pri chybe hlavného rámca načíta server.errorPath (offline.html, servíruje ho appka lokálne)
        super.onReceivedError(view, request, error);
    }

    @Override
    public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse errorResponse) {
        // Zámerne bez volania Capacitor: ten by pri akejkoľvek HTTP chybe (aj 404) ukázal obrazovku offline.
    }
}
