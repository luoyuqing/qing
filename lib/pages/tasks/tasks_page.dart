import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/qing_bottom_nav.dart';
import 'package:fluffychat/widgets/qing_style.dart';
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
  String _tab = 'sessions';

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
      backgroundColor: qingPageBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('任务'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView(theme)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: _hero(theme),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: QingSegmented(
                        values: const ['sessions', 'routines'],
                        labels: [
                          '最近会话 · ${_sessions.length}',
                          '定时任务 · ${_routines.length}',
                        ],
                        selected: _tab,
                        onChanged: (v) {
                          setState(() => _tab = v);
                          _tabs.animateTo(v == 'sessions' ? 0 : 1);
                        },
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: [
                          RefreshIndicator(
                            onRefresh: _load,
                            child: _sessions.isEmpty
                                ? ListView(children: [
                                    _empty(theme, '还没有聊天会话')
                                  ])
                                : ListView.builder(
                                    padding:
                                        const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                    itemCount: _sessions.length,
                                    itemBuilder: (context, i) =>
                                        _sessionCard(theme, _sessions[i]),
                                  ),
                          ),
                          RefreshIndicator(
                            onRefresh: _load,
                            child: _routines.isEmpty
                                ? ListView(children: [
                                    _empty(theme, '还没有定时任务')
                                  ])
                                : ListView.builder(
                                    padding:
                                        const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                    itemCount: _routines.length,
                                    itemBuilder: (context, i) =>
                                        _routineCard(theme, _routines[i]),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: const QingBottomNav(currentIndex: 2),
    );
  }

  Widget _hero(ThemeData theme) {
    final sessions = _sessions.length;
    final routines = _routines.length;
    final enabled = _routines.where((r) => r['enabled'] == true).length;
    return QingHero(
      icon: Icons.task_alt_rounded,
      eyebrow: '任务 · 定时',
      title: sessions == 0 ? '今天还没聊' : '最近 $sessions 段会话',
      subtitle: routines == 0
          ? '小爱还没有定时任务'
          : '$routines 个定时任务，其中 $enabled 个在跑',
      chips: [
        if (sessions > 0) '$sessions 段会话',
        if (routines > 0) '$routines 个定时',
        if (enabled > 0) '$enabled 个运行中',
      ],
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
    return QingCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => _openSession(s),
      child: Row(
        children: [
          CircleAvatar(
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Icon(
            s['chat_type'] == 'group'
                ? Icons.groups_outlined
                : Icons.chat_bubble_outline,
            size: 20,
          ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '${s['platform'] ?? ''} · ${s['message_count'] ?? 0} 条 · '
                  '${_formatTime(s['last_at'])}'
                  '${s['is_current'] == true ? ' · 当前' : ''}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: s['is_current'] == true
                        ? theme.colorScheme.primary
                        : null,
                  ),
                ),
                if (snippet.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(snippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
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
                    s['is_current'] == true
                        ? FilledButton.tonalIcon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              context.go('/rooms/$room');
                            },
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('进入聊天'),
                          )
                        : FilledButton.tonalIcon(
                            onPressed: () => _resumeSession(
                              room,
                              '${s['id']}',
                              sheetContext,
                            ),
                            icon: const Icon(Icons.history, size: 18),
                            label: const Text('接着聊'),
                          )
                  else
                    Chip(
                      label: Text('${s['platform']} 会话'),
                      visualDensity: VisualDensity.compact,
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

  /// 真正切换上下文：给房间发 Hermes 的 `!resume <session_id>` 命令。
  /// 网关会把这个房间的当前会话切到目标 session，后续对话接着那段记忆继续。
  Future<void> _resumeSession(
    String roomId,
    String sessionId,
    BuildContext sheetContext,
  ) async {
    final client = Matrix.of(context).client;
    final room = client.getRoomById(roomId);
    if (room == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本机找不到这个房间，先在聊天里进去一次再试')),
      );
      return;
    }
    try {
      await room.sendTextEvent('!resume $sessionId --cross-room');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切换失败：$e')),
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop(sheetContext);
    context.go('/rooms/$roomId');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已切到这段上下文，直接接着聊就好')),
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
              isUser ? '主人' : _personaLabel,
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
    return QingCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => _openRoutine(r),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled
                  ? theme.colorScheme.primaryContainer.withAlpha(140)
                  : theme.colorScheme.surfaceContainerHighest.withAlpha(160),
            ),
            child: Icon(
              enabled ? Icons.schedule : Icons.pause_circle_outline,
              size: 19,
              color: enabled
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r['name'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
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
          ),
          const Icon(Icons.chevron_right),
        ],
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

  /// 当前人设的名字（气泡上显示）
  String get _personaLabel {
    switch (widget.persona) {
      case 'intimate':
        return '亲密小爱';
      case 'tavern':
        return '酒馆角色卡';
      default:
        return '办公小爱';
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
