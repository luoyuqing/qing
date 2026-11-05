import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:flutter/material.dart';

/// Qing · 凭据
///
/// 管理模型端点用的 API key：全部落在系统级 `/etc/hermes/.env`。
/// 服务端只回变量名、来源、引用位置与是否解析，**永不回传明文值**；
/// 改完之后 gateway 下一轮会重新加载 env，不需要重启。
class CredentialsPage extends StatefulWidget {
  const CredentialsPage({super.key});

  @override
  State<CredentialsPage> createState() => _CredentialsPageState();
}

class _CredentialsPageState extends State<CredentialsPage> {
  static const _ok = Color(0xFF4E8A67);
  static const _bad = Color(0xFFC05552);
  static const _warn = Color(0xFFB5822C);

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  String _q = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await DeviceHubClient.credentials(withRefs: true);
      if (!mounted) return;
      setState(() {
        _items = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<Map<String, dynamic>> get _filtered {
    if (_q.trim().isEmpty) return _items;
    final q = _q.trim().toUpperCase();
    return _items.where((e) => '${e['name']}'.contains(q)).toList();
  }

  /// 编辑或新增：name 为空表示新增
  Future<void> _edit({String? name}) async {
    final theme = Theme.of(context);
    final nameCtrl = TextEditingController(text: name ?? '');
    final valueCtrl = TextEditingController();
    var obscure = true;
    final isNew = name == null;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(isNew ? '新增凭据' : '修改 $name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNew) ...[
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: '变量名（如 MY_API_KEY）',
                    helperText: '大写字母/数字/下划线，需以 _API_KEY / _KEY / _BASE_URL / _TOKEN 结尾',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: valueCtrl,
                obscureText: obscure,
                maxLines: obscure ? 1 : 3,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText: isNew ? '值' : '新的值',
                  helperText: isNew ? '只写系统级 .env，不回显' : '留空不保存；覆盖后立即生效',
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 18),
                    onPressed: () => setLocal(() => obscure = !obscure),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '写入 /etc/hermes/.env（root:root 600，自动备份）。'
                'gateway 下一轮对话重新加载环境变量，不用重启。',
                style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10.5,
                    height: 1.5,
                    color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final n = nameCtrl.text.trim().toUpperCase();
                final v = valueCtrl.text.trim();
                if (v.isEmpty) {
                  _toast('值不能为空');
                  return;
                }
                if (n.isEmpty) {
                  _toast('变量名不能为空');
                  return;
                }
                Navigator.pop(ctx, true);
                await _save(n, v);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      nameCtrl.dispose();
      valueCtrl.dispose();
    }
  }

  Future<void> _save(String name, String value) async {
    try {
      final res = await DeviceHubClient.setCredential(name: name, value: value);
      await _load();
      final refs = (res['references'] as List?) ?? const [];
      _toast(refs.isEmpty
          ? '已保存 $name'
          : '已保存 $name（被 ${refs.length} 处引用，下一条消息生效）');
    } catch (e) {
      _toast('保存失败：$e');
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final theme = Theme.of(context);
    final name = '${item['name']}';
    final refs = (item['references'] as List?) ?? const [];
    if (item['editable'] != true) {
      _toast('这个变量不在系统级 .env 里，不能从这里删');
      return;
    }
    final first = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除 $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (refs.isEmpty)
              const Text('当前没有任何模型或备用链引用它，删除后不影响运行。')
            else ...[
              Text('它正被 ${refs.length} 处引用，删除后会失去可用凭据，'
                  '相关端点在下次调用时会失败并掉到备用链：',
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
              const SizedBox(height: 8),
              for (final r in refs.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '· ${(r as Map)['label'] ?? ''} · ${r['where'] ?? ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11, color: _warn),
                  ),
                ),
              if (refs.length > 6)
                Text('… 还有 ${refs.length - 6} 处',
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 10),
            Text('会先备份 .env 再删这一行。',
                style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: refs.isEmpty ? null : theme.colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(refs.isEmpty ? '删除' : '仍然删除'),
          ),
        ],
      ),
    );
    if (first != true) return;
    try {
      await DeviceHubClient.deleteCredential(name: name, force: refs.isNotEmpty);
      await _load();
      _toast('已删除 $name');
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _filtered;
    return Scaffold(
      backgroundColor: qingPageBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('凭据'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('新增'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: '搜索变量名',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _q = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('${items.length} 项',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const Spacer(),
                Text('写入系统级 .env',
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            QingCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('读取失败', style: theme.textTheme.titleSmall),
                                  const SizedBox(height: 6),
                                  Text(_error!,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant)),
                                  const SizedBox(height: 12),
                                  FilledButton.tonal(
                                      onPressed: _load, child: const Text('重试')),
                                ],
                              ),
                            ),
                          ],
                        )
                      : items.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.only(top: 70),
                              children: const [
                                QingEmpty(
                                  icon: Icons.key_outlined,
                                  title: '没有匹配的凭据',
                                  subtitle: '点右下角新增，或清空搜索',
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) => _row(theme, items[i]),
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, Map<String, dynamic> item) {
    final name = '${item['name']}';
    final resolved = item['resolved'] == true;
    final shadowed = item['shadowed'] == true;
    final refs = (item['references'] as List?) ?? const [];
    final inUser = item['in_user'] == true;
    final editable = item['editable'] == true;

    final source = <String>[
      if (item['in_system'] == true) '系统级',
      if (inUser) '用户级',
      if (shadowed) '用户级遮蔽系统级',
    ].join(' · ');

    return QingCard(
      padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
      onTap: () => _edit(name: name),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: resolved ? _ok : _bad,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    )),
                const SizedBox(height: 3),
                Text(
                  [
                    if (source.isNotEmpty) source,
                    resolved ? '已解析' : '未解析到值',
                    if (refs.isNotEmpty) '被 ${refs.length} 处引用',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10.5,
                    color: shadowed
                        ? _warn
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (editable)
            IconButton(
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
              onPressed: () => _delete(item),
              icon: Icon(Icons.delete_outline,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
