import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_bottom_nav.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 清助理 · 任务（办公小爱）
///
/// 顶部两个 Tab：
///  ① 最近会话 —— 真实聊天会话，点开可读最近的对话记录，并能一键切回对应房间
///  ② 定时任务 —— 查看详情、改名称/计划/内容、启停
class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.persona = 'default'});

  final String persona;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage>
    with SingleTickerProviderStateMixin {
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
        DeviceHubClient.sessions(persona: widget.persona, limit: 30),
        DeviceHubClient.routines(persona: widget.persona),
      ]);
      if (!mounted) return;
      setState(() {
        _sessions = results[0];
        _routines = results[1];
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('任务'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
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
                          ? ListView(children: [_empty(theme, '还没有聊天会话')])
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
            Text(_error!,
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ]),
        ),
      );

  Widget _empty(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 80),
        child: Column(children: [
          Icon(Icons.inbox_outlined,
              size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(text, style: theme.textTheme.bodySmall),
        ]),
      );

  // ---------------- 会话 ----------------

  Widget _sessionCard(ThemeData theme, Map<String, dynamic> s) {
    final name = '${s['name'] ?? '会话'}';
    final snippet = '${s['last_user_message'] ?? s['last_bot_message'] ?? ''}';
    final room = s['room_id'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            s['chat_type'] == 'group'
                ? Icons.groups_outlined
                : Icons.chat_bubble_outline,
            size: 20,
          ),
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${_formatTime(s['last_at'])} · ${s['message_count'] ?? 0} 条消息'
              '${room == null ? '' : ' · 可切回'}',
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
        onTap: () => _openSession(s),
      ),
    );
  }

  void _openSession(Map<String, dynamic> s) {
    final theme = Theme.of(context);
    final room = s['room_id'] as String?;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${s['name'] ?? '会话'}',
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          '${s['platform'] ?? ''} · ${s['message_count'] ?? 0} 条消息',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (room != null)
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        context.go('/rooms/$room');
                      },
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('切回会话'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: DeviceHubClient.sessionMessages(
                  '${s['id']}',
                  persona: widget.persona,
                  limit: 80,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('读取失败：${snapshot.error}',
                            style: theme.textTheme.bodySmall),
                      ),
                    );
                  }
                  final messages = snapshot.data ?? const [];
                  if (messages.isEmpty) {
                    return Center(
                      child: Text('这段会话没有可展示的文字记录',
                          style: theme.textTheme.bodySmall),
                    );
                  }
                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: messages.length,
                    itemBuilder: (context, i) => _bubble(theme, messages[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(ThemeData theme, Map<String, dynamic> m) {
    final isUser = m['role'] == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? '主人' : '小爱',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 3),
            Text('${m['content'] ?? ''}',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
            const SizedBox(height: 4),
            Text(_formatTime(m['timestamp']),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                )),
          ],
        ),
      ),
    );
  }

  // ---------------- 定时任务 ----------------

  Widget _routineCard(ThemeData theme, Map<String, dynamic> r) {
    final enabled = r['enabled'] == true;
    final status = '${r['last_status'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(
          enabled ? Icons.schedule : Icons.pause_circle_outline,
          color:
              enabled ? theme.colorScheme.primary : theme.colorScheme.outline,
        ),
        title: Text('${r['name'] ?? ''}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${r['schedule_expr'] ?? r['schedule'] ?? ''}',
                style: theme.textTheme.bodySmall),
            if (status.isNotEmpty)
              Text(
                '上次 ${_statusText(status)} · ${_formatTime(r['last_run_at'])}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: status.startsWith('ok')
                      ? Colors.green
                      : theme.colorScheme.error,
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openRoutine(r),
      ),
    );
  }

  Future<void> _openRoutine(Map<String, dynamic> r) async {
    final updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _RoutineEditorSheet(
        persona: widget.persona,
        routine: r,
      ),
    );
    if (!mounted) return;
    if (updated == true) {
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('定时任务已保存')),
      );
    }
  }

  String _statusText(String raw) {
    switch (raw) {
      case 'ok':
        return '成功';
      case 'error':
        return '失败';
      case 'running':
        return '进行中';
      default:
        return raw;
    }
  }

  String _formatTime(dynamic value) {
    if (value is num) {
      final dt = DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
      final now = DateTime.now();
      final sameDay =
          dt.year == now.year && dt.month == now.month && dt.day == now.day;
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return sameDay ? '今天 $hh:$mm' : '${dt.month}-${dt.day} $hh:$mm';
    }
    if (value is String && value.isNotEmpty) {
      return value.replaceFirst('T', ' ').split('+').first;
    }
    return '';
  }
}

/// 定时任务编辑面板：名称 / cron 计划 / 任务内容 / 启停
class _RoutineEditorSheet extends StatefulWidget {
  final String persona;
  final Map<String, dynamic> routine;

  const _RoutineEditorSheet({required this.persona, required this.routine});

  @override
  State<_RoutineEditorSheet> createState() => _RoutineEditorSheetState();
}

class _RoutineEditorSheetState extends State<_RoutineEditorSheet> {
  late final TextEditingController _name =
      TextEditingController(text: '${widget.routine['name'] ?? ''}');
  late final TextEditingController _schedule = TextEditingController(
      text:
          '${widget.routine['schedule_expr'] ?? widget.routine['schedule'] ?? ''}');
  late final TextEditingController _prompt =
      TextEditingController(text: '${widget.routine['prompt'] ?? ''}');
  late bool _enabled = widget.routine['enabled'] == true;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _schedule.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await DeviceHubClient.updateRoutine(
        '${widget.routine['id']}',
        persona: widget.persona,
        name: _name.text.trim(),
        prompt: _prompt.text,
        schedule: _schedule.text.trim(),
        enabled: _enabled,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('编辑定时任务', style: theme.textTheme.titleMedium),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _schedule,
              decoration: const InputDecoration(
                labelText: '执行计划（cron）',
                helperText: '例如 0 10 * * *（每天 10:00）；分 时 日 月 周',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _prompt,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '任务内容（下发给小爱的提示词）',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
              title: const Text('启用'),
              subtitle: Text(
                widget.routine['next_run_at'] == null
                    ? '当前没有排期'
                    : '下次执行：${widget.routine['next_run_at']}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '保存后由 Hermes 自己的 cron 模块重算下次执行时间，无需重启网关。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
