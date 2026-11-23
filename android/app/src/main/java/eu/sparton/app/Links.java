package eu.sparton.app;

import android.net.Uri;
import androidx.annotation.Nullable;

/**
 * Pravidlá odkazov appky spartON: čo sa otvorí vo webview appky, čo v systémovom prehliadači
 * a ako sa preloží hlboký odkaz (https://sparton.eu/…, eu.sparton.app://pay/return, push s relatívnou cestou).
 */
final class Links {

    static final String HOST = "sparton.eu";
    static final String ORIGIN = "https://" + HOST;
    static final String START_URL = ORIGIN + "/app";
    static final String APP_SCHEME = "eu.sparton.app";

    /** Cesty, ktoré patria do appky. Ostatné (marketing, cenník, články) idú do prehliadača. */
    private static final String[] IN_APP_PREFIXES = {
        "/app",
        "/login",
        "/register",
        "/forgot-password",
        "/reset-password/",
        "/verify-email/",
        "/invite/",
        "/google-link",
        "/auth/",
        "/pay/",
        "/p/",
        "/media/",
        "/offline.html",
    };

    private Links() {}

    static boolean isAppHost(@Nullable Uri uri) {
        return uri != null && "https".equals(uri.getScheme()) && HOST.equalsIgnoreCase(uri.getHost());
    }

    /** Patrí stránka na sparton.eu do appky? */
    static boolean isInAppPath(@Nullable String path) {
        if (path == null || path.isEmpty() || "/".equals(path)) return false;
        for (String p : IN_APP_PREFIXES) {
            if (p.endsWith("/") ? path.startsWith(p) : (path.equals(p) || path.startsWith(p + "/") || path.startsWith(p + "?"))) {
                return true;
            }
        }
        return false;
    }

    /** Štart webového toku Google – v appke ho nahradí natívne prihlásenie (Google OAuth vo webview blokuje). */
    static boolean isGoogleStart(@Nullable Uri uri) {
        if (uri == null || !"https".equals(uri.getScheme()) || uri.getHost() == null) return false;
        String host = uri.getHost().toLowerCase();
        return (host.equals(HOST) || host.equals("app." + HOST)) && "/auth/google/start".equals(uri.getPath());
    }

    /** Bezpečná relatívna cesta (len "/…", nie "//…" ani schéma) → plná adresa na sparton.eu, inak null. */
    @Nullable
    static String fromRelative(@Nullable String to) {
        if (to == null) return null;
        String t = to.trim();
        if (!t.startsWith("/") || t.startsWith("//") || t.startsWith("/\\") || t.length() > 2000) return null;
        for (int i = 0; i < t.length(); i++) {
            if (t.charAt(i) < 0x20) return null;
        }
        return ORIGIN + t;
    }

    /**
     * Adresa, ktorú má appka načítať pre prichádzajúci odkaz (App Links, vlastná schéma), alebo null.
     * eu.sparton.app://pay/return?to=/app/…&r=ok → https://sparton.eu/app/…
     */
    @Nullable
    static String resolveIncoming(@Nullable Uri uri) {
        if (uri == null) return null;
        if (APP_SCHEME.equals(uri.getScheme())) {
            String to = uri.getQueryParameter("to");
            String target = fromRelative(to);
            return target != null ? target : START_URL;
        }
        if (isAppHost(uri)) {
            return isInAppPath(uri.getPath()) ? uri.toString() : null;
        }
        return null;
    }

    /** Domovské stránky appky – tlačidlo Späť na nich appku zatvorí namiesto návratu na prihlásenie. */
    static boolean isHome(@Nullable String url) {
        if (url == null) return false;
        Uri u = Uri.parse(url);
        if (!isAppHost(u) || u.getPath() == null) return false;
        String p = u.getPath().replaceAll("/+$", "");
        return p.equals("/app") || p.matches("/app/[^/]+") && !p.equals("/app/account") && !p.equals("/app/new-club") && !p.equals("/app/terms");
    }
}
