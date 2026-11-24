import Foundation

/// Pravidlá odkazov appky spartON (rovnaké ako Android `Links.java`): čo sa otvorí vo webview appky, čo v Safari
/// a ako sa preloží hlboký odkaz (Universal Link https://sparton.eu/…, eu.sparton.app://pay/return, push s cestou).
enum Links {
    static let host = "sparton.eu"
    static let origin = "https://sparton.eu"
    static let startURL = URL(string: "https://sparton.eu/app")!
    static let appScheme = "eu.sparton.app"

    /// Cesty, ktoré patria do appky. Ostatné (marketing, cenník, články) idú do Safari.
    private static let inAppPrefixes = [
        "/app", "/login", "/register", "/forgot-password", "/reset-password/", "/verify-email/", "/invite/",
        "/google-link", "/auth/", "/pay/", "/p/", "/media/", "/offline.html",
    ]

    static func isAppHost(_ url: URL?) -> Bool {
        guard let u = url else { return false }
        return u.scheme?.lowercased() == "https" && u.host?.lowercased() == host
    }

    /// Lokálna obrazovka offline (Capacitor ju servíruje cez capacitor://sparton.eu/offline.html).
    static func isLocalOffline(_ url: URL?) -> Bool {
        guard let u = url else { return false }
        return u.scheme?.lowercased() == "capacitor" && u.host?.lowercased() == host
    }

    static func isInAppPath(_ path: String?) -> Bool {
        guard let path = path, !path.isEmpty, path != "/" else { return false }
        for p in inAppPrefixes {
            if p.hasSuffix("/") {
                if path.hasPrefix(p) { return true }
            } else if path == p || path.hasPrefix(p + "/") || path.hasPrefix(p + "?") {
                return true
            }
        }
        return false
    }

    /// Štart webového toku Google / Apple – v appke ho nahradí natívne prihlásenie.
    static func signInStart(_ url: URL?) -> String? {
        guard let u = url, u.scheme?.lowercased() == "https", let h = u.host?.lowercased(),
              h == host || h == "app." + host else { return nil }
        switch u.path {
        case "/auth/google/start": return "google"
        case "/auth/apple/start": return "apple"
        default: return nil
        }
    }

    /// Bezpečná relatívna cesta ("/…", nie "//…" ani schéma) → plná adresa na sparton.eu, inak nil.
    static func fromRelative(_ to: String?) -> URL? {
        guard let t0 = to?.trimmingCharacters(in: .whitespaces), t0.hasPrefix("/"), !t0.hasPrefix("//"),
              !t0.hasPrefix("/\\"), t0.count <= 2000 else { return nil }
        if t0.unicodeScalars.contains(where: { $0.value < 0x20 }) { return nil }
        return URL(string: origin + t0)
    }

    /// Adresa, ktorú má appka načítať pre prichádzajúci odkaz (Universal Link, vlastná schéma), alebo nil.
    static func resolveIncoming(_ url: URL?) -> URL? {
        guard let url = url else { return nil }
        if url.scheme?.lowercased() == appScheme {
            let to = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "to" })?.value
            return fromRelative(to) ?? startURL
        }
        if isAppHost(url) { return isInAppPath(url.path) ? url : nil }
        return nil
    }

    /// Je cesta „domovská“ (prehľad klubu)? Používa sa pri rozhodnutí o geste späť.
    static func isHome(_ url: URL?) -> Bool {
        guard let u = url, isAppHost(u) else { return false }
        var p = u.path
        while p.hasSuffix("/") && p.count > 1 { p.removeLast() }
        if p == "/app" { return true }
        let parts = p.split(separator: "/")
        return parts.count == 2 && parts[0] == "app" && !["account", "new-club", "terms"].contains(String(parts[1]))
    }

    /// Hostitelia analytiky a reklamy – v appke sa nenačítajú nikdy (WKContentRuleList).
    static let blockedHosts = [
        "googletagmanager.com", "google-analytics.com", "analytics.google.com", "googleadservices.com",
        "googlesyndication.com", "doubleclick.net", "connect.facebook.net", "facebook.com", "facebook.net",
    ]

    static func contentRules() -> String {
        let rules = blockedHosts.map { h -> String in
            let esc = h.replacingOccurrences(of: ".", with: "\\\\.")
            return "{\"trigger\":{\"url-filter\":\"^https?://([^/]+\\\\.)?\(esc)[:/]\"},\"action\":{\"type\":\"block\"}}"
        }
        return "[" + rules.joined(separator: ",") + "]"
    }
}
