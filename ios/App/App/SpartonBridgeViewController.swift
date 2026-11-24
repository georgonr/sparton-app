import UIKit
import WebKit
import Network
import Capacitor

/// Udalosti webview pre koreňový kontrolér (pásy, zámok, otázky po prihlásení, push).
protocol SpartonWebHost: AnyObject {
    func pageStarted(_ url: URL?)
    func pageFinished(_ url: URL?)
    func routeChanged(_ url: URL?)
    func presenter() -> UIViewController
}

/// Webview appky: produkčný spartON (https://sparton.eu/app, príznak spartON-App v User-Agent – server v appke
/// skryje nákupy a zablokuje detské účty) + natívne pravidlá navigácie, správy zo stránky, offline a sťahovanie.
final class SpartonBridgeViewController: CAPBridgeViewController, WKScriptMessageHandler {
    weak var host: SpartonWebHost?
    private var navProxy: NavigationProxy?
    private var uiProxy: UIDelegateProxy?
    private(set) var signIn: NativeSignIn?
    private var urlObservation: NSKeyValueObservation?
    private var monitor: NWPathMonitor?
    private var failedURL: URL?
    private(set) var offlineShown = false
    private var online = true

    override func capacitorDidLoad() {
        super.capacitorDidLoad()
        guard let wv = webView, let bridge = bridge else { return }
        #if DEBUG
        // len ladiace zostavenie (smoke test v GitHub Actions cez Web Inspector); vydanie ladenie nemá
        if #available(iOS 16.4, *) { wv.isInspectable = true }
        #endif
        wv.allowsBackForwardNavigationGestures = true
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        let dark = UIColor(red: 0.043, green: 0.165, blue: 0.098, alpha: 1)
        wv.backgroundColor = dark
        wv.scrollView.backgroundColor = dark

        let nav = NavigationProxy(owner: self, inner: wv.navigationDelegate)
        navProxy = nav
        wv.navigationDelegate = nav
        let ui = UIDelegateProxy(owner: self, inner: wv.uiDelegate)
        uiProxy = ui
        wv.uiDelegate = ui
        _ = bridge

        let ucc = wv.configuration.userContentController
        ucc.add(WeakMessageHandler(self), name: "spartonNative")
        ucc.addUserScript(WKUserScript(source: SpartonBridgeViewController.startScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        WKContentRuleListStore.default()?.compileContentRuleList(forIdentifier: "sparton-trackers", encodedContentRuleList: Links.contentRules()) { list, _ in
            if let list = list { DispatchQueue.main.async { ucc.add(list) } }
        }
        signIn = NativeSignIn(webView: wv, presenter: self)
        urlObservation = wv.observe(\.url, options: [.new]) { [weak self] w, _ in
            DispatchQueue.main.async { self?.host?.routeChanged(w.url) }
        }
        watchNetwork()
    }

    /// Okno appky (spartonNative) a obal fetch: pri odhlásení server odregistruje zariadenie podľa X-Push-Token.
    static let startScript = """
    (function(){var o=location.protocol+'//'+location.host;if(o!=='https://sparton.eu'&&o!=='capacitor://sparton.eu')return;
    if(!window.spartonNative){window.spartonNative={postMessage:function(s){try{window.webkit.messageHandlers.spartonNative.postMessage(String(s))}catch(e){}}}}
    if(o!=='https://sparton.eu'||window.__spartonFetch)return;window.__spartonFetch=1;var f=window.fetch;if(!f)return;
    window.fetch=function(i,op){try{var t=window.__spartonPushToken;if(t){var u=new URL(typeof i==='string'?i:(i&&i.url)||String(i),location.href);
    if(u.origin===location.origin){op=Object.assign({},op||{});var h=new Headers(op.headers||(i instanceof Request?i.headers:undefined));
    h.set('X-Push-Token',t);op.headers=h}}}catch(e){}return f.call(this,i,op)}})();
    """

    // MARK: správy zo stránky

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard message.frameInfo.isMainFrame, origin.host.lowercased() == Links.host,
              let s = message.body as? String, let data = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let https = origin.protocol.lowercased() == "https"
        switch o["type"] as? String {
        case "retry": retry()
        case "nonce" where https: signIn?.onNonce(o["nonce"] as? String ?? "")
        case "pushReg" where https: PushManager.shared.onRegistered(ok: o["ok"] as? Bool ?? false, status: o["status"] as? Int ?? 0, key: o["key"] as? String)
        case "pushUnreg" where https: PushManager.shared.onUnregistered(ok: o["ok"] as? Bool ?? false)
        default: break
        }
    }

    func publishPushToken(_ token: String) {
        guard let wv = webView, Links.isAppHost(wv.url),
              let j = try? JSONSerialization.data(withJSONObject: [token]), let s = String(data: j, encoding: .utf8) else { return }
        wv.evaluateJavaScript("window.__spartonPushToken=\(s)[0];", completionHandler: nil)
    }

    func load(_ url: URL) {
        failedURL = nil
        webView?.load(URLRequest(url: url))
    }

    // MARK: navigácia

    /// Rozhodnutie pre navigáciu; nil = nechaj na Capacitor.
    fileprivate func decide(_ action: WKNavigationAction) -> WKNavigationActionPolicy? {
        if #available(iOS 14.5, *), action.shouldPerformDownload { return .download }
        guard let url = action.request.url else { return .cancel }
        let main = action.targetFrame?.isMainFrame ?? true
        // vnorené rámce (Cloudflare Turnstile, platobné prvky) sa načítajú normálne
        if !main { return .allow }
        if let p = Links.signInStart(url) {
            // len z hlavného rámca stránky spartON (nie z cudzej stránky)
            if Links.isAppHost(webView?.url) { signIn?.start(p, url: url) }
            return .cancel
        }
        if Links.isLocalOffline(url) { return .allow }
        if Links.isAppHost(url) {
            if Links.isInAppPath(url.path) { return .allow }
            openExternal(url)
            return .cancel
        }
        let scheme = url.scheme?.lowercased() ?? ""
        // hlavný rámec appky je vždy https://sparton.eu – data:, blob: a iné schémy sa v ňom nenačítajú
        if ["data", "blob", "about", "javascript", "file"].contains(scheme) { return .cancel }
        openExternal(url)
        return .cancel
    }

    func openExternal(_ url: URL) {
        guard view.window?.windowScene?.activationState == .foregroundActive else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    fileprivate func decide(_ response: WKNavigationResponse) -> WKNavigationResponsePolicy {
        let url = response.response.url
        let attachment = ((response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? "")
            .lowercased().contains("attachment")
        if attachment || !response.canShowMIMEType {
            // súbory len zo sparton.eu (cookie relácie sa inam neposiela); iné cez Safari
            guard Links.isAppHost(url) else {
                if let u = url, response.isForMainFrame { openExternal(u) }
                return .cancel
            }
            if #available(iOS 14.5, *) { return .download }
            if let u = url { openExternal(u) }
            return .cancel
        }
        return .allow
    }

    fileprivate func started(_ url: URL?) {
        host?.pageStarted(url)
    }

    fileprivate func finished(_ url: URL?) {
        offlineShown = Links.isLocalOffline(url)
        if !offlineShown { failedURL = nil }
        if let t = PushManager.shared.token { publishPushToken(t) }
        host?.pageFinished(url)
    }

    /// Obrazovka „si offline“ len pri sieťovej chybe hlavného rámca (nie pri HTTP 404/500 – tie ukáže web sám).
    fileprivate func failed(_ error: Error) {
        let e = error as NSError
        guard e.domain == NSURLErrorDomain, SpartonBridgeViewController.networkCodes.contains(e.code) else { return }
        let failing = (e.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? webView?.url
        if let f = failing, Links.isLocalOffline(f) { return }
        failedURL = failing.flatMap { Links.isAppHost($0) ? $0 : nil }
        offlineShown = true
        if let errorURL = bridge?.config.errorPathURL { webView?.load(URLRequest(url: errorURL)) }
    }

    static let networkCodes: Set<Int> = [
        NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
        NSURLErrorNetworkConnectionLost, NSURLErrorDNSLookupFailed, NSURLErrorInternationalRoamingOff,
        NSURLErrorDataNotAllowed, NSURLErrorCallIsActive, NSURLErrorSecureConnectionFailed,
    ]

    func retry() {
        load(failedURL ?? Links.startURL)
    }

    private func watchNetwork() {
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let now = path.status == .satisfied
                if now && !self.online && self.offlineShown { self.retry() }
                self.online = now
            }
        }
        m.start(queue: DispatchQueue(label: "sparton.network"))
        monitor = m
    }

    deinit { monitor?.cancel() }
}

/// Správy zo stránky bez cyklu referencií (WKUserContentController drží handler silno).
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) { target?.userContentController(c, didReceive: m) }
}

/// Navigačný delegát appky pred delegátom Capacitor: vlastné pravidlá odkazov, offline a sťahovanie;
/// ostatné správy (overenie servera, pád procesu…) idú ďalej do Capacitor.
final class NavigationProxy: NSObject, WKNavigationDelegate {
    weak var owner: SpartonBridgeViewController?
    weak var inner: WKNavigationDelegate?

    init(owner: SpartonBridgeViewController, inner: WKNavigationDelegate?) {
        self.owner = owner
        self.inner = inner
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (inner?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        (inner?.responds(to: aSelector) ?? false) ? inner : nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let p = owner?.decide(navigationAction) { decisionHandler(p); return }
        if let h = inner as? WebViewDelegationHandler {
            h.webView(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(owner?.decide(navigationResponse) ?? .allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        inner?.webView?(webView, didStartProvisionalNavigation: navigation)
        owner?.started(webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        inner?.webView?(webView, didFinish: navigation)
        owner?.finished(webView.url)
    }

    // Zámerne bez Capacitor: ten by pri akejkoľvek chybe (aj zrušenej navigácii alebo sťahovaní) ukázal offline.
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        owner?.failed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        owner?.failed(error)
    }

    @available(iOS 14.5, *)
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = Downloads.shared
    }

    @available(iOS 14.5, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = Downloads.shared
    }
}

/// UI delegát: target=_blank a window.open → rovnaké pravidlá ako odkaz v hlavnom rámci (Android: jedno okno).
final class UIDelegateProxy: NSObject, WKUIDelegate {
    weak var owner: SpartonBridgeViewController?
    weak var inner: WKUIDelegate?

    init(owner: SpartonBridgeViewController, inner: WKUIDelegate?) {
        self.owner = owner
        self.inner = inner
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (inner?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        (inner?.responds(to: aSelector) ?? false) ? inner : nil
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if Links.isAppHost(url) && Links.isInAppPath(url.path) {
            webView.load(URLRequest(url: url))
        } else if Links.signInStart(url) == nil, !["data", "blob", "about", "javascript", "file"].contains(url.scheme?.lowercased() ?? "") {
            owner?.openExternal(url)
        }
        return nil
    }
}

/// Sťahovanie súborov (doklady, výpisy, exporty): súbor do dočasného priečinka appky a systémové „Zdieľať / Uložiť do Súborov“.
@available(iOS 14.5, *)
final class Downloads: NSObject, WKDownloadDelegate {
    static let shared = Downloads()
    weak var presenter: UIViewController?
    private var files: [ObjectIdentifier: URL] = [:]

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = suggestedFilename.replacingOccurrences(of: "/", with: "_")
        let dest = dir.appendingPathComponent(safe.isEmpty ? "sparton" : safe)
        try? FileManager.default.removeItem(at: dest)
        files[ObjectIdentifier(download)] = dest
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = files.removeValue(forKey: ObjectIdentifier(download)), let vc = presenter else { return }
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = vc.view
        share.popoverPresentationController?.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 1, height: 1)
        vc.present(share, animated: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        files.removeValue(forKey: ObjectIdentifier(download))
        guard let vc = presenter else { return }
        let a = UIAlertController(title: nil, message: L("download.failed"), preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        vc.present(a, animated: true)
    }
}
