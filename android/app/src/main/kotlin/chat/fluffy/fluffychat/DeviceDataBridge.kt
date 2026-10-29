package chat.fluffy.fluffychat

import android.Manifest
import android.app.Activity
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.CalendarContract
import android.provider.MediaStore
import android.provider.ContactsContract
import android.provider.Settings
import android.provider.Telephony
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
import java.lang.ref.WeakReference
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Qing · 设备数据桥
 *
 * 只读采集：通知（通知监听服务缓存）、日历、通讯录、应用使用时长。
 * 全部在本机读取，交给 Dart 侧上传到用户自己的 device-hub。
 */
object DeviceDataBridge : MethodChannel.MethodCallHandler {
    private const val CHANNEL = "chat.qingzhuli/device_data"
    private const val PREFS = "qingzhuli_device_data"
    private const val REQ_PERMS = 4101

    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var activityRef: WeakReference<Activity>? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    fun register(messenger: BinaryMessenger, context: Context) {
        val ch = MethodChannel(messenger, CHANNEL)
        ch.setMethodCallHandler(this)
        channel = ch
        appContext = context.applicationContext
    }

    fun attachActivity(activity: Activity) {
        activityRef = WeakReference(activity)
        appContext = activity.applicationContext
    }

    private fun ctx(): Context? = appContext ?: activityRef?.get()?.applicationContext

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(statusMap())
            "openNotificationSettings" -> openSettings(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS, result)
            "openUsageSettings" -> openSettings(Settings.ACTION_USAGE_ACCESS_SETTINGS, result)
            "openAppSettings" -> {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", ctx()?.packageName, null)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                runCatching { ctx()?.startActivity(intent) }
                result.success(true)
            }
            "requestCalendarContacts" -> requestCalendarContacts(result)
            "requestSms" -> requestSms(result)
            "sms" -> result.success(readSms(
                call.argument<Int>("limit") ?: 50,
                call.argument<String>("query") ?: "",
            ))
            "requestLocation" -> requestPermission(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION), result)
            "requestFiles" -> requestFiles(result)
            "openAllFilesAccess" -> openAllFilesAccess(result)
            "notifications" -> result.success(readNotifications(call.argument<Int>("limit") ?: 50))
            // 通知黑名单：列出已安装应用 / 读当前黑名单 / 保存黑名单
            "installedApps" -> result.success(installedApps())
            "notifyBlacklist" -> {
                val c = ctx()
                result.success(if (c == null) emptyList<String>() else NotifyBlacklist.get(c).toList())
            }
            "setNotifyBlacklist" -> {
                val c = ctx()
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                if (c != null) NotifyBlacklist.set(c, packages)
                result.success(true)
            }
            "calendar" -> {
                val from = call.argument<Long>("fromMs") ?: (System.currentTimeMillis() - 86_400_000L)
                val to = call.argument<Long>("toMs") ?: (System.currentTimeMillis() + 30L * 86_400_000L)
                result.success(readCalendar(from, to))
            }
            "contacts" -> result.success(readContacts(call.argument<Int>("limit") ?: 500))
            "location" -> result.success(readLocation())
            "files" -> result.success(readFiles(
                call.argument<Int>("limit") ?: 30,
                call.argument<String>("query") ?: "",
            ))
            "usage" -> {
                val from = call.argument<Long>("fromMs") ?: startOfToday()
                val to = call.argument<Long>("toMs") ?: System.currentTimeMillis()
                result.success(readUsage(from, to))
            }
            else -> result.notImplemented()
        }
    }

    private fun openSettings(action: String, result: MethodChannel.Result) {
        val intent = Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { ctx()?.startActivity(intent) }
        result.success(true)
    }

    private fun statusMap(): Map<String, Any> {
        val c = ctx()
        val notificationEnabled = c != null && run {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                val nm = c.getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
                nm?.isNotificationListenerAccessGranted(
                    android.content.ComponentName(c, QingNotificationListener::class.java)
                ) ?: false
            } else {
                Settings.Secure.getString(c.contentResolver, "enabled_notification_listeners")
                    ?.contains(c.packageName) == true
            }
        }
        val calendar = c != null && ContextCompat.checkSelfPermission(c, Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED
        val contacts = c != null && ContextCompat.checkSelfPermission(c, Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED
        // Qing v1.9.0：短信只读（READ_SMS），不申请 SEND_SMS / RECEIVE_SMS
        val sms = hasSmsAccess(c)
        val usage = hasUsageAccess(c)
        val location = c != null && (ContextCompat.checkSelfPermission(c, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(c, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED)
        val files = c != null && hasFileAccess(c)
        return mapOf(
            "notification" to notificationEnabled,
            "calendar" to calendar,
            "contacts" to contacts,
            "sms" to sms,
            "usage" to usage,
            "location" to location,
            "files" to files,
            "all_files" to (Build.VERSION.SDK_INT >= 30 && Environment.isExternalStorageManager()),
            "android" to Build.VERSION.RELEASE,
            "model" to "${Build.MANUFACTURER} ${Build.MODEL}",
        )
    }

    private fun hasSmsAccess(c: Context?): Boolean {
        if (c == null) return false
        return ContextCompat.checkSelfPermission(c, Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasUsageAccess(c: Context?): Boolean {
        if (c == null) return false
        val appOps = c.getSystemService(Context.APP_OPS_SERVICE) as? android.app.AppOpsManager ?: return false
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(), c.packageName)
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(android.app.AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(), c.packageName)
        }
        return mode == android.app.AppOpsManager.MODE_ALLOWED
    }

    private fun hasFileAccess(c: Context): Boolean {
        if (Build.VERSION.SDK_INT >= 30 && android.os.Environment.isExternalStorageManager()) {
            return true
        }
        return if (Build.VERSION.SDK_INT >= 33) {
            listOf(
                Manifest.permission.READ_MEDIA_IMAGES,
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_AUDIO,
            ).any { ContextCompat.checkSelfPermission(c, it) == PackageManager.PERMISSION_GRANTED }
        } else {
            ContextCompat.checkSelfPermission(c, Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    /** Android 13+ 走媒体权限；12 及以下走存储权限。 */
    private fun requestFiles(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 33) {
            requestPermission(
                arrayOf(
                    Manifest.permission.READ_MEDIA_IMAGES,
                    Manifest.permission.READ_MEDIA_VIDEO,
                    Manifest.permission.READ_MEDIA_AUDIO,
                ),
                result,
            )
        } else {
            requestPermission(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE), result)
        }
    }

    /** 「所有文件访问权限」— 只有它能列出非媒体文件（文档/下载/压缩包）。 */
    private fun openAllFilesAccess(result: MethodChannel.Result) {
        val c = ctx()
        if (c == null || Build.VERSION.SDK_INT < 30) {
            result.success(false)
            return
        }
        val ok = runCatching {
            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).apply {
                data = Uri.parse("package:${c.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            c.startActivity(intent)
        }.recoverCatching {
            c.startActivity(
                Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }.isSuccess
        result.success(ok)
    }

    private fun requestPermission(perms: Array<String>, result: MethodChannel.Result) {
        val activity = activityRef?.get()
        if (activity == null) {
            result.error("no_activity", "需要在前台页面申请权限", null)
            return
        }
        val missing = perms.filter {
            ContextCompat.checkSelfPermission(activity, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(statusMap())
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(activity, missing.toTypedArray(), REQ_PERMS)
    }

    /** Qing v1.9.0：短信只读授权（只要 READ_SMS） */
    private fun requestSms(result: MethodChannel.Result) {
        requestPermission(arrayOf(Manifest.permission.READ_SMS), result)
    }

    private fun requestCalendarContacts(result: MethodChannel.Result) {
        val activity = activityRef?.get()
        if (activity == null) {
            result.error("no_activity", "需要在前台页面申请权限", null)
            return
        }
        val missing = mutableListOf<String>()
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) {
            missing.add(Manifest.permission.READ_CALENDAR)
        }
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) {
            missing.add(Manifest.permission.READ_CONTACTS)
        }
        if (missing.isEmpty()) {
            result.success(statusMap())
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(activity, missing.toTypedArray(), REQ_PERMS)
    }

    fun onRequestPermissionsResult(requestCode: Int) {
        if (requestCode != REQ_PERMS) return
        pendingPermissionResult?.success(statusMap())
        pendingPermissionResult = null
    }

    // ---------- 通知 ----------
    private fun readNotifications(limit: Int): List<Map<String, Any?>> {
        val c = ctx() ?: return emptyList()
        val prefs = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString("notifications", "[]") ?: "[]"
        // 黑名单里已有的旧记录也不返回，避免"刚屏蔽还在列表里"
        val blocked = NotifyBlacklist.get(c)
        return runCatching {
            val arr = org.json.JSONArray(raw)
            val out = ArrayList<Map<String, Any?>>()
            var i = arr.length() - 1
            while (i >= 0 && out.size < limit) {
                val o = arr.getJSONObject(i)
                val pkg = o.optString("package")
                if (!blocked.contains(pkg)) {
                    out.add(mapOf(
                        "package" to pkg,
                        "appName" to o.optString("appName"),
                        "title" to o.optString("title"),
                        "text" to o.optString("text"),
                        "postedAt" to o.optLong("postedAt"),
                    ))
                }
                i--
            }
            out
        }.getOrDefault(emptyList())
    }

    /// 手机里已安装、且有启动入口的应用（排除本应用），按名称排序。
    /// 通知缓存里出现过的应用也一并补进来：有些应用没有启动图标，
    /// 但确实在发通知，用户同样应该能屏蔽它。
    private fun installedApps(): List<Map<String, Any?>> {
        val c = ctx() ?: return emptyList()
        val pm = c.packageManager
        val out = LinkedHashMap<String, String>()
        runCatching {
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            for (info in pm.queryIntentActivities(intent, 0)) {
                val pkg = info.activityInfo?.packageName ?: continue
                if (pkg == c.packageName) continue
                if (out.containsKey(pkg)) continue
                val label = runCatching { info.loadLabel(pm).toString() }.getOrDefault(pkg)
                out[pkg] = label
            }
        }
        runCatching {
            val prefs = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val arr = org.json.JSONArray(prefs.getString("notifications", "[]") ?: "[]")
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val pkg = o.optString("package")
                if (pkg.isEmpty() || pkg == c.packageName || out.containsKey(pkg)) continue
                out[pkg] = o.optString("appName").ifEmpty { pkg }
            }
        }
        return out.entries
            .map { mapOf<String, Any?>("package" to it.key, "label" to it.value) }
            .sortedBy { (it["label"] as? String)?.lowercase() ?: "" }
    }

    // ---------- 日历 ----------
    private fun readCalendar(from: Long, to: Long): List<Map<String, Any?>> {
        val c = ctx() ?: return emptyList()
        if (ContextCompat.checkSelfPermission(c, Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) return emptyList()
        val uri: Uri = CalendarContract.Instances.CONTENT_URI.buildUpon()
            .appendPath(from.toString()).appendPath(to.toString()).build()
        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.CALENDAR_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.DESCRIPTION,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.ALL_DAY,
        )
        val out = ArrayList<Map<String, Any?>>()
        runCatching {
            c.contentResolver.query(uri, projection, null, null, "${CalendarContract.Instances.BEGIN} ASC")?.use { cur ->
                while (cur.moveToNext() && out.size < 500) {
                    out.add(mapOf(
                        "id" to cur.getLong(0).toString(),
                        "calendarId" to cur.getLong(1).toString(),
                        "title" to cur.getString(2),
                        "description" to cur.getString(3),
                        "location" to cur.getString(4),
                        "startAt" to cur.getLong(5),
                        "endAt" to cur.getLong(6),
                        "allDay" to (cur.getInt(7) == 1),
                    ))
                }
            }
        }
        return out
    }

    // ---------- 通讯录 ----------
    private fun readContacts(limit: Int): List<Map<String, Any?>> {
        val c = ctx() ?: return emptyList()
        if (ContextCompat.checkSelfPermission(c, Manifest.permission.READ_CONTACTS) != PackageManager.PERMISSION_GRANTED) return emptyList()
        val projection = arrayOf(
            ContactsContract.CommonDataKinds.Phone.CONTACT_ID,
            ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
            ContactsContract.CommonDataKinds.Phone.NUMBER,
            ContactsContract.CommonDataKinds.Phone.TYPE,
        )
        val grouped = LinkedHashMap<String, MutableMap<String, Any?>>()
        runCatching {
            c.contentResolver.query(
                ContactsContract.CommonDataKinds.Phone.CONTENT_URI, projection, null, null,
                "${ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME} ASC"
            )?.use { cur ->
                while (cur.moveToNext() && grouped.size < limit) {
                    val id = cur.getLong(0).toString()
                    val name = cur.getString(1) ?: ""
                    val number = cur.getString(2) ?: ""
                    val entry = grouped.getOrPut(id) {
                        mutableMapOf("id" to id, "name" to name, "phones" to mutableListOf<String>(), "emails" to mutableListOf<String>())
                    }
                    @Suppress("UNCHECKED_CAST")
                    val phones = entry["phones"] as MutableList<String>
                    if (number.isNotBlank() && !phones.contains(number)) phones.add(number)
                }
            }
        }
        return grouped.values.toList()
    }

    // ---------- 短信（只读：收件箱 + 已发送） ----------
    /**
     * 读取手机短信。**只读**，不发送、不拦截、不写回。
     *
     * 数据源：[Telephony.Sms.CONTENT_URI]（content://sms），按时间倒序。
     * 只取 MESSAGE_TYPE_INBOX(1) 与 MESSAGE_TYPE_SENT(2)，跳过草稿/发件箱/失败记录。
     */
    private fun readSms(limit: Int, query: String): List<Map<String, Any?>> {
        val c = ctx() ?: return emptyList()
        if (!hasSmsAccess(c)) return emptyList()

        val projection = arrayOf(
            Telephony.Sms._ID,
            Telephony.Sms.ADDRESS,
            Telephony.Sms.PERSON,
            Telephony.Sms.DATE,
            Telephony.Sms.BODY,
            Telephony.Sms.READ,
            Telephony.Sms.TYPE,
        )

        val inbox = Telephony.Sms.MESSAGE_TYPE_INBOX.toString()
        val sent = Telephony.Sms.MESSAGE_TYPE_SENT.toString()

        val selection = buildString {
            append("${Telephony.Sms.TYPE} IN (?, ?)")
            if (query.isNotBlank()) {
                append(" AND (${Telephony.Sms.BODY} LIKE ? OR ${Telephony.Sms.ADDRESS} LIKE ?)")
            }
        }
        val args = if (query.isBlank()) {
            arrayOf(inbox, sent)
        } else {
            arrayOf(inbox, sent, "%$query%", "%$query%")
        }

        val out = ArrayList<Map<String, Any?>>()
        runCatching {
            c.contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                projection,
                selection,
                args,
                "${Telephony.Sms.DATE} DESC",
            )?.use { cur ->
                while (cur.moveToNext() && out.size < limit) {
                    val type = cur.getInt(6)
                    out.add(
                        mapOf(
                            "id" to cur.getLong(0).toString(),
                            "address" to cur.getString(1),
                            "person" to cur.getString(2),
                            "date" to cur.getLong(3),
                            "body" to cur.getString(4),
                            "read" to (cur.getInt(5) == 1),
                            "type" to type,
                            "direction" to if (type == Telephony.Sms.MESSAGE_TYPE_INBOX) "in" else "out",
                        ),
                    )
                }
            }
        }
        return out
    }

    // ---------- 定位（仅最后一次已知位置，不持续追踪） ----------
    private fun readLocation(): Map<String, Any?> {
        val c = ctx() ?: return mapOf("error" to "no context")
        if (ContextCompat.checkSelfPermission(c, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(c, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            return mapOf("error" to "未授予定位权限")
        }
        val lm = c.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return mapOf("error" to "no location service")
        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER)
        var best: android.location.Location? = null
        for (p in providers) {
            val loc = runCatching { lm.getLastKnownLocation(p) }.getOrNull() ?: continue
            if (best == null || loc.time > best!!.time) best = loc
        }
        val loc = best ?: return mapOf("error" to "暂无已知位置（可先打开地图 App 定位一次）")
        return mapOf(
            "lat" to loc.latitude,
            "lng" to loc.longitude,
            "accuracy" to loc.accuracy,
            "time" to loc.time,
            "provider" to loc.provider,
        )
    }

    // ---------- 文件（MediaStore 索引，不遍历目录） ----------
    private fun readFiles(limit: Int, query: String): List<Map<String, Any?>> {
        val c = ctx() ?: return emptyList()
        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.Files.FileColumns.DISPLAY_NAME,
            MediaStore.Files.FileColumns.SIZE,
            MediaStore.Files.FileColumns.MIME_TYPE,
            MediaStore.Files.FileColumns.DATE_MODIFIED,
            MediaStore.Files.FileColumns.DATA,
        )
        val selection = if (query.isBlank()) null
        else "${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE ?"
        val args = if (query.isBlank()) null else arrayOf("%$query%")

        // 先查 Files（需要「所有文件访问」才能看到全部），
        // 再查四类媒体集合兜底（Android 13+ 只要给了媒体权限就有内容）。
        val uris = buildList {
            add(MediaStore.Files.getContentUri("external"))
            if (Build.VERSION.SDK_INT >= 29) add(MediaStore.Downloads.getContentUri("external"))
            add(MediaStore.Images.Media.getContentUri("external"))
            add(MediaStore.Video.Media.getContentUri("external"))
            add(MediaStore.Audio.Media.getContentUri("external"))
        }

        val merged = LinkedHashMap<String, Map<String, Any?>>()
        for (uri in uris) {
            runCatching {
                c.contentResolver.query(
                    uri, projection, selection, args,
                    "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC",
                )?.use { cur ->
                    while (cur.moveToNext()) {
                        val name = cur.getString(1) ?: continue
                        val size = cur.getLong(2)
                        val path = runCatching { cur.getString(5) }.getOrNull()
                        val key = path?.takeIf { it.isNotBlank() } ?: "$name|$size"
                        if (merged.containsKey(key)) continue
                        val id = cur.getLong(0)
                        merged[key] = mapOf<String, Any?>(
                            "id" to id.toString(),
                            "name" to name,
                            "path" to path,
                            "size" to size,
                            "mime" to cur.getString(3),
                            "modified" to cur.getLong(4) * 1000,
                            "uri" to ContentUris.withAppendedId(uri, id).toString(),
                        )
                    }
                }
            }
        }

        // 有「所有文件访问」时直接遍历存储，能拿到 MediaStore 不索引的文档/压缩包，路径也是真的
        if (Build.VERSION.SDK_INT >= 30 && Environment.isExternalStorageManager()) {
            for (item in scanFilesystem(query, limit)) {
                val path = item["path"] as? String ?: continue
                if (!merged.containsKey(path)) merged[path] = item
            }
        }

        return merged.values
            .sortedByDescending { (it["modified"] as? Long) ?: 0L }
            .take(limit)
    }

    /**
     * 直接遍历共享存储，返回真实绝对路径。
     * 跳过 Android/data、Android/obb、Android/media（系统目录，无意义且量大），
     * 限制深度与总量，避免在低端机上卡住。
     */
    private fun scanFilesystem(query: String, limit: Int): List<Map<String, Any?>> {
        val root = Environment.getExternalStorageDirectory() ?: return emptyList()
        val rootPath = root.absolutePath
        val skipPrefixes = listOf("Android/data", "Android/obb", "Android/media")
        val out = ArrayList<Map<String, Any?>>()
        var visited = 0

        fun walk(dir: File, depth: Int) {
            if (out.size >= limit || visited > 20000 || depth > 6) return
            val children = runCatching { dir.listFiles() }.getOrNull() ?: return
            for (f in children) {
                if (out.size >= limit || visited > 20000) return
                val rel = f.absolutePath.removePrefix("$rootPath/")
                if (skipPrefixes.any { rel.startsWith(it) }) continue
                if (f.isDirectory) {
                    if (!f.name.startsWith(".")) walk(f, depth + 1)
                    continue
                }
                visited++
                if (query.isNotBlank() && !f.name.contains(query, ignoreCase = true)) continue
                out.add(
                    mapOf<String, Any?>(
                        "id" to f.absolutePath.hashCode().toString(),
                        "name" to f.name,
                        "path" to f.absolutePath,
                        "size" to f.length(),
                        "mime" to null,
                        "modified" to f.lastModified(),
                        "uri" to null,
                    ),
                )
            }
        }

        runCatching { walk(root, 0) }
        return out
    }

    // ---------- 使用时长 ----------
    private fun readUsage(from: Long, to: Long): List<Map<String, Any?>> {
        val c = ctx() ?: return emptyList()
        val usm = c.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return emptyList()
        val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, from, to) ?: return emptyList()
        val pm = c.packageManager
        val day = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(from))
        return stats.filter { it.totalTimeInForeground > 0 }
            .sortedByDescending { it.totalTimeInForeground }
            .take(100)
            .map { s ->
                val label = runCatching {
                    pm.getApplicationLabel(pm.getApplicationInfo(s.packageName, 0)).toString()
                }.getOrDefault(s.packageName)
                mapOf(
                    "date" to day,
                    "package" to s.packageName,
                    "appName" to label,
                    "totalMs" to s.totalTimeInForeground,
                    "lastUsed" to s.lastTimeUsed,
                )
            }
    }

    private fun startOfToday(): Long {
        val c = java.util.Calendar.getInstance()
        c.set(java.util.Calendar.HOUR_OF_DAY, 0)
        c.set(java.util.Calendar.MINUTE, 0)
        c.set(java.util.Calendar.SECOND, 0)
        c.set(java.util.Calendar.MILLISECOND, 0)
        return c.timeInMillis
    }
}
