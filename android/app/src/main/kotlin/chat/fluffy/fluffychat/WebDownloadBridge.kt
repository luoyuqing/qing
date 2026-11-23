package chat.fluffy.fluffychat

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.webkit.CookieManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.URLDecoder
import java.util.Locale

/**
 * Qing · 网页下载桥
 *
 * webview_flutter 未暴露 DownloadListener，WebView 会把
 * `Content-Disposition: attachment` 的响应静默丢弃。Dart 侧拦截
 * a[download] 后把 URL 交到这里，改用系统 DownloadManager 落盘。
 *
 * 关键点：Cookie 直接读 WebView 的 CookieManager，与服务页共用同一份
 * 票据会话，因此需要登录的下载链接也能成功。
 */
object WebDownloadBridge : MethodChannel.MethodCallHandler {
    private const val CHANNEL = "chat.qingzhuli/web_download"
    private var appContext: Context? = null

    fun register(messenger: BinaryMessenger, context: Context) {
        val channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler(this)
        appContext = context.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "enqueue" -> enqueue(call, result)
            else -> result.notImplemented()
        }
    }

    private fun enqueue(call: MethodCall, result: MethodChannel.Result) {
        val ctx = appContext
        if (ctx == null) {
            result.error("no_context", "应用上下文不可用", null)
            return
        }

        val rawUrl = call.argument<String>("url").orEmpty().trim()
        val hint = call.argument<String>("filename").orEmpty().trim()
        val uri = runCatching { Uri.parse(rawUrl) }.getOrNull()
        if (uri == null || (uri.scheme != "http" && uri.scheme != "https")) {
            result.error("bad_url", "只支持 http/https 下载", null)
            return
        }

        val filename = resolveFilename(uri, hint)
        val dirType = when {
            isImage(filename) -> Environment.DIRECTORY_PICTURES
            isVideo(filename) -> Environment.DIRECTORY_MOVIES
            else -> Environment.DIRECTORY_DOWNLOADS
        }

        try {
            val request = DownloadManager.Request(uri).apply {
                setTitle(filename)
                setDescription("清助理下载")
                setNotificationVisibility(
                    DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
                )
                setAllowedOverMetered(true)
                setAllowedOverRoaming(true)
                mimeOf(filename)?.let { setMimeType(it) }

                // 与服务页共享 WebView 会话，HttpOnly 票据 Cookie 也能带上
                val cookie = runCatching {
                    CookieManager.getInstance().getCookie(rawUrl)
                }.getOrNull()
                if (!cookie.isNullOrBlank()) {
                    addRequestHeader("Cookie", cookie)
                }

                setDestinationInExternalPublicDir(dirType, "Qing/$filename")
            }
            val dm = ctx.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            val id = dm.enqueue(request)
            result.success(
                mapOf(
                    "ok" to true,
                    "id" to id,
                    "filename" to filename,
                    "dir" to dirType
                )
            )
        } catch (e: Exception) {
            result.error("enqueue_failed", e.message ?: e.javaClass.simpleName, null)
        }
    }

    private fun resolveFilename(uri: Uri, hint: String): String {
        val cleanHint = sanitize(hint)
        if (cleanHint.isNotEmpty() && cleanHint.contains('.')) return cleanHint

        val last = uri.lastPathSegment.orEmpty()
        var name = runCatching { URLDecoder.decode(last, "UTF-8") }.getOrDefault(last)
        name = sanitize(name)
        if (name.isEmpty()) name = "qing-${System.currentTimeMillis()}"
        if (!name.contains('.')) name += extensionOf(uri.path.orEmpty())
        return name.take(120)
    }

    private fun sanitize(raw: String): String = raw
        .replace(Regex("""[\\/:*?"<>|\u0000-\u001f]"""), "_")
        .trim()
        .trimStart('.')
        .take(120)

    private fun extensionOf(path: String): String {
        val ext = path.substringAfterLast('.', "")
        return if (ext.length in 1..5 && ext.all { it.isLetterOrDigit() }) ".$ext" else ".bin"
    }

    private fun isImage(name: String) = mimeOf(name)?.startsWith("image/") == true

    private fun isVideo(name: String) = mimeOf(name)?.startsWith("video/") == true

    private fun mimeOf(name: String): String? =
        when (name.substringAfterLast('.', "").lowercase(Locale.ROOT)) {
            "png" -> "image/png"
            "jpg", "jpeg" -> "image/jpeg"
            "webp" -> "image/webp"
            "gif" -> "image/gif"
            "bmp" -> "image/bmp"
            "heic", "heif" -> "image/heic"
            "mp4" -> "video/mp4"
            "webm" -> "video/webm"
            "mov" -> "video/quicktime"
            "mkv" -> "video/x-matroska"
            "pdf" -> "application/pdf"
            "zip" -> "application/zip"
            "txt" -> "text/plain"
            "json" -> "application/json"
            "m3u", "m3u8" -> "application/vnd.apple.mpegurl"
            else -> null
        }
}
