import 'dart:convert';

import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:go_router/go_router.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:material_ui/material_ui.dart';

/// 清助理 · 连接应用
///
/// 目录来自 hub `/catalog`：官方 MCP（高德/飞书/GitHub/WPS/DeepWiki）
/// + 内置连接器（知乎/B站/快递/QQ邮箱/钉钉，由 X2 直接实现，无需部署）。
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
              const SizedBox(height: 12),
              for (final f in fields) ...[
                TextField(
                  controller: controllers['${f['key']}'],
                  obscureText: f['secret'] == true,
                  decoration: InputDecoration(
                    labelText: '${f['label']}',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                mode == 'remote'
                    ? '凭据会存在你自己的 X2 上，手机不保存。'
                    : '内置连接器由 X2 直接执行，无需部署其他服务。',
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
                    const QingSectionTitle('官方 MCP'),
                    Text('连接后由 X2 代理调用，凭据不上手机。',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 10),
                    for (final item in remote) _catalogTile(context, item),
                    const SizedBox(height: 20),
                    const SizedBox(height: 18),
                    const QingSectionTitle('内置连接器'),
                    Text('由 X2 直接实现，零部署；AI 对话里可直接用。',
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 10),
                    for (final item in native) _catalogTile(context, item),
                  ],
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
              ],
            ),
          ),
          const SizedBox(width: 6),
          pending
              ? Text('待开放', style: theme.textTheme.bodySmall)
              : connected && '${item['mode']}' == 'native'
                  ? TextButton(
                      onPressed: () => _testNative(item),
                      child: const Text('测试'),
                    )
                  : TextButton(
                      onPressed: () => _open(item),
                      child: Text(connected ? '重配' : '连接'),
                    ),
        ],
      ),
    );
  }
}
