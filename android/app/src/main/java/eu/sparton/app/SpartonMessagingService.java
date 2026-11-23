package eu.sparton.app;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import androidx.annotation.NonNull;
import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;
import java.util.Map;

/**
 * Push zo servera spartON (FCM HTTP v1: notification {title, body}, data {url, tag}).
 * Na pozadí správu zobrazí systém (kanál a ikona z manifestu, ťuknutie otvorí appku s extra „url“);
 * v popredí ju zobrazí táto služba rovnako.
 */
public class SpartonMessagingService extends FirebaseMessagingService {

    static final String CHANNEL_ID = "sparton";
    static final String EXTRA_URL = "url";

    @Override
    public void onNewToken(@NonNull String token) {
        PushRegistrar.onNewToken(this, token);
    }

    @Override
    public void onMessageReceived(@NonNull RemoteMessage message) {
        RemoteMessage.Notification n = message.getNotification();
        Map<String, String> data = message.getData();
        String title = n != null && n.getTitle() != null ? n.getTitle() : data.get("title");
        String body = n != null && n.getBody() != null ? n.getBody() : data.get("body");
        if (title == null && body == null) return;
        String url = data.get(EXTRA_URL);
        String tag = data.get("tag");
        show(this, title, body, url, tag);
    }

    static void ensureChannel(Context c) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager nm = c.getSystemService(NotificationManager.class);
        if (nm == null || nm.getNotificationChannel(CHANNEL_ID) != null) return;
        NotificationChannel ch = new NotificationChannel(CHANNEL_ID, c.getString(R.string.push_channel_name), NotificationManager.IMPORTANCE_HIGH);
        ch.setDescription(c.getString(R.string.push_channel_description));
        nm.createNotificationChannel(ch);
    }

    static void show(Context c, String title, String body, String url, String tag) {
        if (!NotificationManagerCompat.from(c).areNotificationsEnabled()) return;
        ensureChannel(c);
        Intent open = new Intent(c, MainActivity.class).setAction(Intent.ACTION_VIEW).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        if (url != null) open.putExtra(EXTRA_URL, url);
        int id = (tag != null ? tag : String.valueOf(System.currentTimeMillis())).hashCode();
        PendingIntent pi = PendingIntent.getActivity(c, id, open, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        NotificationCompat.Builder b = new NotificationCompat.Builder(c, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_sparton)
            .setColor(ContextCompat.getColor(c, R.color.sparton_green))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(new NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pi);
        try {
            NotificationManagerCompat.from(c).notify(tag != null ? tag : null, tag != null ? 1 : id, b.build());
        } catch (SecurityException ignored) {
            // POST_NOTIFICATIONS odobraté medzi kontrolou a zobrazením
        }
    }
}
