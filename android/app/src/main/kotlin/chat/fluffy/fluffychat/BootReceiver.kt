package chat.fluffy.fluffychat

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 开机 / 应用更新后自动把后台同步服务拉起来。
 * 国产 ROM 常用 QUICKBOOT_POWERON 代替标准 BOOT_COMPLETED。
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        Log.i(TAG, "Boot/update event: $action")
        if (!BackgroundSyncService.isEnabled(context)) {
            Log.i(TAG, "Background sync disabled, not starting after $action")
            return
        }
        BackgroundSyncService.start(context)
    }

    companion object {
        private const val TAG = "QingliaoBgSync"
    }
}
