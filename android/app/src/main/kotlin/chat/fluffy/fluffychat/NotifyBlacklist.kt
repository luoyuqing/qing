package chat.fluffy.fluffychat

import android.content.Context
import org.json.JSONArray

/**
 * 清助理 · 通知黑名单
 *
 * 用户在「设置 → 设备数据 → 数据授权 → 通知 → 通知黑名单」里勾掉的应用，
 * **在通知监听服务里就直接丢掉**：既不写入本地缓存，也不会被上报给服务器。
 * 不是"先存下来再过滤"，因为过滤后仍然能在库里翻到，等于没屏蔽。
 *
 * 存原生 SharedPreferences（与通知缓存同一个文件），这样即使 Flutter 引擎
 * 没起来，监听服务也能正确过滤。
 */
object NotifyBlacklist {
    private const val PREFS = "qingzhuli_device_data"
    private const val KEY = "notify_blacklist"

    @Volatile
    private var cache: Set<String>? = null

    fun get(ctx: Context): Set<String> {
        cache?.let { return it }
        val prefs = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY, "[]") ?: "[]"
        val set = runCatching {
            val arr = JSONArray(raw)
            val out = HashSet<String>(arr.length())
            for (i in 0 until arr.length()) {
                val pkg = arr.optString(i)
                if (pkg.isNotEmpty()) out.add(pkg)
            }
            out
        }.getOrDefault(emptySet())
        cache = set
        return set
    }

    fun set(ctx: Context, packages: List<String>) {
        val clean = packages.map { it.trim() }.filter { it.isNotEmpty() }.distinct()
        val arr = JSONArray().apply { clean.forEach { put(it) } }
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY, arr.toString())
            .apply()
        cache = clean.toSet()
    }

    fun contains(ctx: Context, pkg: String): Boolean = get(ctx).contains(pkg)
}
