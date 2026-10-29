import 'dart:convert';

import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/markdown_view.dart';

import 'session_messages_pane.dart';
import 'package:fluffychat/utils/qing_schedule.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/qing_bottom_nav.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Qing · 任务（办公小爱）
///
/// 顶部三个 Tab：
///  ① 最近会话 —— 最近 30 段真实聊天，点开可读记录、能一键切回对应房间
///  ② 收藏 —— 星标过的会话集中放这里，不受「最近 30 条」限制（本地持久化）
///  ③ 定时任务 —— 查看详情、改名称/计划/内容、启停
class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.persona = 'default'});

  final String persona;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sessions = const [];
  List<Map<String, dynamic>> _routines = const [];
  Map<String, dynamic>? _digest;
  String _tab = 'sessions';

  /// 收藏：只存本地（SharedPreferences），不上传服务端。
  /// _favOrder 决定展示顺序（最近收藏在前），_favMeta 保存快照，
  /// 这样即使会话已经掉出「最近 30 条」，收藏里仍能看到名字并点回去。
  static const _favKey = 'qingzhuli.fav_sessions';
  List<String> _favOrder = const [];
  Map<String, Map<String, dynamic>> _favMeta = const {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadFavorites();
    // 左右滑动列表时，上面的分段控件要跟着走
    _tabs.addListener(() {
      const values = ['sessions', 'favorites', 'routines'];
      final v = values[_tabs.index];
      if (v != _tab) setState(() => _tab = v);
    });
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
        DeviceHubClient.sessionDigest(persona: widget.persona)
            .catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      setState(() {
        _sessions = results[0] as List<Map<String, dynamic>>;
        _routines = results[1] as List<Map<String, dynamic>>;
        _digest = results[2] as Map<String, dynamic>;
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

  // ---------------- 收藏（纯本地） ----------------

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_favKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List).whereType<Map>();
      final order = <String>[];
      final meta = <String, Map<String, dynamic>>{};
      for (final e in list) {
        final id = '${e['id'] ?? ''}';
        if (id.isEmpty || meta.containsKey(id)) continue;
        order.add(id);
        meta[id] = {
          'id': id,
          'name': '${e['name'] ?? '会话'}',
          'room_id': e['room_id'],
          'last_at': e['last_at'],
        };
      }
      if (!mounted) return;
      setState(() {
        _favOrder = order;
        _favMeta = meta;
      });
    } catch (_) {
      // 收藏是附加功能，本地数据坏了就当没有，不打断整个任务页
    }
  }

  bool _isFavorite(Map<String, dynamic> s) =>
      _favOrder.contains('${s['id'] ?? ''}');

  Future<void> _toggleFavorite(Map<String, dynamic> s) async {
    final id = '${s['id'] ?? ''}';
    if (id.isEmpty) return;
    final order = List<String>.from(_favOrder);
    final meta = Map<String, Map<String, dynamic>>.from(_favMeta);
    final removing = order.remove(id);
    if (removing) {
      meta.remove(id);
    } else {
      order.insert(0, id);
      meta[id] = {
        'id': id,
        'name': '${s['name'] ?? '会话'}',
        'room_id': s['room_id'],
        'last_at': s['last_at'],
      };
    }
    setState(() {
      _favOrder = order;
      _favMeta = meta;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _favKey,
        jsonEncode([
          for (final fid in order)
            {
              'id': fid,
              'name': meta[fid]?['name'] ?? '会话',
              'room_id': meta[fid]?['room_id'],
              'last_at': meta[fid]?['last_at'],
            },
        ]),
      );
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(removing ? '已取消收藏' : '已收藏，在「收藏」里随时能找到'),
        duration: const Duration(seconds: 2),
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
                        values: const ['sessions', 'favorites', 'routines'],
                        labels: [
                          '会话 · ${_sessions.length}',
                          '收藏 · ${_favOrder.length}',
                          '定时 · ${_routines.length}',
                        ],
                        selected: _tab,
                        onChanged: (v) {
                          setState(() => _tab = v);
                          _tabs.animateTo(switch (v) {
                            'favorites' => 1,
                            'routines' => 2,
                            _ => 0,
                          });
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
                            child: _favoritesList(theme),
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
        if (_digestItemCount > 0) '今日 $_digestItemCount 段会话',
        if (_digestTotal > 0) '$_digestTotal 条',
      ],
    );
  }

  int get _digestItemCount {
    final items = (_digest?['items'] as List?) ?? const [];
    return items.length;
  }

  int get _digestTotal {
    final items = (_digest?['items'] as List?) ?? const [];
    return items.fold<int>(
      0,
      (sum, e) => sum + (((e as Map)['message_count'] as num?)?.toInt() ?? 0),
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

  // ---------------- 收藏列表 ----------------

  Widget _favoritesList(ThemeData theme) {
    final rows = <({Map<String, dynamic> data, bool cached})>[];
    for (final id in _favOrder) {
      Map<String, dynamic>? live;
      for (final s in _sessions) {
        if ('${s['id']}' == id) {
          live = s;
          break;
        }
      }
      final data = live ?? _favMeta[id];
      if (data == null) continue;
      rows.add((data: data, cached: live == null));
    }
    if (rows.isEmpty) {
      return ListView(
        children: [_empty(theme, '还没有收藏。点会话右侧的 ☆ 就能收藏')],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: rows.length,
      itemBuilder: (context, i) => rows[i].cached
          ? _cachedFavoriteCard(theme, rows[i].data)
          : _sessionCard(theme, rows[i].data),
    );
  }

  /// 已经掉出「最近 30 条」的收藏：仍然能看到名字并点回房间
  Widget _cachedFavoriteCard(ThemeData theme, Map<String, dynamic> s) {
    final room = s['room_id'] as String?;
    return QingCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      onTap: room == null ? null : () => context.go('/rooms/$room'),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(
              Icons.bookmark_rounded,
              size: 20,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s['name'] ?? '已收藏的会话'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '不在最近 30 条内 · ${_formatTime(s['last_at'])}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _toggleFavorite(s),
            tooltip: '取消收藏',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.star_rounded, color: Color(0xFFF2B01E)),
          ),
        ],
      ),
    );
  }

  // ---------------- 会话 ----------------

  Widget _sessionCard(ThemeData theme, Map<String, dynamic> s) {
    final name = '${s['name'] ?? '会话'}';
    final snippet =
        MdInline.strip('${s['last_user_message'] ?? s['last_bot_message'] ?? ''}');
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
          IconButton(
            onPressed: () => _toggleFavorite(s),
            tooltip: _isFavorite(s) ? '取消收藏' : '收藏',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              _isFavorite(s) ? Icons.star_rounded : Icons.star_border_rounded,
              size: 21,
              color: _isFavorite(s)
                  ? const Color(0xFFF2B01E)
                  : theme.colorScheme.outline,
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
            SessionMessagesPane(
              sessionId: '${s['id']}',
              persona: widget.persona,
              scrollController: scrollController,
              bubbleBuilder: (m) => _bubble(theme, m),
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
            MarkdownView(
              data: '${m['content'] ?? ''}',
              baseStyle: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
              onTapLink: (url) => UrlLauncher(context, url).launchUrl(),
            ),
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
                Text(
                  QingSchedule.describe(
                    '${r['schedule_expr'] ?? r['schedule'] ?? ''}',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
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
  late final TextEditingController _prompt =
      TextEditingController(text: '${widget.routine['prompt'] ?? ''}');
  late bool _enabled = widget.routine['enabled'] == true;
  bool _saving = false;
  bool _running = false;
  bool _histLoading = false;
  List<Map<String, dynamic>> _history = const [];

  /// 执行计划拆成四种「傻瓜选项」，不再逼用户写 cron：
  /// 每天 / 每周 / 每小时 / 自定义。前三者由界面拼 cron，自定义保留原始输入。
  static const _modes = <String, String>{
    'daily': '每天',
    'weekly': '每周',
    'hourly': '每小时',
    'custom': '自定义',
  };
  String _mode = 'daily';
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);
  Set<int> _weekdays = <int>{DateTime.monday};
  int _minute = 0;
  late final TextEditingController _custom = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initSchedule(
      '${widget.routine['schedule_expr'] ?? widget.routine['schedule'] ?? ''}',
    );
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _histLoading = true);
    try {
      final items = await DeviceHubClient.routineHistory(
        persona: widget.persona,
        jobId: '${widget.routine['id']}',
        limit: 10,
      );
      if (!mounted) return;
      setState(() => _history = items);
    } catch (_) {
      // 历史读不到不影响编辑
    } finally {
      if (mounted) setState(() => _histLoading = false);
    }
  }

  Future<void> _runNow() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('立即运行一次'),
        content: const Text('会真的执行这个任务（可能消耗模型用量、可能推送消息）。确定现在跑一次？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('运行')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _running = true);
    try {
      await DeviceHubClient.runRoutine(
        persona: widget.persona,
        jobId: '${widget.routine['id']}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已触发，几秒后下面会出现这次的结果')),
      );
      await Future<void>.delayed(const Duration(seconds: 4));
      await _loadHistory();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('触发失败：$e')));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _when(Map<String, dynamic> h) {
    final a = DateTime.tryParse('${h['started_at'] ?? ''}');
    if (a == null) return '';
    final l = a.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.month}-${l.day} ${two(l.hour)}:${two(l.minute)}';
  }

  String _dur(Map<String, dynamic> h) {
    final a = DateTime.tryParse('${h['started_at'] ?? ''}');
    final b = DateTime.tryParse('${h['finished_at'] ?? ''}');
    if (a == null || b == null) return '';
    final s = b.difference(a).inMilliseconds / 1000;
    return s >= 10 ? '${s.toStringAsFixed(0)}s' : '${s.toStringAsFixed(1)}s';
  }

  /// 把现有 cron 反解成对应的选项；反解不出就落到「自定义」
  void _initSchedule(String expr) {
    final raw = expr.trim();
    _custom.text = raw;
    final daily = QingSchedule.dailyTime(raw);
    if (daily != null) {
      _mode = 'daily';
      _time = TimeOfDay(hour: daily.hour, minute: daily.minute);
      return;
    }
    final f = raw.split(RegExp(r'\s+'));
    if (f.length != 5) return; // every 30m / once at ... → 自定义

    // 每小时：分 * * * *
    if (f[1] == '*' && f[2] == '*' && f[3] == '*' && f[4] == '*') {
      final m = int.tryParse(f[0]);
      if (m != null && m >= 0 && m <= 59) {
        _mode = 'hourly';
        _minute = m;
        return;
      }
    }

    // 每周：分 时 * * 1,3
    if (f[2] == '*' && f[3] == '*' && f[4] != '*') {
      final m = int.tryParse(f[0]);
      final h = int.tryParse(f[1]);
      final days = <int>{};
      for (final p in f[4].split(',')) {
        final d = int.tryParse(p);
        if (d != null && d >= 1 && d <= 7) days.add(d);
      }
      if (m != null && h != null && days.isNotEmpty) {
        _mode = 'weekly';
        _time = TimeOfDay(hour: h, minute: m);
        _weekdays = days;
        return;
      }
    }
    _mode = 'custom';
  }

  /// 当前选项对应的 cron
  String get _cron {
    switch (_mode) {
      case 'weekly':
        return QingSchedule.weekly(_weekdays, _time.hour, _time.minute);
      case 'hourly':
        return QingSchedule.hourly(_minute);
      case 'custom':
        return _custom.text.trim();
      default:
        return QingSchedule.daily(_time.hour, _time.minute);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked == null || !mounted) return;
    setState(() => _time = picked);
  }

  /// 执行计划编辑器：四种选项 + 实时人话预览
  Widget _scheduleEditor(ThemeData theme) {
    final timeText = QingSchedule.timeText(_time.hour, _time.minute);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('执行计划', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in _modes.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _mode == entry.key,
                  onSelected: (_) => setState(() => _mode = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_mode == 'weekly') ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(
                      '${QingSchedule.weekdayNames[d]!.replaceFirst('周', '')}',
                    ),
                    selected: _weekdays.contains(d),
                    onSelected: (on) => setState(() {
                      final next = Set<int>.from(_weekdays);
                      if (on) {
                        next.add(d);
                      } else {
                        next.remove(d);
                      }
                      // 至少留一天，否则计划就空了
                      _weekdays = next.isEmpty ? {d} : next;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (_mode == 'hourly')
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var m = 0; m < 60; m += 5)
                  ChoiceChip(
                    label: Text('${m.toString().padLeft(2, '0')} 分'),
                    selected: _minute == m,
                    onSelected: (_) => setState(() => _minute = m),
                  ),
              ],
            )
          else if (_mode == 'custom')
            TextField(
              controller: _custom,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'cron 表达式',
                helperText: '分 时 日 月 周，例如 0 10 * * *',
                border: OutlineInputBorder(),
              ),
            )
          else
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(timeText),
                ),
                const SizedBox(width: 10),
                Text(
                  _mode == 'weekly' ? '每周这些天的 $timeText' : '每天 $timeText',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          const SizedBox(height: 10),
          Text(
            '→ ${QingSchedule.describe(_cron)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _prompt.dispose();
    _custom.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cron = _cron;
    if (cron.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('执行计划不能为空')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await DeviceHubClient.updateRoutine(
        '${widget.routine['id']}',
        persona: widget.persona,
        name: _name.text.trim(),
        prompt: _prompt.text,
        schedule: _cron,
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
            _scheduleEditor(theme),
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
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('立即运行',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            Text('不用等排期，现在就执行一次',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: _running ? null : _runNow,
                        style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        child: _running
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('运行'),
                      ),
                    ],
                  ),
                  if (_histLoading)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('读取历史…',
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant)),
                    )
                  else if (_history.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.6)),
                    const SizedBox(height: 8),
                    Text('最近运行',
                        style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant)),
                    for (final h in _history.take(5))
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: '${h['status']}' == 'completed'
                                    ? const Color(0xFF4E8A67)
                                    : const Color(0xFFC05552),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(_when(h),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(fontSize: 11)),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${h['status']}' == 'completed' ? '成功' : '${h['status']}',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                            fontSize: 11,
                                            color: '${h['status']}' == 'completed'
                                                ? const Color(0xFF4E8A67)
                                                : const Color(0xFFC05552)),
                                      ),
                                      const Spacer(),
                                      Text(_dur(h),
                                          style: theme.textTheme.bodySmall?.copyWith(
                                              fontSize: 11,
                                              color: theme
                                                  .colorScheme.onSurfaceVariant)),
                                    ],
                                  ),
                                  if ('${h['error'] ?? ''}'.isNotEmpty)
                                    Text('${h['error']}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                            fontSize: 10.5,
                                            color: theme.colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
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
