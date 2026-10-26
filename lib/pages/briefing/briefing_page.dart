import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_bottom_nav.dart';
import 'package:material_ui/material_ui.dart';

/// 清助理 · 简报（仅办公小爱）
///
/// 数据来自 device-hub：GET /briefing/today
/// 没有 AI 简报时，hub 会用今天的日程 + 待办 + 通知数拼一份概览。
class BriefingPage extends StatefulWidget {
  const BriefingPage({super.key});

  @override
  State<BriefingPage> createState() => _BriefingPageState();
}

class _BriefingPageState extends State<BriefingPage> {
  bool _loading = true;
  String? _error;
  String? _date;
  String? _briefing;
  bool _generated = false;
  List<Map<String, dynamic>> _todos = const [];

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
      final data = await DeviceHubClient.getJson('/briefing/today');
      if (!mounted) return;
      setState(() {
        _date = data['date'] as String?;
        _briefing = data['briefing'] as String?;
        _generated = data['generated'] == true;
        _todos = (data['todos'] as List? ?? [])
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
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

  Future<void> _toggleTodo(Map<String, dynamic> todo) async {
    final id = todo['id'] as int?;
    if (id == null) return;
    final next = !(todo['done'] == true);
    setState(() => todo['done'] = next);
    try {
      await DeviceHubClient.setTodoDone(id, next);
    } catch (e) {
      if (!mounted) return;
      setState(() => todo['done'] = !next);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('更新失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('简报'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_date != null)
              Text(
                _date!,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            if (_generated && !_loading && _error == null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('自动概览（由设备数据生成）',
                    style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _EmptyCard(
                icon: Icons.cloud_off,
                title: '读取失败',
                subtitle: '$_error\n\n请确认已配对，且手机与服务器在同一网络',
                action: FilledButton.tonal(onPressed: _load, child: const Text('重试')),
              )
            else ...[
              for (final line in (_briefing ?? '').split('\n'))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    _stripMarkdown(line),
                    style: line.startsWith('## ')
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.bodyMedium,
                  ),
                ),
              if (_todos.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('待办', style: theme.textTheme.titleSmall),
                for (final todo in _todos)
                  CheckboxListTile(
                    value: todo['done'] == true,
                    onChanged: (_) => _toggleTodo(todo),
                    title: Text('${todo['title'] ?? ''}'),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ],
          ],
        ),
      ),
      bottomNavigationBar: const QingBottomNav(currentIndex: 1),
    );
  }

  String _stripMarkdown(String line) {
    var s = line;
    if (s.startsWith('## ')) s = s.substring(3);
    s = s.replaceAll('**', '');
    return s;
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(subtitle,
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
