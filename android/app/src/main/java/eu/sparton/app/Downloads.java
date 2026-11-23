package eu.sparton.app;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import android.webkit.CookieManager;
import androidx.annotation.RequiresApi;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;

/**
 * Stiahnutie súboru zo spartON (dokumenty, výpisy, exporty) do priečinka Stiahnuté (Android 10+, MediaStore, bez povolení).
 * Cookie relácie sa posiela len na https://sparton.eu a presmerovania sa sledujú len v rámci sparton.eu –
 * relácia sa tak nikdy nedostane na iný server.
 */
final class Downloads {

    private static final int MAX_REDIRECTS = 5;

    private Downloads() {}

    @RequiresApi(api = Build.VERSION_CODES.Q)
    static boolean save(Context c, String url, String userAgent, String name, String mimeType) {
        HttpURLConnection conn = null;
        Uri item = null;
        ContentResolver cr = c.getContentResolver();
        try {
            String current = url;
            for (int i = 0; ; i++) {
                Uri u = Uri.parse(current);
                if (!Links.isAppHost(u)) return false;
                conn = (HttpURLConnection) new URL(current).openConnection();
                conn.setInstanceFollowRedirects(false);
                conn.setConnectTimeout(20_000);
                conn.setReadTimeout(60_000);
                if (userAgent != null) conn.setRequestProperty("User-Agent", userAgent);
                String cookies = CookieManager.getInstance().getCookie(current);
                if (cookies != null) conn.setRequestProperty("Cookie", cookies);
                int code = conn.getResponseCode();
                if (code >= 300 && code < 400) {
                    String loc = conn.getHeaderField("Location");
                    conn.disconnect();
                    if (loc == null || i >= MAX_REDIRECTS) return false;
                    current = new URL(new URL(current), loc).toString();
                    continue;
                }
                if (code != 200) return false;
                break;
            }
            String type = mimeType != null && !mimeType.isEmpty() ? mimeType : conn.getContentType();
            ContentValues v = new ContentValues();
            v.put(MediaStore.Downloads.DISPLAY_NAME, name);
            if (type != null) v.put(MediaStore.Downloads.MIME_TYPE, type.split(";")[0].trim());
            v.put(MediaStore.Downloads.IS_PENDING, 1);
            item = cr.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
            if (item == null) return false;
            try (InputStream in = conn.getInputStream(); OutputStream out = cr.openOutputStream(item)) {
                if (out == null) throw new IllegalStateException("bez výstupu");
                byte[] buf = new byte[64 * 1024];
                int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            }
            ContentValues done = new ContentValues();
            done.put(MediaStore.Downloads.IS_PENDING, 0);
            cr.update(item, done, null, null);
            return true;
        } catch (Exception e) {
            if (item != null) {
                try {
                    cr.delete(item, null, null);
                } catch (Exception ignored) {}
            }
            return false;
        } finally {
            if (conn != null) conn.disconnect();
        }
    }
}
