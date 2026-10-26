import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_bottom_nav.dart';
import 'package:material_ui/material_ui.dart';

/// 清助理 · 任务（仅办公小爱）
///
/// 两个分区：
///  - 会话：办公小爱的历史/进行中任务会话（读 Hermes state.db，只读）
///  - 定时任务：Hermes cron jobs + 最近执行结果
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sessions = const [];
  List<Map<String, dynamic>> _routines = const [];

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
        DeviceHubClient.getJson('/tasks/sessions', query: {'limit': '20'}),
        DeviceHubClient.getJson('/routines'),
      ]);
      if (!mounted) return;
      setState(() {
        _sessions = _asList(results[0]['items']);
        _routines = _asList(results[1]['items']);
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

  List<Map<String, dynamic>> _asList(dynamic value) => (value as List? ?? [])
      .whereType<Map>()
      .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
      .toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                    const Icon(Icons.cloud_off, size: 40),
                    const SizedBox(height: 12),
                    const Text('读取失败'),
                    const SizedBox(height: 8),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 12),
                    FilledButton.tonal(onPressed: _load, child: const Text('重试')),
                  ]),
                ),
              )
            else ...[
              Text('最近的会话', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_sessions.isEmpty)
                Text('还没有会话记录', style: theme.textTheme.bodySmall)
              else
                for (final s in _sessions) _sessionCard(context, s),
              const SizedBox(height: 20),
              Text('定时任务', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_routines.isEmpty)
                Text('还没有定时任务', style: theme.textTheme.bodySmall)
              else
                for (final r in _routines) _routineCard(context, r),
            ],
          ],
        ),
      ),
      bottomNavigationBar: const QingBottomNav(currentIndex: 2),
    );
  }

  Widget _sessionCard(BuildContext context, Map<String, dynamic> s) {
    final theme = Theme.of(context);
    final name = '${s['name'] ?? ''}';
    final snippet = '${s['last_user_message'] ?? ''}';
    final at = _formatTime(s['last_at']);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            s['chat_type'] == 'group' ? Icons.groups_outlined : Icons.person_outline,
            size: 20,
          ),
        ),
        title: Text(
          name.length > 40 ? '${name.substring(0, 40)}…' : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '$at · ${s['message_count'] ?? 0} 条消息${snippet.isEmpty ? '' : '\n$snippet'}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        isThreeLine: snippet.isNotEmpty,
      ),
    );
  }

  Widget _routineCard(BuildContext context, Map<String, dynamic> r) {
    final theme = Theme.of(context);
    final enabled = r['enabled'] == true;
    final last = r['last_execution'];
    final lastStatus = last is Map ? '${last['status'] ?? ''}' : '';
    final statusColor = lastStatus.contains('completed')
        ? Colors.green
        : lastStatus.contains('fail')
            ? theme.colorScheme.error
            : theme.colorScheme.outline;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          enabled ? Icons.schedule : Icons.pause_circle_outline,
          color: enabled ? theme.colorScheme.primary : theme.colorScheme.outline,
        ),
        title: Text('${r['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${r['schedule'] ?? ''}${lastStatus.isEmpty ? '' : ' · 上次 $lastStatus'}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
      ),
    );
  }

  String _formatTime(dynamic value) {
    if (value is num) {
      final dt = DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
      final now = DateTime.now();
      final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return sameDay ? '今天 $hh:$mm' : '${dt.month}-${dt.day} $hh:$mm';
    }
    if (value is String && value.isNotEmpty) return value;
    return '';
  }
}
