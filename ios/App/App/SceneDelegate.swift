import UIKit
import WebKit
import Capacitor
import GoogleSignIn

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var root: SpartonRootViewController?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: windowScene)
        // kým sa zapíše súhlas „len nevyhnutné“, ukáž úvodnú obrazovku (rovnakú ako LaunchScreen)
        w.rootViewController = UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController()
        w.makeKeyAndVisible()
        window = w

        var first: URL?
        if let u = connectionOptions.userActivities.first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb })?.webpageURL { first = Links.resolveIncoming(u) }
        if let u = connectionOptions.urlContexts.first?.url { first = Links.resolveIncoming(u) ?? first }
        let wantsSettings = connectionOptions.shortcutItem?.type == SceneDelegate.settingsShortcut

        SceneDelegate.necessaryCookiesOnly {
            let r = SpartonRootViewController()
            self.root = r
            w.rootViewController = r
            if let f = first { r.open(f) }
            if wantsSettings { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { r.showSettings() } }
            SceneDelegateProxy.shared.scene(scene, willConnectTo: session, options: connectionOptions)
        }
    }

    static let settingsShortcut = "eu.sparton.app.settings"

    /// Appka nepoužíva analytické ani marketingové cookies: súhlas „len nevyhnutné“ (formát webu, lib/consent.ts,
    /// verzia 2) sa zapíše pri každom štarte, takže sa cookie lišta webu v appke nezobrazí. Požiadavky na analytiku
    /// a reklamu navyše blokuje WKContentRuleList (pre prípad zmeny súhlasu v pätičke).
    static func necessaryCookiesOnly(_ done: @escaping () -> Void) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let props: [HTTPCookiePropertyKey: Any] = [
            .name: "sparton_consent", .value: "2.000.\(f.string(from: Date()))", .domain: ".sparton.eu", .path: "/",
            .secure: "TRUE", .expires: Date().addingTimeInterval(365 * 24 * 3600), HTTPCookiePropertyKey("SameSite"): "Lax",
        ]
        guard let c = HTTPCookie(properties: props) else { done(); return }
        WKWebsiteDataStore.default().httpCookieStore.setCookie(c) { DispatchQueue.main.async(execute: done) }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for ctx in URLContexts {
            if GIDSignIn.sharedInstance.handle(ctx.url) { continue }
            if let t = Links.resolveIncoming(ctx.url) { root?.open(t) }
        }
        SceneDelegateProxy.shared.scene(scene, openURLContexts: URLContexts)
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if userActivity.activityType == NSUserActivityTypeBrowsingWeb, let t = Links.resolveIncoming(userActivity.webpageURL) { root?.open(t) }
        SceneDelegateProxy.shared.scene(scene, continue: userActivity)
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        let ok = shortcutItem.type == SceneDelegate.settingsShortcut
        if ok { root?.showSettings() }
        completionHandler(ok)
    }

    func sceneDidEnterBackground(_ scene: UIScene) { root?.didEnterBackground() }
    func sceneWillEnterForeground(_ scene: UIScene) { root?.willEnterForeground() }
}
