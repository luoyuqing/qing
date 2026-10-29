import 'dart:convert';

import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:go_router/go_router.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:material_ui/material_ui.dart';

/// Qing · 连接应用
///
/// 目录来自 hub `/catalog`：官方 MCP（高德/飞书/GitHub/WPS/DeepWiki）
/// + 内置连接器（知乎/B站/快递/QQ邮箱/钉钉，由服务器直接实现，无需部署）。
///
/// 目录完全由服务器下发（hub 的 `/catalog`，支持热加载）：
/// 服务器上加/减一条连接器，这里刷新就能看到，不需要更新 App。
class ConnectorsPage extends StatefulWidget {
  const ConnectorsPage({super.key});

  @override
  State<ConnectorsPage> createState() => _ConnectorsPageState();
}

class _ConnectorsPageState extends State<ConnectorsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _catalog = const [];
  List<Map<String, dynamic>> _servers = const [];
  List<Map<String, dynamic>> _native = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        DeviceHubClient.catalog(),
        DeviceHubClient.mcpServers(),
        DeviceHubClient.nativeConnectors(),
      ]);
      if (!mounted) return;
      setState(() {
        _catalog = results[0];
        _servers = results[1];
        _native = results[2];
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

  IconData _icon(String? key) {
    switch (key) {
      case 'map':
        return Icons.map_outlined;
      case 'chat':
        return Icons.forum_outlined;
      case 'code':
        return Icons.code;
      case 'book':
        return Icons.menu_book_outlined;
      case 'trend':
        return Icons.local_fire_department_outlined;
      case 'video':
        return Icons.play_circle_outline;
      case 'package':
        return Icons.local_shipping_outlined;
      case 'mail':
        return Icons.mail_outline;
      case 'robot':
        return Icons.smart_toy_outlined;
      case 'doc':
        return Icons.description_outlined;
      case 'train':
        return Icons.train_outlined;
      default:
        return Icons.extension_outlined;
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final mode = '${item['mode']}';
    if (mode == 'pending') {
      _snack('${item['name']} 需要桥接服务，暂未开放');
      return;
    }
    final fields = (item['fields'] as List? ?? [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
    final steps = (item['steps'] as List? ?? [])
        .map((e) => '$e'.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final docUrl = '${item['doc_url'] ?? ''}'.trim();
    final controllers = <String, TextEditingController>{};
    for (final f in fields) {
      controllers['${f['key']}'] = TextEditingController();
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('连接 ${item['name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${item['capability'] ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall),
              if (steps.isNotEmpty) ...[
                const SizedBox(height: 4),
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 6),
                    title: const Text('怎么获取？', style: TextStyle(fontSize: 13)),
                    children: [
                      for (var i = 0; i < steps.length; i++)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              '${i + 1}. ${steps[i]}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      if (docUrl.isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () =>
                                UrlLauncher(context, docUrl).launchUrl(),
                            child: const Text('查看官方文档'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              for (final f in fields) ...[
                TextField(
                  controller: controllers['${f['key']}'],
                  obscureText: f['secret'] == true,
                  decoration: InputDecoration(
                    labelText: '${f['label']}',
                    hintText: '${f['placeholder'] ?? ''}',
                    helperText: '${f['hint'] ?? ''}',
                    helperMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if ('${f['help_url'] ?? ''}'.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => UrlLauncher(
                        context,
                        '${f['help_url']}',
                      ).launchUrl(),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('去获取'),
                    ),
                  ),
                const SizedBox(height: 10),
              ],
              Text(
                mode == 'remote'
                    ? '凭据存在你自己的服务器上，手机不保存。'
                    : '内置连接器由服务器直接执行，无需部署其他服务。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('连接')),
        ],
      ),
    );
    if (ok != true) return;
    final config = <String, dynamic>{};
    for (final entry in controllers.entries) {
      final v = entry.value.text.trim();
      if (v.isEmpty) {
        _snack('请把参数填完整');
        return;
      }
      config[entry.key] = v;
    }
    setState(() => _loading = true);
    try {
      if (mode == 'remote') {
        var url = '${item['url'] ?? ''}';
        config.forEach((k, v) => url = url.replaceAll('{$k}', '$v'));
        final result = await DeviceHubClient.addMcpServer(
          name: '${item['name']}',
          url: url,
          token: config['token'] as String?,
        );
        _snack(result['warning'] != null
            ? '${result['warning']}'
            : '已连接，发现 ${result['tool_count'] ?? 0} 个工具');
      } else {
        await DeviceHubClient.saveConnector('${item['id']}', config);
        _snack('已保存，可以让小爱直接用了');
      }
      await _load();
    } catch (e) {
      setState(() => _loading = false);
      _snack('连接失败：$e');
    }
  }

  Future<void> _testNative(Map<String, dynamic> meta) async {
    final id = '${meta['id']}';
    setState(() => _loading = true);
    try {
      final result = await DeviceHubClient.callConnector(id, {});
      final pretty = const JsonEncoder.withIndent('  ').convert(result);
      if (!mounted) return;
      setState(() => _loading = false);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${meta['name']} · 测试结果'),
          content: SingleChildScrollView(
              child: SelectableText(pretty, style: const TextStyle(fontSize: 12))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          ],
        ),
      );
    } catch (e) {
      setState(() => _loading = false);
      _snack('测试失败：$e');
    }
  }

  bool _connected(Map<String, dynamic> item) {
    if (item['connected'] == true) return true;
    final mode = '${item['mode']}';
    if (mode == 'remote') {
      final base = '${item['url'] ?? ''}'.split('?').first;
      return _servers.any((s) => '${s['url'] ?? ''}'.contains(base));
    }
    if (mode == 'native') {
      return _native.any((n) => '${n['name']}' == '${item['id']}');
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remote = _catalog.where((e) => '${e['mode']}' != 'native').toList();
    final native = _catalog.where((e) => '${e['mode']}' == 'native').toList();

    return Scaffold(
      backgroundColor: qingPageBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('连接应用'),
        leading: Center(
          child: BackButton(onPressed: () => context.go('/rooms/settings')),
        ),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_off, size: 40),
                      const SizedBox(height: 8),
                      Text('读取失败：$_error', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.tonal(onPressed: _load, child: const Text('重试')),
                    ]),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Text(
                      '列表由服务器下发：服务器上加一条就多一个，不用更新 App。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const QingSectionTitle('可连接的 MCP'),
                    Text('连接后由服务器代理调用，凭据只存服务器、不上手机。',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 10),
                    if (remote.isEmpty)
                      _emptyHint(context, '服务器暂时没有开放 MCP 连接')
                    else
                      for (final item in remote) _catalogTile(context, item),
                    const SizedBox(height: 18),
                    const QingSectionTitle('内置连接器'),
                    Text('由服务器直接实现，零部署；AI 对话里可直接用。',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 10),
                    if (native.isEmpty)
                      _emptyHint(context, '服务器暂时没有开放内置连接器')
                    else
                      for (final item in native) _catalogTile(context, item),
                  ],
                ),
    );
  }

  /// 找到某个目录项对应的已绑定 MCP 记录（按 URL 前缀匹配）
  Map<String, dynamic>? _serverFor(Map<String, dynamic> item) {
    final base = '${item['url'] ?? ''}'.split('?').first;
    if (base.isEmpty) return null;
    for (final s in _servers) {
      if ('${s['url'] ?? ''}'.contains(base)) return s;
    }
    return null;
  }

  /// 测试已绑定的 MCP：重拉一次工具清单，成功即说明凭据有效
  Future<void> _testRemote(Map<String, dynamic> item) async {
    final server = _serverFor(item);
    final id = server?['id'];
    if (id is! int) {
      _snack('还没连接，先点「连接」把 Key 填上');
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await DeviceHubClient.refreshMcpServer(id);
      if (!mounted) return;
      setState(() => _loading = false);
      final count = result['tool_count'] ??
          (result['tools'] as List?)?.length ??
          0;
      _snack('连接正常，发现 $count 个工具');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('连接失败：$e');
    }
  }

  Widget _emptyHint(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Text(text, style: theme.textTheme.bodySmall),
      ),
    );
  }

  Widget _catalogTile(BuildContext context, Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final connected = _connected(item);
    final pending = '${item['mode']}' == 'pending';
    return QingCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: pending ? null : () => _open(item),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.secondaryContainer.withAlpha(140),
            ),
            child: Icon(_icon('${item['icon']}'), size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text('${item['name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    if (connected) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.check_circle,
                          size: 15, color: Colors.green.shade600),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text('${item['capability'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall),
                if ('${item['note'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('${item['note']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      )),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (pending)
            Text('待开放', style: theme.textTheme.bodySmall)
          else if (connected)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => '${item['mode']}' == 'native'
                      ? _testNative(item)
                      : _testRemote(item),
                  child: const Text('测试'),
                ),
                TextButton(
                  onPressed: () => _open(item),
                  child: const Text('重配'),
                ),
              ],
            )
          else
            TextButton(
              onPressed: () => _open(item),
              child: const Text('连接'),
            ),
        ],
      ),
    );
  }
}
