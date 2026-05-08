package co.tz.mianet.geofire;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;

import androidx.annotation.Nullable;

public class NativeTrackingForegroundService extends Service {

    static final String EXTRA_NOTIFICATION_ID = "notification_id";
    static final String EXTRA_NOTIFICATION_TITLE = "notification_title";
    static final String EXTRA_NOTIFICATION_BODY = "notification_body";
    static final String EXTRA_CHANNEL_ID = "channel_id";
    static final String EXTRA_CHANNEL_NAME = "channel_name";

    static Intent createIntent(
            Context context,
            int notificationId,
            String title,
            String body,
            String channelId,
            String channelName
    ) {
        Intent intent = new Intent(context, NativeTrackingForegroundService.class);
        intent.putExtra(EXTRA_NOTIFICATION_ID, notificationId);
        intent.putExtra(EXTRA_NOTIFICATION_TITLE, title);
        intent.putExtra(EXTRA_NOTIFICATION_BODY, body);
        intent.putExtra(EXTRA_CHANNEL_ID, channelId);
        intent.putExtra(EXTRA_CHANNEL_NAME, channelName);
        return intent;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        final int notificationId = intent != null ? intent.getIntExtra(EXTRA_NOTIFICATION_ID, 7201) : 7201;
        final String title = intent != null ? intent.getStringExtra(EXTRA_NOTIFICATION_TITLE) : "Location tracking active";
        final String body = intent != null ? intent.getStringExtra(EXTRA_NOTIFICATION_BODY) : "Updating your live location";
        final String channelId = intent != null ? intent.getStringExtra(EXTRA_CHANNEL_ID) : "geofire_native_tracking";
        final String channelName = intent != null ? intent.getStringExtra(EXTRA_CHANNEL_NAME) : "GeoFire Tracking";

        createNotificationChannel(channelId, channelName);

        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(this, channelId)
                : new Notification.Builder(this);

        Notification notification = builder
                .setContentTitle(title)
                .setContentText(body)
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setOngoing(true)
                .build();

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(notificationId, notification, ServiceInfoCompat.FOREGROUND_SERVICE_TYPE_LOCATION);
        } else {
            startForeground(notificationId, notification);
        }

        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        stopForeground(true);
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void createNotificationChannel(String channelId, String channelName) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }

        NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null) {
            return;
        }

        NotificationChannel existing = manager.getNotificationChannel(channelId);
        if (existing != null) {
            return;
        }

        NotificationChannel channel = new NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_LOW
        );
        channel.setDescription("Foreground service notification for native GeoFire tracking");
        manager.createNotificationChannel(channel);
    }

    private static final class ServiceInfoCompat {
        private static final int FOREGROUND_SERVICE_TYPE_LOCATION = 0x00000008;
    }
}
