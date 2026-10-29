import 'dart:convert';

import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:go_router/go_router.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:material_ui/material_ui.dart';

/// Qing · 连接应用（MCP）
///
/// 所有 MCP 连接都由 X2 的 device-hub 代理：凭据只存在服务器，手机不直连第三方。
/// 页面负责：添加服务器 / 刷新工具 / 按 schema 填参数调用。
class McpServersPage extends StatefulWidget {
  const McpServersPage({super.key});

  @override
  State<McpServersPage> createState() => _McpServersPageState();
}

class _McpServersPageState extends State<McpServersPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _servers = const [];

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
      final servers = await DeviceHubClient.mcpServers();
      if (!mounted) return;
      setState(() {
        _servers = servers;
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

  Future<void> _add() async {
    final name = TextEditingController();
    final url = TextEditingController(text: 'https://');
    final token = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('连接应用'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '名称（如 GitHub）'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'MCP 地址',
                  hintText: 'https://mcp.example.com/mcp',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: token,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Token（可选）',
                  helperText: '存在你自己的服务器上，不经过第三方',
                ),
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
    if (name.text.trim().isEmpty || !url.text.trim().startsWith('http')) {
      _snack('请填写名称和正确的地址');
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await DeviceHubClient.addMcpServer(
        name: name.text.trim(),
        url: url.text.trim(),
        token: token.text,
      );
      final warning = result['warning'];
      _snack(warning == null ? '已连接，发现 ${result['tool_count'] ?? 0} 个工具' : '$warning');
      await _load();
    } catch (e) {
      setState(() => _loading = false);
      _snack('连接失败：$e');
    }
  }

  Future<void> _refresh(int id) async {
    setState(() => _loading = true);
    try {
      final result = await DeviceHubClient.refreshMcpServer(id);
      _snack('已刷新，共 ${result['tool_count'] ?? 0} 个工具');
      await _load();
    } catch (e) {
      setState(() => _loading = false);
      _snack('刷新失败：$e');
    }
  }

  Future<void> _remove(int id) async {
    try {
      await DeviceHubClient.deleteMcpServer(id);
      await _load();
    } catch (e) {
      _snack('删除失败：$e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showTools(Map<String, dynamic> server) {
    final tools = (server['tools'] as List? ?? [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Column(
          children: [
            ListTile(
              title: Text('${server['name']} · ${tools.length} 个工具'),
              subtitle: Text('${server['url']}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  Navigator.pop(context);
                  _refresh(server['id'] as int);
                },
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: tools.isEmpty
                  ? const Center(child: Text('还没有工具，点右上角刷新'))
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: tools.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final tool = tools[index];
                        return ListTile(
                          leading: const Icon(Icons.extension_outlined),
                          title: Text('${tool['name']}'),
                          subtitle: Text(
                            '${tool['description'] ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _callTool(server, tool);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _callTool(
      Map<String, dynamic> server, Map<String, dynamic> tool) async {
    final schema = (tool['inputSchema'] as Map?) ?? const {};
    final props = (schema['properties'] as Map?) ?? const {};
    final initial = <String, dynamic>{};
    props.forEach((k, v) {
      final type = (v is Map) ? v['type'] : null;
      initial['$k'] = type == 'number' || type == 'integer' ? 0 : '';
    });
    final argsController =
        TextEditingController(text: const JsonEncoder.withIndent('  ').convert(initial));
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${tool['name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${tool['description'] ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              TextField(
                controller: argsController,
                minLines: 5,
                maxLines: 10,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: '参数（JSON）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              try {
                final args = jsonDecode(argsController.text) as Map<String, dynamic>;
                Navigator.pop(context, '__running__');
                await Future<void>.delayed(const Duration(milliseconds: 10));
                final data = await DeviceHubClient.callMcpTool(
                  serverId: server['id'] as int,
                  tool: '${tool['name']}',
                  arguments: args,
                );
                if (!mounted) return;
                _showResult('${tool['name']}', data);
              } catch (e) {
                if (!mounted) return;
                _showResult('${tool['name']}', {'error': '$e'});
              }
            },
            child: const Text('调用'),
          ),
        ],
      ),
    );
    if (result == '__running__') _snack('正在调用…');
  }

  void _showResult(String tool, Map<String, dynamic> data) {
    final pretty = const JsonEncoder.withIndent('  ').convert(data);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$tool · 结果'),
        content: SingleChildScrollView(
          child: SelectableText(pretty, style: const TextStyle(fontSize: 12)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  const Icon(Icons.vpn_key_off, size: 40),
                  const SizedBox(height: 8),
                  Text('读取失败：$_error', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.tonal(onPressed: _load, child: const Text('重试')),
                ]),
              ),
            )
          else ...[
            Text('已连接', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              '连接由 X2 代理，凭据只存在你自己的服务器；手机不直连第三方。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_servers.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Icon(Icons.extension_outlined,
                        size: 40, color: theme.colorScheme.outline),
                    const SizedBox(height: 8),
                    const Text('还没有连接应用'),
                    const SizedBox(height: 4),
                    Text('点右下角 + 添加 MCP 服务',
                        style: theme.textTheme.bodySmall),
                  ]),
                ),
              )
            else
              for (final server in _servers)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.hub_outlined)),
                    title: Text('${server['name']}'),
                    subtitle: Text(
                      server['last_error'] != null
                          ? '连接异常：${server['last_error']}'
                          : '${server['url']}\n${server['tool_count'] ?? 0} 个工具',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(server['id'] as int),
                    ),
                    onTap: () => _showTools(server),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
