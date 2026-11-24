import UIKit
import WebKit

/// Koreň appky: webview spartON v bezpečnej oblasti (pod stavovým riadkom a nad indikátorom domovskej obrazovky
/// sú pásy vo farbe hornej a dolnej hrany stránky – rovnako ako Android), úvodná obrazovka do načítania,
/// zámok Face ID, otázky po prvom prihlásení, Nastavenia appky a otvorenie odkazov.
final class SpartonRootViewController: UIViewController, SpartonWebHost {
    static let dark = UIColor(red: 0.043, green: 0.165, blue: 0.098, alpha: 1)
    let bridgeVC = SpartonBridgeViewController()
    private let topBand = UIView()
    private let bottomBand = UIView()
    private var splash: UIView?
    private(set) var lock: BiometricLock!
    private var topColor = SpartonRootViewController.dark
    private var dialogShownThisSession = false
    private var pendingURL: URL?
    private var loadedOnce = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = SpartonRootViewController.dark
        for b in [topBand, bottomBand] {
            b.backgroundColor = SpartonRootViewController.dark
            b.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(b)
        }
        bridgeVC.host = self
        addChild(bridgeVC)
        let web = bridgeVC.view!
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            topBand.topAnchor.constraint(equalTo: view.topAnchor), topBand.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBand.trailingAnchor.constraint(equalTo: view.trailingAnchor), topBand.bottomAnchor.constraint(equalTo: view.centerYAnchor),
            bottomBand.topAnchor.constraint(equalTo: view.centerYAnchor), bottomBand.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBand.trailingAnchor.constraint(equalTo: view.trailingAnchor), bottomBand.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            web.topAnchor.constraint(equalTo: g.topAnchor), web.bottomAnchor.constraint(equalTo: g.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: g.leadingAnchor), web.trailingAnchor.constraint(equalTo: g.trailingAnchor),
        ])
        bridgeVC.didMove(toParent: self)
        showSplash()
        lock = BiometricLock(host: self)
        if #available(iOS 14.5, *) { Downloads.shared.presenter = self }

        let push = PushManager.shared
        push.onToken = { [weak self] t in self?.bridgeVC.publishPushToken(t); self?.syncPush() }
        push.onOpenURL = { [weak self] u in self?.open(u) }
        if let u = push.takePendingOpen() { pendingURL = u }
        lock.onColdStart()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        SpartonRootViewController.luminance(topColor) > 0.5 ? .darkContent : .lightContent
    }

    func presenter() -> UIViewController { self }

    // MARK: úvodná obrazovka (rovnaká ako LaunchScreen) do načítania prvej stránky, najviac 4 s

    private func showSplash() {
        let v = UIView()
        v.backgroundColor = SpartonRootViewController.dark
        v.translatesAutoresizingMaskIntoConstraints = false
        let img = UIImageView(image: UIImage(named: "Splash"))
        img.contentMode = .scaleAspectFill
        img.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(img)
        view.addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: view.topAnchor), v.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            v.leadingAnchor.constraint(equalTo: view.leadingAnchor), v.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            img.topAnchor.constraint(equalTo: v.topAnchor), img.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            img.leadingAnchor.constraint(equalTo: v.leadingAnchor), img.trailingAnchor.constraint(equalTo: v.trailingAnchor),
        ])
        splash = v
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in self?.hideSplash() }
    }

    private func hideSplash() {
        guard let s = splash else { return }
        splash = nil
        UIView.animate(withDuration: 0.25, animations: { s.alpha = 0 }, completion: { _ in s.removeFromSuperview() })
    }

    // MARK: SpartonWebHost

    func pageStarted(_ url: URL?) {}

    func pageFinished(_ url: URL?) {
        hideSplash()
        sampleBarColors()
        if !loadedOnce {
            loadedOnce = true
            if let u = pendingURL { pendingURL = nil; bridgeVC.load(u); return }
        }
        guard Links.isAppHost(url), let wv = bridgeVC.webView else { return }
        PushManager.sessionKey(wv.configuration.websiteDataStore.httpCookieStore) { [weak self] sess in
            DispatchQueue.main.async {
                guard let self = self, sess != nil else { return }
                self.afterLoginPrompts()
                self.syncPush()
            }
        }
    }

    func routeChanged(_ url: URL?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.sampleBarColors() }
    }

    func syncPush() {
        guard let wv = bridgeVC.webView, !bridgeVC.offlineShown else { return }
        PushManager.shared.sync(wv)
    }

    /// Po prihlásení raz: povolenie upozornení, pri ďalšom načítaní ponuka Face ID.
    private func afterLoginPrompts() {
        guard !dialogShownThisSession, !lock.isLocked, presentedViewController == nil else { return }
        if PushManager.shared.askOnce({ [weak self] in self?.syncPush() }) {
            dialogShownThisSession = true
            return
        }
        guard !Prefs.d.bool(forKey: Prefs.bioAsked), lock.biometricsAvailable else { return }
        Prefs.d.set(true, forKey: Prefs.bioAsked)
        dialogShownThisSession = true
        let m = lock.methodName
        let a = UIAlertController(title: String(format: L("bio.offer.title"), m), message: String(format: L("bio.offer.text"), m), preferredStyle: .alert)
        a.addAction(UIAlertAction(title: L("bio.offer.no"), style: .cancel) { [weak self] _ in self?.lock.setEnabled(false) })
        a.addAction(UIAlertAction(title: L("bio.offer.yes"), style: .default) { [weak self] _ in
            self?.lock.prompt { self?.lock.setEnabled(true) }
        })
        present(a, animated: true)
    }

    // MARK: Nastavenia appky (podržanie ikony → Nastavenia appky)

    func showSettings() {
        guard presentedViewController == nil else { return }
        let on = lock.isEnabled
        let m = lock.methodName
        let a = UIAlertController(title: L("settings.title"), message: nil, preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: String(format: L(on ? "settings.bio.off" : "settings.bio.on"), m), style: .default) { [weak self] _ in
            guard let self = self else { return }
            guard self.lock.canAuthenticate else {
                let x = UIAlertController(title: nil, message: L("settings.bio.unavailable"), preferredStyle: .alert)
                x.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(x, animated: true)
                return
            }
            self.lock.prompt { self.lock.setEnabled(!on) }
        })
        a.addAction(UIAlertAction(title: L("settings.notifications"), style: .default) { _ in
            let s: String
            if #available(iOS 16.0, *) { s = UIApplication.openNotificationSettingsURLString } else { s = UIApplication.openSettingsURLString }
            if let u = URL(string: s) { UIApplication.shared.open(u) }
        })
        a.addAction(UIAlertAction(title: L("settings.close"), style: .cancel))
        a.popoverPresentationController?.sourceView = view
        a.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(a, animated: true)
    }

    // MARK: odkazy (Universal Links, eu.sparton.app://, push)

    func open(_ url: URL) {
        if !loadedOnce { pendingURL = url; return }
        bridgeVC.load(url)
    }

    // MARK: životný cyklus

    func didEnterBackground() { lock.onBackground() }

    func willEnterForeground() {
        lock.onForeground()
        if loadedOnce, Links.isAppHost(bridgeVC.webView?.url) { syncPush() }
    }

    // MARK: farby líšt podľa stránky

    private func sampleBarColors() {
        let js = "(function(){function c(x,y){var e=document.elementFromPoint(x,y);while(e){var b=getComputedStyle(e).backgroundColor;" +
            "if(b&&b!=='transparent'&&!/,\\s*0\\)$/.test(b))return b;e=e.parentElement}" +
            "var d=document.body||document.documentElement;return d?getComputedStyle(d).backgroundColor:''}" +
            "var w=Math.max(1,Math.floor(innerWidth/2));return c(w,1)+'|'+c(w,Math.max(1,innerHeight-2))})()"
        bridgeVC.webView?.evaluateJavaScript(js) { [weak self] v, _ in
            guard let self = self, let s = v as? String else { return }
            let parts = s.split(separator: "|").map(String.init)
            guard parts.count == 2, let top = SpartonRootViewController.cssColor(parts[0]), let bottom = SpartonRootViewController.cssColor(parts[1]) else { return }
            self.topBand.backgroundColor = top
            self.bottomBand.backgroundColor = bottom
            self.topColor = top
            self.setNeedsStatusBarAppearanceUpdate()
        }
    }

    static func cssColor(_ css: String) -> UIColor? {
        let s = css.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("rgb"), let o = s.firstIndex(of: "("), let c = s.firstIndex(of: ")") else { return nil }
        let n = s[s.index(after: o)..<c].split(whereSeparator: { ",/ ".contains($0) }).compactMap { Double($0) }
        guard n.count >= 3 else { return nil }
        return UIColor(red: n[0] / 255, green: n[1] / 255, blue: n[2] / 255, alpha: 1)
    }

    static func luminance(_ c: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ x: CGFloat) -> Double { let v = Double(x); return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}
