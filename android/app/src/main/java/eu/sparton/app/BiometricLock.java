package eu.sparton.app;

import android.os.Build;
import android.os.SystemClock;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import androidx.annotation.NonNull;
import androidx.biometric.BiometricManager;
import androidx.biometric.BiometricPrompt;
import androidx.core.content.ContextCompat;

/**
 * Biometrické odomknutie appky (odtlačok, tvár alebo zámok zariadenia). Zapína sa po prihlásení (otázka raz)
 * alebo v Nastaveniach appky (dlhé podržanie ikony → Nastavenia appky). Pri štarte a po návrate z pozadia
 * dlhšom ako LOCK_AFTER_MS prekryje obsah, kým sa používateľ neoverí. Biometrické údaje ostávajú v zariadení.
 */
final class BiometricLock {

    static final long LOCK_AFTER_MS = 5L * 60 * 1000;
    static final int AUTHENTICATORS = BiometricManager.Authenticators.BIOMETRIC_WEAK | BiometricManager.Authenticators.DEVICE_CREDENTIAL;

    private final MainActivity activity;
    private View overlay;
    private long backgroundAt = 0;
    private boolean prompting = false;

    BiometricLock(MainActivity activity) {
        this.activity = activity;
    }

    boolean isEnabled() {
        return Prefs.get(activity).getBoolean(Prefs.BIO_ENABLED, false);
    }

    /** Je v zariadení nastavený odtlačok/tvár (ponuka po prihlásení) – bez nich ponuku nezobrazíme. */
    boolean biometricsAvailable() {
        return BiometricManager.from(activity).canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK) == BiometricManager.BIOMETRIC_SUCCESS;
    }

    boolean canAuthenticate() {
        return BiometricManager.from(activity).canAuthenticate(AUTHENTICATORS) == BiometricManager.BIOMETRIC_SUCCESS;
    }

    boolean isLocked() {
        return overlay != null && overlay.getVisibility() == View.VISIBLE;
    }

    void onBackground() {
        backgroundAt = SystemClock.elapsedRealtime();
    }

    /** Studený štart – zamkni hneď, ak je zámok zapnutý. */
    void onColdStart() {
        if (isEnabled()) lock();
    }

    /** Návrat z pozadia. */
    void onForeground() {
        if (!isEnabled() || isLocked()) return;
        if (backgroundAt > 0 && SystemClock.elapsedRealtime() - backgroundAt > LOCK_AFTER_MS) lock();
        backgroundAt = 0;
    }

    void lock() {
        if (!canAuthenticate()) {
            // používateľ odstránil zámok zariadenia – zámok appky by ho zamkol navždy, preto sa vypne
            Prefs.get(activity).edit().putBoolean(Prefs.BIO_ENABLED, false).apply();
            hide();
            return;
        }
        if (overlay == null) {
            overlay = LayoutInflater.from(activity).inflate(R.layout.lock_overlay, (ViewGroup) activity.getWindow().getDecorView(), false);
            overlay.setClickable(true);
            Button b = overlay.findViewById(R.id.lock_unlock);
            b.setOnClickListener(v -> prompt(null));
            ((ViewGroup) activity.getWindow().getDecorView()).addView(overlay);
        }
        overlay.setVisibility(View.VISIBLE);
        overlay.post(() -> prompt(null));
    }

    private void hide() {
        if (overlay != null) overlay.setVisibility(View.GONE);
    }

    /** Overenie; bez callbacku odomkne appku, s callbackom potvrdí zmenu nastavenia. */
    void prompt(Runnable onSuccess) {
        if (prompting) return;
        prompting = true;
        BiometricPrompt.PromptInfo.Builder info = new BiometricPrompt.PromptInfo.Builder()
            .setTitle(activity.getString(R.string.bio_prompt_title))
            .setSubtitle(activity.getString(R.string.bio_prompt_subtitle))
            .setAllowedAuthenticators(AUTHENTICATORS);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            info.setConfirmationRequired(false);
        }
        BiometricPrompt p = new BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(activity),
            new BiometricPrompt.AuthenticationCallback() {
                @Override
                public void onAuthenticationSucceeded(@NonNull BiometricPrompt.AuthenticationResult result) {
                    prompting = false;
                    if (onSuccess != null) onSuccess.run();
                    else hide();
                }

                @Override
                public void onAuthenticationError(int errorCode, @NonNull CharSequence errString) {
                    prompting = false;
                    // zámok ostáva; tlačidlo „Odomknúť“ skúsi znova
                }
            }
        );
        try {
            p.authenticate(info.build());
        } catch (Exception e) {
            prompting = false;
        }
    }

    void setEnabled(boolean on) {
        Prefs.get(activity).edit().putBoolean(Prefs.BIO_ENABLED, on).putBoolean(Prefs.BIO_ASKED, true).apply();
    }
}
