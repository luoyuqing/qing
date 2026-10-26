import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_bottom_nav.dart';
import 'package:material_ui/material_ui.dart';

/// 清助理 · 任务（办公小爱）
///
/// 顶部两个 Tab：最近会话 / 定时任务；点任意条目进入详情。
class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sessions = const [];
  List<Map<String, dynamic>> _routines = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        DeviceHubClient.getJson('/tasks/sessions', query: {'limit': '30'}),
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
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: '最近会话 · ${_sessions.length}'),
            Tab(text: '定时任务 · ${_routines.length}'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView(theme)
              : TabBarView(
                  controller: _tabs,
                  children: [
                    RefreshIndicator(
                      onRefresh: _load,
                      child: _sessions.isEmpty
                          ? ListView(children: [_empty(theme, '还没有会话记录')])
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              itemCount: _sessions.length,
                              itemBuilder: (context, i) =>
                                  _sessionCard(theme, _sessions[i]),
                            ),
                    ),
                    RefreshIndicator(
                      onRefresh: _load,
                      child: _routines.isEmpty
                          ? ListView(children: [_empty(theme, '还没有定时任务')])
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              itemCount: _routines.length,
                              itemBuilder: (context, i) =>
                                  _routineCard(theme, _routines[i]),
                            ),
                    ),
                  ],
                ),
      bottomNavigationBar: const QingBottomNav(currentIndex: 2),
    );
  }

  Widget _errorView(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 40),
            const SizedBox(height: 8),
            const Text('读取失败'),
            const SizedBox(height: 6),
            Text(_error!, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ]),
        ),
      );

  Widget _empty(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(children: [
          Icon(Icons.inbox_outlined, size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(text, style: theme.textTheme.bodySmall),
        ]),
      );

  Widget _sessionCard(ThemeData theme, Map<String, dynamic> s) {
    final name = '${s['name'] ?? ''}';
    final snippet = '${s['last_user_message'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            s['chat_type'] == 'group' ? Icons.groups_outlined : Icons.person_outline,
            size: 20,
          ),
        ),
        title: Text(name.length > 32 ? '${name.substring(0, 32)}…' : name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${_formatTime(s['last_at'])} · ${s['message_count'] ?? 0} 条消息',
              style: theme.textTheme.bodySmall,
            ),
            if (snippet.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(snippet,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _sessionDetail(s),
      ),
    );
  }

  Widget _routineCard(ThemeData theme, Map<String, dynamic> r) {
    final enabled = r['enabled'] == true;
    final last = r['last_execution'];
    final status = last is Map ? '${last['status'] ?? ''}' : '';
    final color = status.contains('completed')
        ? Colors.green
        : status.contains('fail')
            ? theme.colorScheme.error
            : theme.colorScheme.outline;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Icon(enabled ? Icons.schedule : Icons.pause_circle_outline,
            color: enabled ? theme.colorScheme.primary : theme.colorScheme.outline),
        title: Text('${r['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${r['schedule'] ?? ''}${status.isEmpty ? '' : ' · 上次 $status'}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Icon(Icons.chevron_right, color: color),
        onTap: () => _routineDetail(r),
      ),
    );
  }

  void _sessionDetail(Map<String, dynamic> s) {
    _showDetail('会话详情', [
      ('名称', '${s['name'] ?? ''}'),
      ('类型', s['chat_type'] == 'group' ? '群聊' : '私聊'),
      ('来源', '${s['source'] ?? ''}'),
      ('消息数', '${s['message_count'] ?? 0}'),
      ('最后活动', _formatTime(s['last_at'])),
      ('最后一条用户消息', '${s['last_user_message'] ?? ''}'),
    ]);
  }

  void _routineDetail(Map<String, dynamic> r) {
    final last = r['last_execution'];
    final rows = <(String, String)>[
      ('名称', '${r['name'] ?? ''}'),
      ('计划', '${r['schedule'] ?? ''}'),
      ('状态', r['enabled'] == true ? '已启用' : '已暂停'),
      ('任务内容', '${r['prompt'] ?? ''}'),
      if (last is Map) ('上次执行', '${last['status'] ?? ''} · ${last['started_at'] ?? ''}'),
    ];
    _showDetail('定时任务详情', rows);
  }

  void _showDetail(String title, List<(String, String)> rows) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.$1, style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 2),
                      SelectableText(row.$2, style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
            ],
          ),
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
