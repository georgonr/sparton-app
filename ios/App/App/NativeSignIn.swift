import UIKit
import WebKit
import AuthenticationServices
import GoogleSignIn

/// Natívne prihlásenie cez Google a Apple (rovnaký tok ako Android `GoogleSignIn.java`). Web vo webview by
/// skončil chybou Google „disallowed_useragent“ a Sign in with Apple musí byť natívne (pravidlo 4.8), preto appka
/// zachytí odkazy /auth/google/start a /auth/apple/start a:
/// 1. stránka si vypýta nonce (GET /auth/native/nonce – server ho uloží aj do šifrovaného cookie),
/// 2. Google SDK / AuthenticationServices vráti identity token s týmto nonce (Apple s jeho SHA-256),
/// 3. stránka pošle POST /auth/native/{google|apple} a prejde na `redirect`; chyba → ?google=<kód> / ?apple=<kód>.
final class NativeSignIn: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    /// Verejné ID webového OAuth klienta spartON (projekt sparton-514413) – nie je tajné; aud tokenu Google.
    static let webClientID = "979693546215-ffjm3irso9ct05dskqun10l34kuogmls.apps.googleusercontent.com"
    static let errorCodes = ["cancelled", "failed", "unverified", "taken", "disabled", "child", "native_child", "closed",
                             "mismatch", "invite_invalid", "rate_limited", "off", "invalid_token", "invalid_request", "no_email"]

    private weak var webView: WKWebView?
    private weak var presenter: UIViewController?
    private var provider: String?
    private var pending: [String: Any]?
    private var asked = false
    private var rawNonce: String?

    init(webView: WKWebView, presenter: UIViewController) {
        self.webView = webView
        self.presenter = presenter
    }

    /// iOS OAuth klient (Google Cloud sparton-514413) – doplní sa pri zostavení (GIDClientID v Info.plist).
    static var googleClientID: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              id.hasSuffix(".apps.googleusercontent.com") else { return nil }
        return id
    }

    func start(_ provider: String, url: URL) {
        guard self.provider == nil else { return }
        if provider == "google" && NativeSignIn.googleClientID == nil {
            fail("google", "off")
            return
        }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func v(_ n: String) -> String? { q.first(where: { $0.name == n })?.value.flatMap { $0.isEmpty ? nil : $0 } }
        var b: [String: Any] = ["mode": v("mode") == "register" ? "register" : "login"]
        if let i = v("invite") { b["invite"] = i }
        if let n = v("next") { b["next"] = n }
        if let l = v("lang") { b["lang"] = l }
        self.provider = provider
        pending = b
        asked = false
        let js = "(function(){var n=window.spartonNative;function d(v){if(n&&n.postMessage)n.postMessage(JSON.stringify({type:'nonce',nonce:v}))}" +
            "fetch('/auth/native/nonce',{credentials:'same-origin'}).then(function(r){return r.json()})" +
            ".then(function(j){d(j&&j.nonce?String(j.nonce):'')}).catch(function(){d('')})})()"
        webView?.evaluateJavaScript(js, completionHandler: nil)
        // bez odpovede (sieť) sa tok po 15 s zruší – bez nonce zo servera sa neprihlasuje
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self, self.provider == provider, !self.asked else { return }
            self.finish("failed")
        }
    }

    func onNonce(_ nonce: String) {
        guard let p = provider, !asked else { return }
        guard !nonce.isEmpty else { finish("failed"); return }
        asked = true
        rawNonce = nonce
        if p == "google" { google(nonce) } else { apple(nonce) }
    }

    // MARK: Google

    private func google(_ nonce: String) {
        guard let id = NativeSignIn.googleClientID, let vc = presenter else { finish("off"); return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: id, serverClientID: NativeSignIn.webClientID)
        GIDSignIn.sharedInstance.signIn(withPresenting: vc, hint: nil, additionalScopes: nil, nonce: nonce) { [weak self] result, error in
            guard let self = self else { return }
            if let e = error as NSError? {
                self.finish(e.code == GIDSignInError.Code.canceled.rawValue ? nil : "failed")
                return
            }
            guard let token = result?.user.idToken?.tokenString else { self.finish("failed"); return }
            // relácia Google v appke sa nepotrebuje – prihlásenie drží spartON
            GIDSignIn.sharedInstance.signOut()
            self.post(["idToken": token])
        }
    }

    // MARK: Apple

    private func apple(_ nonce: String) {
        let req = ASAuthorizationAppleIDProvider().createRequest()
        req.requestedScopes = [.fullName, .email]
        req.nonce = sha256Hex(nonce)
        let c = ASAuthorizationController(authorizationRequests: [req])
        c.delegate = self
        c.presentationContextProvider = self
        c.performRequests()
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        presenter?.view.window ?? ASPresentationAnchor()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
              let t = cred.identityToken, let token = String(data: t, encoding: .utf8) else { finish("failed"); return }
        var b: [String: Any] = ["idToken": token]
        if let n = rawNonce { b["nonce"] = n }
        if let c = cred.authorizationCode, let code = String(data: c, encoding: .utf8) { b["authorizationCode"] = code }
        if let n = cred.fullName {
            var name: [String: String] = [:]
            if let g = n.givenName { name["givenName"] = g }
            if let f = n.familyName { name["familyName"] = f }
            if !name.isEmpty { b["name"] = name }
        }
        post(b)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let code = (error as? ASAuthorizationError)?.code
        finish(code == .canceled ? nil : "failed")
    }

    // MARK: odoslanie a chyby

    private func post(_ extra: [String: Any]) {
        guard let p = provider, var b = pending, let wv = webView, Links.isAppHost(wv.url) else { finish(nil); return }
        extra.forEach { b[$0.key] = $0.value }
        provider = nil
        pending = nil
        rawNonce = nil
        guard let json = try? JSONSerialization.data(withJSONObject: b), let body = String(data: json, encoding: .utf8),
              let kj = try? JSONSerialization.data(withJSONObject: NativeSignIn.errorCodes), let codes = String(data: kj, encoding: .utf8) else { return }
        let js = "(function(b,K,P){function err(c){c=K.indexOf(c)>=0?c:'failed';var u=new URL(location.href);u.searchParams.set(P,c);location.replace(u.toString())}" +
            "fetch('/auth/native/'+P,{method:'POST',credentials:'same-origin',headers:{'content-type':'application/json'},body:JSON.stringify(b)})" +
            ".then(function(r){return r.json().catch(function(){return {ok:false,code:'failed'}})})" +
            ".then(function(j){if(j&&j.redirect){location.assign(j.redirect)}else{err(j&&j.code)}})" +
            ".catch(function(){err('failed')})})(\(body),\(codes),'\(p)')"
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    private func finish(_ code: String?) {
        let p = provider ?? "google"
        provider = nil
        pending = nil
        rawNonce = nil
        guard let code = code else { return }
        fail(p, code)
    }

    /// Hláška na tej istej stránke (?google=<kód> / ?apple=<kód>, texty webu).
    private func fail(_ provider: String, _ code: String) {
        guard let wv = webView, Links.isAppHost(wv.url) else { return }
        wv.evaluateJavaScript("(function(){var u=new URL(location.href);u.searchParams.set('\(provider)','\(code)');location.replace(u.toString())})()", completionHandler: nil)
    }
}
