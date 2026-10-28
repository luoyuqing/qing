import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/markdown_view.dart';
import 'package:fluffychat/utils/qing_schedule.dart';
import 'package:fluffychat/widgets/qing_bottom_nav.dart';
import 'package:material_ui/material_ui.dart';

/// 清助理 · 简报（仅办公小爱）
///
/// 一天两份：
///   晨报 —— 早上（时间取「早间简报」定时任务的实际配置）
///   晚报 —— 晚上（时间取「晚间简报」定时任务的实际配置）
///
/// 页头那行小字**不再写死时间**：每次加载都读一次 `/routines`，
/// 找到对应的定时任务后把 cron 转成 HH:mm 显示。改了定时任务的计划，
/// 这里跟着变；读不到就不显示时间，而不是继续骗人。
///
/// 数据来自 device-hub：GET /briefing/day?date=YYYY-MM-DD
/// 没生成时 hub 会给一份设备数据兜底（generated=true）。
class BriefingPage extends StatefulWidget {
  const BriefingPage({super.key, this.persona = 'default'});

  final String persona;

  @override
  State<BriefingPage> createState() => _BriefingPageState();
}

class _BriefingPageState extends State<BriefingPage> {
  static const _kinds = ['morning', 'evening'];
  static const _kindLabels = {'morning': '晨报', 'evening': '晚报'};

  bool _loading = true;
  bool _requesting = false;
  String? _error;
  String _date = _todayKey();
  String _kind = DateTime.now().hour >= 17 ? 'evening' : 'morning';
  List<Map<String, dynamic>> _items = const [];
  List<String> _pending = const [];
  List<Map<String, dynamic>> _todos = const [];
  Map<String, dynamic> _stats = const {};

  /// 定时任务列表：只用来把「晨报/晚报几点」显示成真实配置
  List<Map<String, dynamic>> _routines = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${_two(now.month)}-${_two(now.day)}';
  }

  static String _two(int n) => n < 10 ? '0$n' : '$n';

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      // 简报正文与定时任务并行取；定时任务只用于显示「几点生成」，
      // 读失败不能拖垮正文，所以单独兜底成空列表。
      final results = await Future.wait<dynamic>([
        DeviceHubClient.briefingDay(date: _date),
        DeviceHubClient.routines(persona: widget.persona).catchError(
          (Object _) => <Map<String, dynamic>>[],
        ),
      ]);
      if (!mounted) return;
      final data = results[0] as Map<String, dynamic>;
      final routines = results[1] as List<Map<String, dynamic>>;
      final items = (data['items'] as List? ?? [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
      setState(() {
        _routines = routines;
        _items = items;
        _pending = (data['pending'] as List? ?? []).map((e) => '$e').toList();
        _todos = (data['todos'] as List? ?? [])
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
        _stats = (data['stats'] as Map?)?.map((k, v) => MapEntry('$k', v)) ?? const <String, dynamic>{};
        _loading = false;
        _error = null;
        // 当天默认选中：晚上看晚报，白天看晨报；没有就挑有的那份
        if (_date == _todayKey()) {
          final have = items.map((e) => e['kind']).toSet();
          if (!have.contains(_kind)) {
            _kind = have.contains('evening') && DateTime.now().hour >= 17
                ? 'evening'
                : (have.contains('morning') ? 'morning' : _kind);
          }
        } else if (items.isNotEmpty &&
            !items.any((e) => e['kind'] == _kind)) {
          _kind = '${items.last['kind']}';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _current {
    for (final item in _items) {
      if (item['kind'] == _kind) return item;
    }
    return null;
  }

  bool get _isToday => _date == _todayKey();

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

  Future<void> _requestBriefing() async {
    final kind = _kind;
    final before = _current?['created_at'];
    setState(() => _requesting = true);
    try {
      await DeviceHubClient.requestBriefing(kind: kind);
    } catch (e) {
      if (!mounted) return;
      setState(() => _requesting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('触发失败：$e')));
      return;
    }
    // 小爱写完要一会儿，轮询到这篇出现（或被改写）为止
    for (var i = 0; i < 40; i++) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted || !_requesting) return;
      try {
        final data = await DeviceHubClient.briefingDay(date: _date);
        final items = (data['items'] as List? ?? [])
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
        final match = items.where((e) => e['kind'] == kind).toList();
        if (match.isNotEmpty &&
            match.first['generated'] != true &&
            match.first['created_at'] != before) {
          if (!mounted) return;
          setState(() {
            _items = items;
            _pending = (data['pending'] as List? ?? []).map((e) => '$e').toList();
            _requesting = false;
          });
          return;
        }
      } catch (_) {
        // 忽略中间态
      }
    }
    if (!mounted) return;
    setState(() => _requesting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('小爱还在写，过一会儿下拉刷新看看')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = Color.alphaBlend(
      theme.colorScheme.primary.withAlpha(6),
      theme.colorScheme.surface,
    );
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _load(silent: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _topBar(theme)),
              SliverToBoxAdapter(child: _dateRail(theme)),
              SliverToBoxAdapter(child: _hero(theme)),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else ...[
                SliverToBoxAdapter(child: _kindSwitch(theme)),
                SliverToBoxAdapter(child: _body(theme)),
                if (_todos.isNotEmpty)
                  SliverToBoxAdapter(child: _todosCard(theme)),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: const QingBottomNav(currentIndex: 1),
    );
  }

  // ---------------- 定时任务 → 展示文案 ----------------

  /// 判断某个定时任务是晨报还是晚报：先看名字，名字认不出再看提示词。
  String _routineKind(Map<String, dynamic> r) {
    final name = '${r['name'] ?? ''}';
    if (name.contains('晚报') || name.contains('晚间')) return 'evening';
    if (name.contains('晨报') || name.contains('早间') || name.contains('早报')) {
      return 'morning';
    }
    final prompt = '${r['prompt'] ?? ''}';
    if (prompt.contains('晚报') || prompt.contains('晚间简报')) return 'evening';
    if (prompt.contains('晨报') || prompt.contains('早间简报')) return 'morning';
    return '';
  }

  /// 某份简报的生成时间（HH:mm）。
  /// 没有对应定时任务、或计划不是「每天固定时刻」，一律返回 null（不猜）。
  String? _briefingTime(String kind) {
    for (final r in _routines) {
      if (_routineKind(r) != kind) continue;
      final expr = '${r['schedule_expr'] ?? r['schedule'] ?? ''}';
      final t = QingSchedule.dailyTime(expr);
      if (t == null) continue;
      return QingSchedule.timeText(t.hour, t.minute);
    }
    return null;
  }

  /// 页头那行小字：时间全部来自定时任务的实际配置
  String get _scheduleLabel {
    final morning = _briefingTime('morning');
    final evening = _briefingTime('evening');
    if (morning != null && evening != null) {
      return '办公小爱 · 每天 $morning 晨报 / $evening 晚报';
    }
    if (morning != null) return '办公小爱 · 每天 $morning 晨报';
    if (evening != null) return '办公小爱 · 每天 $evening 晚报';
    return '办公小爱 · 晨报与晚报按定时任务生成';
  }

  // ---------------- 顶部 ----------------

  Widget _topBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '简报',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _scheduleLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          _RoundIcon(
            icon: Icons.refresh_rounded,
            onTap: _loading ? null : () => _load(),
          ),
        ],
      ),
    );
  }

  Widget _dateRail(ThemeData theme) {
    final now = DateTime.now();
    final days = <DateTime>[
      for (var i = 0; i < 7; i++) DateTime(now.year, now.month, now.day - i)
    ];
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final d = days[i];
          final key = '${d.year}-${_two(d.month)}-${_two(d.day)}';
          final active = key == _date;
          final label = i == 0
              ? '今天'
              : (i == 1 ? '昨天' : _weekday(d));
          return GestureDetector(
            onTap: () {
              if (key == _date) return;
              setState(() {
                _date = key;
                _loading = true;
              });
              _load();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 54,
              decoration: BoxDecoration(
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: active
                      ? Colors.transparent
                      : theme.colorScheme.outlineVariant.withAlpha(70),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: active
                          ? theme.colorScheme.onPrimary.withAlpha(220)
                          : theme.colorScheme.onSurfaceVariant.withAlpha(170),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${d.day}',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: active
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------------- Hero ----------------

  Widget _hero(ThemeData theme) {
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final current = _current;
    final headline = _headline(current?['content'] as String?);
    final sessions = _stats['sessions'] ?? 0;
    final open = _stats['todos_open'] ?? 0;
    final notif = _stats['notifications'] ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.primary,
              Color.alphaBlend(cs.tertiary.withAlpha(180), cs.primary),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withAlpha(isDark ? 60 : 46),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: -36,
              top: -48,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(24),
                ),
              ),
            ),
            Positioned(
              right: 28,
              bottom: -56,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withAlpha(14),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome,
                          size: 14, color: Colors.white.withAlpha(210)),
                      const SizedBox(width: 6),
                      Text(
                        _isToday ? '办公小爱 · 今天' : '办公小爱 · 回顾',
                        style: TextStyle(
                          fontSize: 11.5,
                          letterSpacing: .4,
                          color: Colors.white.withAlpha(210),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _greeting(),
                    style: const TextStyle(
                      fontSize: 25,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    headline.isNotEmpty
                        ? headline
                        : '${_monthDay(_date)} ${_weekdayCn(_date)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: Colors.white.withAlpha(215),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _statChip('${_monthDay(_date)} ${_weekdayCn(_date)}'),
                      _statChip('$sessions 段会话'),
                      _statChip('$open 件待办'),
                      if (notif != 0) _statChip('$notif 条通知'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(36),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withAlpha(235),
            fontWeight: FontWeight.w500,
          ),
        ),
      );

  // ---------------- 晨报 / 晚报 切换 ----------------

  Widget _kindSwitch(ThemeData theme) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withAlpha(150),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            for (final kind in _kinds)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _kind = kind),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _kind == kind
                          ? cs.surfaceContainerLowest
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: _kind == kind
                          ? [
                              BoxShadow(
                                color: Colors.black.withAlpha(12),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _kindLabels[kind]!,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: _kind == kind
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: _kind == kind
                                ? cs.onSurface
                                : cs.onSurfaceVariant.withAlpha(170),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _items.any((e) =>
                                    e['kind'] == kind && e['generated'] != true)
                                ? cs.primary
                                : cs.outlineVariant.withAlpha(120),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------- 正文 ----------------

  Widget _body(ThemeData theme) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: _StateCard(
          icon: Icons.cloud_off_rounded,
          title: '读取失败',
          subtitle: '$_error\n\n确认已配对，且手机能连到 hub',
          action: FilledButton.tonal(onPressed: () => _load(), child: const Text('重试')),
        ),
      );
    }
    final current = _current;
    if (_requesting) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: _StateCard(
          icon: Icons.edit_note_rounded,
          title: '小爱正在写${_kindLabels[_kind]}…',
          subtitle: '读完今天的会话和待办大概要 1-2 分钟，写完会自动出现在这里。',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text('生成中', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      );
    }
    if (current == null) {
      final pending = _pending.contains(_kind);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: _StateCard(
          icon: _kind == 'evening'
              ? Icons.nightlight_round
              : Icons.wb_sunny_outlined,
          title: pending
              ? (_briefingTime(_kind) == null
                  ? '${_kindLabels[_kind]}会按定时任务自动生成'
                  : '${_kindLabels[_kind]}会在 ${_briefingTime(_kind)} 自动生成')
              : '这天没有${_kindLabels[_kind]}',
          subtitle: pending
              ? (_kind == 'evening'
                  ? '小爱会在晚上把今天所有会话的结论、还没落地的待办整理成一页。'
                  : '小爱会在早上结合日程、待办和手机通知，告诉你今天先做什么。')
              : '换个日期看看，或者让小爱现在补一份。',
          action: _isToday
              ? FilledButton.icon(
                  onPressed: _requestBriefing,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('让小爱现在写'),
                )
              : null,
        ),
      );
    }

    final generated = current['generated'] == true;
    final created = _clock(current['created_at'] as String?);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(70),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (generated)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withAlpha(120),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '小爱还没写，这是按今天的日程与待办自动整理的',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ..._renderContent(theme, '${current['content'] ?? ''}'),
            const SizedBox(height: 12),
            Divider(height: 1, color: theme.colorScheme.outlineVariant.withAlpha(60)),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.auto_awesome,
                    size: 13,
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(140)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    generated
                        ? '设备数据自动整理'
                        : '办公小爱${created.isEmpty ? '' : ' · $created 生成'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                    ),
                  ),
                ),
                if (_isToday)
                  TextButton.icon(
                    onPressed: _requesting ? null : _requestBriefing,
                    icon: const Icon(Icons.autorenew_rounded, size: 15),
                    label: const Text('重新生成',
                        style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 正文：交给通用 MarkdownView，标题/引用/列表/代码块/表格/
  /// 粗斜体/行内代码/链接全部按标记渲染，不再把星号和井号原样露出来。
  List<Widget> _renderContent(ThemeData theme, String content) {
    return [
      MarkdownView(
        data: content,
        baseStyle: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13.8,
              height: 1.62,
              color: theme.colorScheme.onSurface.withAlpha(225),
            ) ??
            const TextStyle(fontSize: 13.8, height: 1.62),
        onTapLink: (url) => UrlLauncher(context, url).launchUrl(),
      ),
    ];
  }

  Widget _todosCard(ThemeData theme) {
    final open = _todos.where((t) => t['done'] != true).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(70),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('待办',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text('$open 件未完成',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                    )),
              ],
            ),
            const SizedBox(height: 6),
            for (final todo in _todos) _todoRow(theme, todo),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _todoRow(ThemeData theme, Map<String, dynamic> todo) {
    final done = todo['done'] == true;
    final cs = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _toggleTodo(todo),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: done ? cs.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: done
                      ? cs.primary
                      : cs.outlineVariant.withAlpha(180),
                  width: 1.4,
                ),
              ),
              child: done
                  ? Icon(Icons.check_rounded, size: 13, color: cs.onPrimary)
                  : null,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                '${todo['title'] ?? ''}',
                style: TextStyle(
                  fontSize: 13.2,
                  height: 1.4,
                  color: done
                      ? cs.onSurfaceVariant.withAlpha(140)
                      : cs.onSurface,
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: cs.onSurfaceVariant.withAlpha(140),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 小工具 ----------------

  String _greeting() {
    if (!_isToday) return '这一天';
    final h = DateTime.now().hour;
    if (h < 5) return '夜深了';
    if (h < 11) return '早上好';
    if (h < 13) return '中午好';
    if (h < 18) return '下午好';
    return '晚上好';
  }

  String _headline(String? content) {
    if (content == null) return '';
    for (final line in content.split('\n')) {
      final t = line.trim();
      if (t.startsWith('## ')) {
        final s = _clean(t.substring(3));
        return s.length > 46 ? '${s.substring(0, 46)}…' : s;
      }
    }
    return '';
  }

  /// 压成纯文本（标题、摘要这些单行展示用）。
  String _clean(String s) => MdInline.strip(s);

  String _clock(String? iso) {
    if (iso == null || iso.length < 16) return '';
    return iso.substring(11, 16);
  }

  String _monthDay(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return key;
    return '${int.tryParse(parts[1]) ?? parts[1]}月${int.tryParse(parts[2]) ?? parts[2]}日';
  }

  String _weekdayCn(String key) {
    final d = DateTime.tryParse(key);
    if (d == null) return '';
    return _weekday(d);
  }

  String _weekday(DateTime d) =>
      const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][d.weekday - 1];
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLowest,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon,
              size: 19,
              color: onTap == null
                  ? cs.onSurfaceVariant.withAlpha(80)
                  : cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withAlpha(70)),
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primaryContainer.withAlpha(120),
            ),
            child: Icon(icon, size: 25, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.55,
              color: cs.onSurfaceVariant.withAlpha(200),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
