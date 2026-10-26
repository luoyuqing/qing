package chat.fluffy.fluffychat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * 常驻前台服务（dataSync），让 Flutter/Dart 隔离区活着，Matrix 客户端才能
 * 用 `/sync` 长轮询收消息 —— 不需要 Firebase，也不需要 ntfy。
 *
 * 真正的同步循环在 Dart 侧；这里只负责：
 *  - 持有 dataSync 前台通知（新系统强制要求）
 *  - 进程被杀后 START_STICKY 重启
 *  - 被广播接收器唤醒时把 Flutter 引擎拉起来
 */
class BackgroundSyncService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startInForeground()
        WatchdogReceiver.schedule(this)
        ensureFlutterEngine()
        Log.i(TAG, "Background sync service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            Log.i(TAG, "Stop requested")
            WatchdogReceiver.cancel(this)
            stopInForeground()
            stopSelf()
            return START_NOT_STICKY
        }
        createChannel()
        startInForeground()
        WatchdogReceiver.schedule(this)
        ensureFlutterEngine()
        return START_STICKY
    }

    override fun onTimeout(startId: Int) {
        Log.w(TAG, "onTimeout(startId=$startId), restarting")
        restartSelf()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        Log.w(TAG, "onTimeout(startId=$startId, type=$fgsType), restarting")
        restartSelf()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // 用户从最近任务划掉 App 也继续跑
        Log.i(TAG, "Task removed, service stays alive")
        start(applicationContext)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        WatchdogReceiver.cancel(this)
        Log.i(TAG, "Service destroyed")
        super.onDestroy()
    }

    private fun restartSelf() {
        WatchdogReceiver.schedule(this, delayMs = 1_000L)
        stopInForeground()
        stopSelf()
        start(applicationContext)
    }

    private fun stopInForeground() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun ensureFlutterEngine() {
        try {
            val engine = MainActivity.provideEngine(applicationContext)
            if (!engine.dartExecutor.isExecutingDart) {
                engine.localizationPlugin.sendLocalesToFlutter(resources.configuration)
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint.createDefault(),
                )
                Log.i(TAG, "Flutter engine started from background service")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Unable to start Flutter engine", e)
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        // 渠道重要性创建后不可改：旧渠道是 IMPORTANCE_LOW（普通常驻通知），
        // 换新 ID 用 IMPORTANCE_MIN 重建，并把旧渠道删掉。
        // MIN：状态栏不显示图标、不折叠进通知列表，只沉在通知栏底部
        // 「正在运行」分组里，把存在感降到系统允许的最低。
        manager.deleteNotificationChannel(LEGACY_CHANNEL_ID)
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.background_sync_channel),
            NotificationManager.IMPORTANCE_MIN,
        ).apply {
            description = getString(R.string.background_sync_channel_desc)
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
            lockscreenVisibility = Notification.VISIBILITY_SECRET
        }
        manager.createNotificationChannel(channel)
    }

    private fun startInForeground() {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val contentIntent = PendingIntent.getActivity(this, 0, launchIntent, flags)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.background_sync_title))
            .setContentText(getString(R.string.background_sync_text))
            .setSmallIcon(R.drawable.notifications_icon)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()
    }

    companion object {
        private const val TAG = "QingliaoBgSync"
        const val CHANNEL_ID = "qingliao_background_sync_v2"
        const val LEGACY_CHANNEL_ID = "qingliao_background_sync"
        const val NOTIFICATION_ID = 0x514C414F
        const val ACTION_START = "chat.qingliao.START_BACKGROUND_SYNC"
        const val ACTION_STOP = "chat.qingliao.STOP_BACKGROUND_SYNC"
        private const val PREFS = "qingliao_bg_sync"
        private const val ENABLED_KEY = "enabled"

        fun isEnabled(context: Context): Boolean {
            return context.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getBoolean(ENABLED_KEY, false)
        }

        fun setEnabled(context: Context, enabled: Boolean) {
            context.applicationContext
                .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean(ENABLED_KEY, enabled)
                .apply()
        }

        fun start(context: Context) {
            val app = context.applicationContext
            setEnabled(app, true)
            val intent = Intent(app, BackgroundSyncService::class.java).setAction(ACTION_START)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    app.startForegroundService(intent)
                } else {
                    app.startService(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Unable to start background sync service", e)
            }
        }

        fun stop(context: Context) {
            val app = context.applicationContext
            setEnabled(app, false)
            val intent = Intent(app, BackgroundSyncService::class.java).setAction(ACTION_STOP)
            try {
                app.startService(intent)
            } catch (e: Exception) {
                Log.w(TAG, "Unable to deliver stop intent, stopping directly", e)
                app.stopService(Intent(app, BackgroundSyncService::class.java))
            }
        }
    }
}
