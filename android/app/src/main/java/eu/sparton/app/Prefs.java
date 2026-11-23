package eu.sparton.app;

import android.content.Context;
import android.content.SharedPreferences;

/** Nastavenia appky v zariadení (žiadne tajomstvá – token FCM nie je tajný, relácia sa ukladá len ako odtlačok). */
final class Prefs {

    private static final String NAME = "sparton_app";
    static final String PUSH_TOKEN = "push_token";
    static final String PUSH_REG_KEY = "push_reg_key";
    static final String PUSH_REG_AT = "push_reg_at";
    static final String PUSH_ASKED = "push_asked";
    static final String BIO_ENABLED = "bio_enabled";
    static final String BIO_ASKED = "bio_asked";

    private Prefs() {}

    static SharedPreferences get(Context c) {
        return c.getApplicationContext().getSharedPreferences(NAME, Context.MODE_PRIVATE);
    }
}
