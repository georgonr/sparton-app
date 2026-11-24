import Foundation
import UIKit
import UserNotifications
import WebKit
import CryptoKit
import FirebaseCore
import FirebaseMessaging

/// Texty appky (Localizable.strings sk/cs/en, tyká).
func L(_ key: String) -> String { NSLocalizedString(key, comment: "") }

/// Malé trvalé nastavenia appky (UserDefaults – bez osobných údajov; token FCM je identifikátor zariadenia pre push).
enum Prefs {
    static let pushToken = "pushToken"
    static let pushRegKey = "pushRegKey"
    static let pushRegAt = "pushRegAt"
    static let pushAsked = "pushAsked"
    static let bioEnabled = "bioEnabled"
    static let bioAsked = "bioAsked"
    static var d: UserDefaults { .standard }
}

func sha256Hex(_ s: String) -> String {
    SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// Push (APNs cez Firebase Cloud Messaging, rovnako ako Android): server spartON posiela FCM HTTP v1 s blokom `apns`.
/// Registrácia zariadenia: POST /api/push/devices fetchom z prihlásenej stránky sparton.eu (cookies, CSRF pôvod),
/// po prihlásení, pri zmene tokenu alebo relácie a raz za 24 h; pri vypnutých upozorneniach DELETE.
final class PushManager: NSObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    static let shared = PushManager()
    static let sessionCookie = "sparton_session"
    private let refresh: TimeInterval = 24 * 60 * 60
    private var inFlight = false
    /// Firebase je nakonfigurovaný (zostavenie má GoogleService-Info.plist). Bez neho sa push ticho vynechá.
    private(set) var firebaseReady = false
    /// Cesta z ťuknutia na upozornenie, ktorú má appka otvoriť (spracuje ju koreňový kontrolér).
    var onOpenURL: ((URL) -> Void)?
    var onToken: ((String) -> Void)?
    private var pendingOpen: URL?

    var token: String? { Prefs.d.string(forKey: Prefs.pushToken) }

    func configure(_ application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        firebaseReady = true
        application.registerForRemoteNotifications()
    }

    func setAPNsToken(_ deviceToken: Data) {
        guard firebaseReady else { return }
        Messaging.messaging().apnsToken = deviceToken
    }

    // MARK: MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let tok = fcmToken, !tok.isEmpty else { return }
        if tok != token {
            Prefs.d.set(tok, forKey: Prefs.pushToken)
            Prefs.d.removeObject(forKey: Prefs.pushRegKey)
        }
        DispatchQueue.main.async { self.onToken?(tok) }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let path = info["url"] as? String, let url = Links.fromRelative(path) {
            DispatchQueue.main.async {
                if let open = self.onOpenURL { open(url) } else { self.pendingOpen = url }
            }
        }
        completionHandler()
    }

    func takePendingOpen() -> URL? {
        defer { pendingOpen = nil }
        return pendingOpen
    }

    // MARK: povolenie

    /// Po prvom prihlásení raz: systémová otázka na upozornenia. Vráti true, ak sa otázka zobrazila.
    func askOnce(_ done: @escaping () -> Void) -> Bool {
        guard firebaseReady, !Prefs.d.bool(forKey: Prefs.pushAsked) else { return false }
        Prefs.d.set(true, forKey: Prefs.pushAsked)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
                done()
            }
        }
        return true
    }

    // MARK: registrácia na serveri

    static func sessionKey(_ store: WKHTTPCookieStore, _ done: @escaping (String?) -> Void) {
        store.getAllCookies { cookies in
            let c = cookies.first { $0.name == sessionCookie && $0.domain.hasSuffix(Links.host) && !$0.value.isEmpty }
            done(c.map { sha256Hex($0.value) })
        }
    }

    /// Po načítaní stránky sparton.eu: zaregistruj, obnov alebo odregistruj zariadenie podľa stavu.
    func sync(_ webView: WKWebView) {
        guard firebaseReady, !inFlight, Links.isAppHost(webView.url) else { return }
        PushManager.sessionKey(webView.configuration.websiteDataStore.httpCookieStore) { sess in
            guard let sess = sess else { return }
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async { self.sync(webView, sess: sess, enabled: settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional) }
            }
        }
    }

    private func sync(_ webView: WKWebView, sess: String, enabled: Bool) {
        guard let tok = token, Links.isAppHost(webView.url) else { return }
        let key = sha256Hex(sess + "|" + tok)
        let stored = Prefs.d.string(forKey: Prefs.pushRegKey)
        if !enabled {
            if key == stored { unregister(webView, tok) }
            return
        }
        let at = Prefs.d.double(forKey: Prefs.pushRegAt)
        if key == stored && Date().timeIntervalSince1970 - at < refresh { return }
        register(webView, tok, key)
    }

    private func register(_ webView: WKWebView, _ tok: String, _ key: String) {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let body: [String: Any] = [
            "platform": "ios", "token": tok, "appVersion": v,
            "osVersion": "iOS \(UIDevice.current.systemVersion)", "deviceModel": PushManager.deviceModel(),
            "locale": Locale.current.identifier.replacingOccurrences(of: "_", with: "-"),
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: body), let b = String(data: json, encoding: .utf8),
              let kj = try? JSONSerialization.data(withJSONObject: [key]), let k = String(data: kj, encoding: .utf8) else { return }
        inFlight = true
        let js = "(function(b,k){var n=window.spartonNative;function d(o){if(n&&n.postMessage)n.postMessage(JSON.stringify(o))}" +
            "fetch('/api/push/devices',{method:'POST',credentials:'same-origin',headers:{'content-type':'application/json'},body:JSON.stringify(b)})" +
            ".then(function(r){d({type:'pushReg',ok:r.ok,status:r.status,key:k[0]})})" +
            ".catch(function(){d({type:'pushReg',ok:false,status:0,key:k[0]})})})(\(b),\(k))"
        webView.evaluateJavaScript(js, completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { self.inFlight = false }
    }

    private func unregister(_ webView: WKWebView, _ tok: String) {
        guard let json = try? JSONSerialization.data(withJSONObject: ["token": tok]), let b = String(data: json, encoding: .utf8) else { return }
        let js = "(function(b){var n=window.spartonNative;" +
            "fetch('/api/push/devices',{method:'DELETE',credentials:'same-origin',headers:{'content-type':'application/json'},body:JSON.stringify(b)})" +
            ".then(function(r){if(n&&n.postMessage)n.postMessage(JSON.stringify({type:'pushUnreg',ok:r.ok}))}).catch(function(){})})(\(b))"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func onRegistered(ok: Bool, status: Int, key: String?) {
        inFlight = false
        if ok, let key = key {
            Prefs.d.set(key, forKey: Prefs.pushRegKey)
            Prefs.d.set(Date().timeIntervalSince1970, forKey: Prefs.pushRegAt)
        } else if status == 401 {
            Prefs.d.removeObject(forKey: Prefs.pushRegKey)
        }
    }

    func onUnregistered(ok: Bool) {
        if ok {
            Prefs.d.removeObject(forKey: Prefs.pushRegKey)
            Prefs.d.removeObject(forKey: Prefs.pushRegAt)
        }
    }

    static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        let id = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return "Apple \(id)"
    }
}
