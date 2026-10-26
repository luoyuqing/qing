package chat.fluffy.fluffychat

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONArray
import org.json.JSONObject

/**
 * 清助理 · 通知监听服务
 *
 * 系统把通知推给我们，我们只在本地保留最近 300 条（供用户主动同步时上传到自己的 hub）。
 * 不联网、不判定内容、过滤掉本应用自己的通知。
 */
class QingNotificationListener : NotificationListenerService() {

    companion object {
        private const val PREFS = "qingzhuli_device_data"
        private const val KEY = "notifications"
        private const val MAX = 300
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val ctx = applicationContext ?: return
        if (sbn.packageName == ctx.packageName) return
        val n = sbn.notification ?: return
        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val big = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        val text = big ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        if (title.isBlank() && text.isBlank()) return

        val appName = runCatching {
            val pm = ctx.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(sbn.packageName, 0)).toString()
        }.getOrDefault(sbn.packageName)

        val obj = JSONObject().apply {
            put("package", sbn.packageName)
            put("appName", appName)
            put("title", title.take(200))
            put("text", text.take(1000))
            put("postedAt", if (sbn.postTime > 0) sbn.postTime else System.currentTimeMillis())
        }

        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val arr = runCatching { JSONArray(prefs.getString(KEY, "[]")) }.getOrElse { JSONArray() }
        val next = JSONArray()
        next.put(obj)
        var i = 0
        while (i < arr.length() && next.length() < MAX) {
            next.put(arr.getJSONObject(i))
            i++
        }
        prefs.edit().putString(KEY, next.toString()).apply()
    }
}
