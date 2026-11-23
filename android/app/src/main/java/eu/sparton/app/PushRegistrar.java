package eu.sparton.app;

import android.content.SharedPreferences;
import android.os.Build;
import android.webkit.CookieManager;
import android.webkit.WebView;
import androidx.annotation.Nullable;
import androidx.core.app.NotificationManagerCompat;
import com.google.firebase.messaging.FirebaseMessaging;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;
import org.json.JSONObject;

/**
 * Registrácia zariadenia pre push (FCM) na serveri spartON: POST /api/push/devices z prihlásenej stránky
 * (rovnaké cookies a pôvod ako web, CSRF ochrana servera platí). Upsert podľa tokenu – volá sa po prihlásení,
 * pri zmene tokenu alebo relácie a raz za 24 h. Keď používateľ upozornenia vypne, zariadenie sa odregistruje.
 */
final class PushRegistrar {

    static final String SESSION_COOKIE = "sparton_session";
    private static final long REFRESH_MS = 24L * 60 * 60 * 1000;

    private final MainActivity activity;
    private boolean fetchingToken = false;
    private boolean inFlight = false;

    PushRegistrar(MainActivity activity) {
        this.activity = activity;
    }

    /** Odtlačok relácie (SHA-256 hodnoty cookie) – samotná hodnota sa nikam neukladá. Null = neprihlásený. */
    @Nullable
    static String sessionKey() {
        String all = CookieManager.getInstance().getCookie(Links.ORIGIN);
        if (all == null) return null;
        for (String part : all.split(";")) {
            String p = part.trim();
            if (p.startsWith(SESSION_COOKIE + "=") && p.length() > SESSION_COOKIE.length() + 1) {
                return sha256(p.substring(SESSION_COOKIE.length() + 1));
            }
        }
        return null;
    }

    static boolean isLoggedIn() {
        return sessionKey() != null;
    }

    @Nullable
    String token() {
        return Prefs.get(activity).getString(Prefs.PUSH_TOKEN, null);
    }

    /** Získa token FCM (ak Firebase nie je nakonfigurovaný, push sa ticho vynechá). */
    void ensureToken(@Nullable Runnable then) {
        if (fetchingToken) return;
        try {
            fetchingToken = true;
            FirebaseMessaging.getInstance()
                .getToken()
                .addOnCompleteListener(t -> {
                    fetchingToken = false;
                    if (t.isSuccessful() && t.getResult() != null && !t.getResult().isEmpty()) {
                        String tok = t.getResult();
                        String old = token();
                        if (!tok.equals(old)) {
                            Prefs.get(activity).edit().putString(Prefs.PUSH_TOKEN, tok).remove(Prefs.PUSH_REG_KEY).apply();
                        }
                        activity.publishPushToken(tok);
                        if (then != null) then.run();
                    }
                });
        } catch (IllegalStateException e) {
            fetchingToken = false; // Firebase bez google-services.json
        }
    }

    /** Po načítaní stránky sparton.eu: zaregistruj, obnov alebo odregistruj zariadenie podľa stavu. */
    void sync(WebView webView) {
        String sess = sessionKey();
        if (sess == null || inFlight) return;
        String tok = token();
        if (tok == null) {
            ensureToken(() -> activity.runOnUiThread(() -> sync(activity.getBridge().getWebView())));
            return;
        }
        SharedPreferences p = Prefs.get(activity);
        String key = sha256(sess + "|" + tok);
        String stored = p.getString(Prefs.PUSH_REG_KEY, null);
        boolean enabled = NotificationManagerCompat.from(activity).areNotificationsEnabled();
        if (!enabled) {
            if (key.equals(stored)) {
                unregister(webView, tok);
            }
            return;
        }
        long at = p.getLong(Prefs.PUSH_REG_AT, 0);
        if (key.equals(stored) && System.currentTimeMillis() - at < REFRESH_MS) return;
        register(webView, tok, key);
    }

    private void register(WebView webView, String tok, String key) {
        try {
            JSONObject body = new JSONObject();
            body.put("platform", "android");
            body.put("token", tok);
            body.put("appVersion", BuildConfig.VERSION_NAME);
            body.put("osVersion", "Android " + Build.VERSION.RELEASE);
            body.put("deviceModel", (Build.MANUFACTURER + " " + Build.MODEL).trim());
            body.put("locale", Locale.getDefault().toLanguageTag());
            inFlight = true;
            String js =
                "(function(b,k){var n=window.spartonNative;function d(o){if(n&&n.postMessage)n.postMessage(JSON.stringify(o))}" +
                "fetch('/api/push/devices',{method:'POST',credentials:'same-origin',headers:{'content-type':'application/json'},body:JSON.stringify(b)})" +
                ".then(function(r){d({type:'pushReg',ok:r.ok,status:r.status,key:k})})" +
                ".catch(function(){d({type:'pushReg',ok:false,status:0,key:k})})})(" +
                body +
                "," +
                JSONObject.quote(key) +
                ")";
            webView.evaluateJavascript(js, null);
            // keď WebView nepodporuje správy (staré verzie), ďalší pokus príde pri ďalšom načítaní
            webView.postDelayed(() -> inFlight = false, 15000);
        } catch (Exception e) {
            inFlight = false;
        }
    }

    private void unregister(WebView webView, String tok) {
        try {
            JSONObject body = new JSONObject();
            body.put("token", tok);
            String js =
                "(function(b){var n=window.spartonNative;" +
                "fetch('/api/push/devices',{method:'DELETE',credentials:'same-origin',headers:{'content-type':'application/json'},body:JSON.stringify(b)})" +
                ".then(function(r){if(n&&n.postMessage)n.postMessage(JSON.stringify({type:'pushUnreg',ok:r.ok}))}).catch(function(){})})(" +
                body +
                ")";
            webView.evaluateJavascript(js, null);
        } catch (Exception ignored) {}
    }

    void onRegistered(boolean ok, int status, @Nullable String key) {
        inFlight = false;
        SharedPreferences.Editor e = Prefs.get(activity).edit();
        if (ok && key != null) {
            e.putString(Prefs.PUSH_REG_KEY, key).putLong(Prefs.PUSH_REG_AT, System.currentTimeMillis());
        } else if (status == 401) {
            e.remove(Prefs.PUSH_REG_KEY);
        }
        e.apply();
    }

    void onUnregistered(boolean ok) {
        if (ok) Prefs.get(activity).edit().remove(Prefs.PUSH_REG_KEY).remove(Prefs.PUSH_REG_AT).apply();
    }

    /** Nový token z FCM – pri najbližšom načítaní stránky sa zariadenie zaregistruje znova. */
    static void onNewToken(android.content.Context c, String tok) {
        Prefs.get(c).edit().putString(Prefs.PUSH_TOKEN, tok).remove(Prefs.PUSH_REG_KEY).apply();
    }

    static String sha256(String s) {
        try {
            byte[] d = MessageDigest.getInstance("SHA-256").digest(s.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (byte b : d) sb.append(String.format(Locale.ROOT, "%02x", b));
            return sb.toString();
        } catch (Exception e) {
            return Integer.toHexString(s.hashCode());
        }
    }
}
