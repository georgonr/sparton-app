package eu.sparton.app;

import android.net.Uri;
import android.os.CancellationSignal;
import android.webkit.WebView;
import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;
import androidx.credentials.Credential;
import androidx.credentials.CredentialManager;
import androidx.credentials.CredentialManagerCallback;
import androidx.credentials.CustomCredential;
import androidx.credentials.GetCredentialRequest;
import androidx.credentials.GetCredentialResponse;
import androidx.credentials.exceptions.GetCredentialCancellationException;
import androidx.credentials.exceptions.GetCredentialException;
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption;
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential;
import org.json.JSONObject;

/**
 * Natívne prihlásenie cez Google (Credential Manager). Web vo webview by skončil chybou Google „disallowed_useragent“,
 * preto appka zachytí odkaz /auth/google/start a:
 * 1. stránka si vypýta nonce (GET /auth/native/nonce, server ho uloží aj do šifrovaného cookie),
 * 2. Credential Manager vráti ID token pre webového klienta spartON (aud) s týmto nonce,
 * 3. stránka pošle POST /auth/native/google {idToken, mode, invite, next, lang} a prejde na `redirect`.
 * Chyba sa ukáže na tej istej stránke cez ?google=<kód> (hlášky webu).
 */
final class GoogleSignIn {

    /** Verejné ID webového OAuth klienta spartON (projekt sparton-514413) – nie je tajné. */
    static final String WEB_CLIENT_ID = "979693546215-ffjm3irso9ct05dskqun10l34kuogmls.apps.googleusercontent.com";

    private final MainActivity activity;
    private JSONObject pending;
    private boolean running = false;

    GoogleSignIn(MainActivity activity) {
        this.activity = activity;
    }

    /** Odkaz /auth/google/start?mode=…&lang=…&next=…&invite=… */
    void start(Uri startUrl) {
        if (running) return;
        try {
            String mode = startUrl.getQueryParameter("mode");
            String invite = startUrl.getQueryParameter("invite");
            JSONObject b = new JSONObject();
            b.put("mode", "register".equals(mode) ? "register" : "login");
            if (invite != null && !invite.isEmpty()) b.put("invite", invite);
            String next = startUrl.getQueryParameter("next");
            if (next != null && !next.isEmpty()) b.put("next", next);
            String lang = startUrl.getQueryParameter("lang");
            if (lang != null && !lang.isEmpty()) b.put("lang", lang);
            pending = b;
            running = true;
        } catch (Exception e) {
            return;
        }
        WebView wv = activity.getBridge().getWebView();
        wv.evaluateJavascript(
            "(function(){var n=window.spartonNative;function d(v){if(n&&n.postMessage)n.postMessage(JSON.stringify({type:'gnonce',nonce:v}))}" +
                "fetch('/auth/native/nonce',{credentials:'same-origin'}).then(function(r){return r.json()})" +
                ".then(function(j){d(j&&j.nonce?String(j.nonce):'')}).catch(function(){d('')})})()",
            null
        );
        // bez odpovede (veľmi staré WebView bez správ, sieť) sa tok po 15 s zruší – bez nonce zo servera sa neprihlasuje
        wv.postDelayed(
            () -> {
                if (running && pending != null && !pending.has("_asked")) finish("failed");
            },
            15000
        );
    }

    void onNonce(String nonce) {
        if (!running || pending == null || pending.has("_asked")) return;
        if (nonce == null || nonce.isEmpty()) {
            finish("failed");
            return;
        }
        try {
            pending.put("_asked", true);
        } catch (Exception ignored) {}
        GetSignInWithGoogleOption.Builder ob = new GetSignInWithGoogleOption.Builder(WEB_CLIENT_ID);
        ob.setNonce(nonce);
        GetCredentialRequest req = new GetCredentialRequest.Builder().addCredentialOption(ob.build()).build();
        CredentialManager cm = CredentialManager.create(activity);
        cm.getCredentialAsync(
            activity,
            req,
            new CancellationSignal(),
            ContextCompat.getMainExecutor(activity),
            new CredentialManagerCallback<GetCredentialResponse, GetCredentialException>() {
                @Override
                public void onResult(GetCredentialResponse result) {
                    Credential c = result.getCredential();
                    if (c instanceof CustomCredential && GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL.equals(c.getType())) {
                        try {
                            String idToken = GoogleIdTokenCredential.createFrom(c.getData()).getIdToken();
                            post(idToken);
                            return;
                        } catch (Exception ignored) {}
                    }
                    finish("failed");
                }

                @Override
                public void onError(@NonNull GetCredentialException e) {
                    finish(e instanceof GetCredentialCancellationException ? null : "failed");
                }
            }
        );
    }

    private void post(String idToken) {
        if (!activity.isOnAppPage()) {
            finish(null);
            return;
        }
        try {
            JSONObject b = new JSONObject(pending.toString());
            b.remove("_asked");
            b.put("idToken", idToken);
            running = false;
            pending = null;
            String js =
                "(function(b){var K=['cancelled','failed','unverified','taken','disabled','child','closed','mismatch','invite_invalid','rate_limited','off'];" +
                "function err(c){c=K.indexOf(c)>=0?c:'failed';var u=new URL(location.href);u.searchParams.set('google',c);location.replace(u.toString())}" +
                "fetch('/auth/native/google',{method:'POST',credentials:'same-origin',headers:{'content-type':'application/json'},body:JSON.stringify(b)})" +
                ".then(function(r){return r.json().catch(function(){return {ok:false,code:'failed'}})})" +
                ".then(function(j){if(j&&j.redirect){location.assign(j.redirect)}else{err(j&&j.code)}})" +
                ".catch(function(){err('failed')})})(" +
                b +
                ")";
            activity.getBridge().getWebView().evaluateJavascript(js, null);
        } catch (Exception e) {
            finish("failed");
        }
    }

    /** Koniec bez prihlásenia: null = používateľ zrušil (bez hlášky), inak kód pre ?google=. */
    private void finish(String code) {
        running = false;
        pending = null;
        if (code == null || !activity.isOnAppPage()) return;
        activity
            .getBridge()
            .getWebView()
            .evaluateJavascript(
                "(function(){var u=new URL(location.href);u.searchParams.set('google'," + JSONObject.quote(code) + ");location.replace(u.toString())})()",
                null
            );
    }
}
