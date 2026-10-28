import 'dart:async';
import 'dart:math' as math;

import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:flutter/material.dart';

/// 健康度三档色（好 / 偏高 / 超了）
///
/// 为什么这几个不跟主色联动：它们表达的是**客观状态**而不是品牌感，
/// 跟着设置里的主色走的话，「红了」这件事就读不出来了。
/// 取值刻意压低饱和度，和项目里既有的「已授权」勾（#2E7D52）同一族，
/// 面积都很小（6px 圆点、5px 进度条、一行标签字），不抢主色的戏。
const Color _okColor = Color(0xFF4E8A67);
const Color _warnColor = Color(0xFFB5822C);
const Color _badColor = Color(0xFFC05552);

/// v1.10.3 · 本页固定配色：白底 + 天空蓝
///
/// 用户明确要求「不想看见一点儿紫色」。而主题 seed 可被用户在设置里选成
/// 任意颜色，只要这页还从 Theme 取品牌色就永远可能被染紫——所以整页
/// （含趋势页）包一层固定 colorScheme：品牌色一律天空蓝，中性色自定灰阶，
/// 不再读全局值。深色模式给一套同色相的暗色版，避免夜间刺眼。
ThemeData _fixedServerTheme(BuildContext context) {
  final light = Theme.of(context).brightness == Brightness.light;
  const sky = Color(0xFF5B87C4); // 晴空蓝主色（与全局默认主色同一个值）
  const skyBright = Color(0xFF8FB4DC); // 同色相提亮（深色模式）
  const skyDeep = Color(0xFF3F6A9E); // 浅蓝底上的文字/强调
  final base = Theme.of(context);
  return base.copyWith(
    scaffoldBackgroundColor: light ? Colors.white : const Color(0xFF121417),
    colorScheme: base.colorScheme.copyWith(
      primary: light ? sky : skyBright,
      onPrimary: light ? Colors.white : const Color(0xFF0B2540),
      primaryContainer: light ? const Color(0xFFE7EEF7) : const Color(0xFF20364F),
      onPrimaryContainer: light ? skyDeep : const Color(0xFFC9DCEF),
      secondary: light ? sky : skyBright,
      secondaryContainer: light ? const Color(0xFFE7EEF7) : const Color(0xFF20364F),
      onSecondaryContainer: light ? skyDeep : const Color(0xFFC9DCEF),
      tertiary: light ? sky : skyBright,
      surface: light ? Colors.white : const Color(0xFF121417),
      onSurface: light ? const Color(0xFF1B1F24) : const Color(0xFFE8EAED),
      onSurfaceVariant: light ? const Color(0xFF697079) : const Color(0xFF9AA3AD),
      outlineVariant: light ? const Color(0xFFE3E7EC) : const Color(0xFF2A2F36),
      surfaceContainerLowest: light ? Colors.white : const Color(0xFF0E1013),
      surfaceContainerLow: light ? const Color(0xFFF7F9FB) : const Color(0xFF181B1F),
      surfaceContainer: light ? const Color(0xFFF3F5F8) : const Color(0xFF1B1F24),
      surfaceContainerHigh: light ? const Color(0xFFF7F9FB) : const Color(0xFF20242A),
      surfaceContainerHighest: light ? const Color(0xFFF0F3F6) : const Color(0xFF262B32),
      surfaceTint: Colors.transparent,
    ),
  );
}

/// 清助理 · X2 服务器状态页
///
/// 数据全部来自 device-hub 的 /server/status（服务端直读 /proc 与 cgroup v2），
/// 手机只负责展示，不缓存任何历史。
///
/// 两个口径上的讲究（服务端已经处理好，这里只负责如实显示）：
/// - 内存用 cgroup 的 anon（真实占用），不含 page cache；
/// - 服务的 mem_limit 是 cgroup 的 memory.max，容器没有限制时不显示。
class ServerStatusPage extends StatefulWidget {
  const ServerStatusPage({super.key});

  @override
  State<ServerStatusPage> createState() => _ServerStatusPageState();
}

class _ServerStatusPageState extends State<ServerStatusPage>
    with WidgetsBindingObserver {
  static const _refreshSeconds = 30;

  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;
  bool _refreshing = false;
  bool _auto = true;
  Timer? _timer;

  final _expanded = <String>{};
  final _details = <String, Map<String, dynamic>>{};
  final _detailLoading = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 切到后台就停轮询，别让 hub 白跑
    if (state == AppLifecycleState.resumed) {
      if (_auto) _startTimer();
      _load(silent: true);
    } else {
      _timer?.cancel();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_auto) return;
    _timer = Timer.periodic(const Duration(seconds: _refreshSeconds), (_) {
      if (mounted) _load(silent: true);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (_refreshing) return;
    if (!silent) setState(() => _loading = _data == null);
    _refreshing = true;
    try {
      final data = await DeviceHubClient.serverStatus();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _loading = false;
      });
    } finally {
      _refreshing = false;
    }
  }

  String _friendlyError(Object e) {
    final text = e.toString();
    if (text.contains('尚未配对')) return '还没和 X2 配对，先去「设备数据」完成配对';
    if (text.contains('TimeoutException') || text.contains('timeout')) {
      return '连接超时，检查手机和 X2 是否在同一个网络';
    }
    if (text.contains('401')) return '配对凭据已失效，请重新配对';
    return '连不上 X2（$text）';
  }

  Future<void> _toggleService(String key) async {
    if (_expanded.contains(key)) {
      setState(() => _expanded.remove(key));
      return;
    }
    setState(() => _expanded.add(key));
    if (_details.containsKey(key)) return;
    setState(() => _detailLoading.add(key));
    try {
      final detail = await DeviceHubClient.serverServiceDetail(key);
      if (!mounted) return;
      setState(() => _details[key] = detail);
    } catch (e) {
      if (!mounted) return;
      setState(() => _details[key] = {'ok': false, 'error': '$e'});
    } finally {
      if (mounted) setState(() => _detailLoading.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _fixedServerTheme(context),
      child: Builder(builder: (context) {
        final theme = Theme.of(context);
        return Scaffold(
      appBar: AppBar(
        title: const Text('服务器状态'),
        actions: [
          PopupMenuButton<int>(
            tooltip: '自动刷新',
            icon: Icon(_auto ? Icons.sync : Icons.sync_disabled),
            initialValue: _auto ? _refreshSeconds : 0,
            onSelected: (value) {
              setState(() => _auto = value > 0);
              if (value > 0) {
                _startTimer();
              } else {
                _timer?.cancel();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 30, child: Text('每 30 秒刷新')),
              PopupMenuItem(value: 60, child: Text('每分钟刷新')),
              PopupMenuItem(value: 0, child: Text('关闭自动刷新')),
            ],
          ),
          IconButton(
            tooltip: '立即刷新',
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(theme),
      ),
        );
      }),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) return _skeleton(theme);
    if (_data == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 80, 16, 16),
        children: [_errorCard(theme)],
      );
    }
    final data = _data!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        if (_error != null) ...[_staleBanner(theme), const SizedBox(height: 10)],
        _hero(theme, data),
        const SizedBox(height: 12),
        _metricGrid(theme, data),
        const SizedBox(height: 12),
        _networkRow(theme, data),
        const SizedBox(height: 20),
        _sectionHeader(theme, '服务与容器',
            trailing: '${data['services_total']?['count'] ?? 0} 项在用'),
        const SizedBox(height: 8),
        _servicesTotal(theme, data),
        const SizedBox(height: 8),
        _serviceList(theme, data),
        const SizedBox(height: 16),
        _trendEntry(theme),
        const SizedBox(height: 16),
        _footnote(theme),
      ],
    );
  }

  // ---------------- 区块 ----------------

  Widget _sectionHeader(ThemeData theme, String title, {String? trailing}) {
    return Row(
      children: [
        Text(title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const Spacer(),
        if (trailing != null)
          Text(trailing,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _card(ThemeData theme, {required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _hero(ThemeData theme, Map<String, dynamic> data) {
    final host = (data['host'] as Map?) ?? const {};
    final cpu = (data['cpu'] as Map?) ?? const {};
    final level = _overallLevel(data);
    final uptime = _fmtDuration(_asNum(host['uptime_s']).toInt());
    final load = _asNum((cpu['load'] as List?)?.firstOrNull);
    final temp = _asNum(cpu['temp_c']);
    return _card(
      theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _dot(level.color, size: 7),
              const SizedBox(width: 6),
              Text(level.label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: level.color, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(_ago(data['sampled_at']),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          Text('${host['name'] ?? 'X2'} · 家庭服务器',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            '${host['os'] ?? ''} · ${host['arch'] ?? ''} · ${host['cores'] ?? '-'} 核',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _heroStat(theme, '已运行', uptime),
              _heroStat(theme, '负载', load.toStringAsFixed(2)),
              _heroStat(theme, '温度', temp > 0 ? '${temp.round()}°C' : '—',
                  color: temp >= 75
                      ? _levelColor(95)
                      : (temp >= 65 ? _levelColor(75) : null)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(ThemeData theme, String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value,
              style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color ?? theme.colorScheme.onSurface)),
        ],
      ),
    );
  }

  Widget _metricGrid(ThemeData theme, Map<String, dynamic> data) {
    final cpu = (data['cpu'] as Map?) ?? const {};
    final mem = (data['mem'] as Map?) ?? const {};
    final disks = (data['disk'] as List?) ?? const [];
    final cards = <Widget>[
      _metricCard(
        theme,
        label: 'CPU',
        value: _asNum(cpu['usage_pct']).toStringAsFixed(0),
        unit: '%',
        pct: _asNum(cpu['usage_pct']),
        sub: '${_asNum(cpu['freq_mhz']).toInt()} MHz',
      ),
      _metricCard(
        theme,
        label: '内存',
        value: (_asNum(mem['used_mb']) / 1024).toStringAsFixed(1),
        unit: ' / ${(_asNum(mem['total_mb']) / 1024).toStringAsFixed(1)} GB',
        pct: _asNum(mem['pct']),
        sub: '缓存 ${(_asNum(mem['cache_mb']) / 1024).toStringAsFixed(1)} GB',
      ),
      for (final disk in disks.take(2))
        _metricCard(
          theme,
          label: (disk as Map)['mount'] == '/' ? '系统盘' : '数据盘',
          value: _asNum(disk['pct']).toStringAsFixed(0),
          unit: '%',
          pct: _asNum(disk['pct']),
          sub:
              '${_asNum(disk['used_gb']).toStringAsFixed(0)} / ${_asNum(disk['size_gb']).toStringAsFixed(0)} GB',
        ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final card in cards) SizedBox(width: width, child: card),
        ],
      );
    });
  }

  Widget _metricCard(
    ThemeData theme, {
    required String label,
    required String value,
    required String unit,
    required double pct,
    required String sub,
  }) {
    final color = _levelColor(pct);
    return _card(
      theme,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          RichText(
            text: TextSpan(
              style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
              children: [
                TextSpan(text: value),
                TextSpan(
                  text: unit,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _bar(theme, pct / 100, color),
          const SizedBox(height: 6),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _bar(ThemeData theme, double value, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 5,
        backgroundColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }

  Widget _networkRow(ThemeData theme, Map<String, dynamic> data) {
    final net = (data['net'] as Map?) ?? const {};
    return Row(
      children: [
        Expanded(
          child: _miniStat(theme, '下行', _fmtRate(_asNum(net['rx_bps'])),
              icon: Icons.south_rounded),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _miniStat(theme, '上行', _fmtRate(_asNum(net['tx_bps'])),
              icon: Icons.north_rounded),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _miniStat(theme, '网卡', '${net['iface'] ?? '-'}',
              icon: Icons.lan_outlined),
        ),
      ],
    );
  }

  Widget _miniStat(ThemeData theme, String label, String value,
      {required IconData icon}) {
    return _card(
      theme,
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 3),
              Text(label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 3),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _servicesTotal(ThemeData theme, Map<String, dynamic> data) {
    final total = (data['services_total'] as Map?) ?? const {};
    final memMb = _asNum(total['mem_mb']);
    final pctOfRam = _asNum(total['pct_of_ram']);
    final services = (data['services'] as List?) ?? const [];
    final top = services.isEmpty ? null : services.first as Map;
    final topShare = services.isEmpty || memMb <= 0
        ? 0.0
        : (_asNum(top?['mem_mb']) / memMb * 100);
    return _card(
      theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('合计',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              Text('占全机 ${pctOfRam.toStringAsFixed(0)}%',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              RichText(
                text: TextSpan(
                  style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface),
                  children: [
                    TextSpan(text: memMb.toStringAsFixed(0)),
                    TextSpan(
                      text: ' MB',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text('CPU ${_asNum(total['cpu_pct']).toStringAsFixed(1)}%',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          _compositionBar(theme, services, memMb),
          const SizedBox(height: 7),
          if (top != null)
            Text(
              '${top['name']} 一个占了 ${topShare.toStringAsFixed(0)}%，其余 ${services.length - 1} 项合计 ${(memMb - _asNum(top['mem_mb'])).toStringAsFixed(0)} MB',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Widget _compositionBar(
      ThemeData theme, List services, double totalMb) {
    if (services.isEmpty || totalMb <= 0) {
      return _bar(theme, 0, theme.colorScheme.outlineVariant);
    }
    // 只用主色一个色相，靠深浅分段：多色分开的话这块会是整个页面最花的一处
    final base = theme.colorScheme.primary;
    final segments = <Widget>[];
    for (var i = 0; i < services.length; i++) {
      final mb = _asNum((services[i] as Map)['mem_mb']);
      final flex = math.max((mb / totalMb * 1000).round(), 1);
      segments.add(Expanded(
        flex: flex,
        child: Container(
          color: base.withValues(alpha: (1.0 - i * 0.13).clamp(0.34, 1.0)),
        ),
      ));
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(height: 7, child: Row(children: segments)),
    );
  }

  Widget _serviceList(ThemeData theme, Map<String, dynamic> data) {
    final services = (data['services'] as List?) ?? const [];
    if (services.isEmpty) {
      return _card(theme, child: const Text('没有可显示的服务'));
    }
    return _card(
      theme,
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 12),
      child: Column(
        children: [
          for (var i = 0; i < services.length; i++) ...[
            _serviceTile(theme, services[i] as Map<String, dynamic>),
            if (i != services.length - 1)
              Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ],
        ],
      ),
    );
  }

  Widget _serviceTile(ThemeData theme, Map<String, dynamic> item) {
    final key = '${item['key']}';
    final memMb = _asNum(item['mem_mb']);
    final limitMb = _asNum(item['mem_limit_mb']);
    final cpuPct = _asNum(item['cpu_pct']);
    final active = item['active'] == true;
    final expanded = _expanded.contains(key);
    final isContainer = item['kind'] == 'container';
    final meta = <String>[
      if (isContainer && limitMb > 0)
        '${memMb.toStringAsFixed(0)} / ${limitMb.toStringAsFixed(0)} MB'
      else
        '${item['pids'] ?? 0} 进程',
      if (!isContainer) '${item['threads'] ?? 0} 线程',
      if (item['uptime_s'] != null) _fmtDuration(_asNum(item['uptime_s']).toInt()),
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _toggleService(key),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                _dot(active ? _okColor : _badColor, size: 6),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(item['name'] as String? ?? '-',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium),
                          ),
                          if (isContainer) ...[
                            const SizedBox(width: 5),
                            _chip(theme, '容器'),
                          ],
                          if (item['note'] != null) ...[
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(item['note'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${memMb.toStringAsFixed(memMb >= 100 ? 0 : 1)} MB',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('CPU ${cpuPct.toStringAsFixed(1)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
                Icon(expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        if (expanded) _serviceDetail(theme, key),
      ],
    );
  }

  Widget _chip(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
            width: 0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }

  Widget _serviceDetail(ThemeData theme, String key) {
    if (_detailLoading.contains(key)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 14),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Text('正在读取进程…',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    final detail = _details[key];
    if (detail == null) return const SizedBox.shrink();
    if (detail['ok'] != true) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 14),
        child: Text('读取失败：${detail['error'] ?? '未知错误'}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error)),
      );
    }
    final procs = (detail['processes'] as List?) ?? const [];
    final io = detail['io'] as Map?;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final proc in procs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${(proc as Map)['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  Text('${_asNum(proc['rss_mb']).toStringAsFixed(1)} MB',
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          if (_asNum(detail['process_count']) > procs.length)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('另有 ${_asNum(detail['process_count']).toInt() - procs.length} 个进程未显示',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 4),
          Text(
            [
              'CPU 累计 ${_asNum(detail['cpu_total_s']).toStringAsFixed(0)} 秒',
              if (io != null)
                '读 ${_asNum(io['read_mb']).toStringAsFixed(0)} MB · 写 ${_asNum(io['write_mb']).toStringAsFixed(0)} MB',
            ].join(' · '),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (detail['rss_note'] != null) ...[
            const SizedBox(height: 3),
            Text(detail['rss_note'] as String,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _trendEntry(ThemeData theme) {
    return FilledButton.tonalIcon(
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ServerTrendPage()),
        );
      },
      icon: const Icon(Icons.show_chart, size: 18),
      label: const Text('看 24 小时趋势'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
    );
  }

  Widget _footnote(ThemeData theme) {
    return Text(
      '内存取 cgroup 的 anon（真实占用，不含文件缓存）；进程 RSS 含共享页，'
      '合计会大于服务实际占用。数据只在 X2 本地采集，手机不保存历史。',
      style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 11, color: theme.colorScheme.onSurfaceVariant, height: 1.6),
    );
  }

  Widget _staleBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 14, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text('刷新失败，显示的是上一次的数据：$_error',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }

  Widget _errorCard(ThemeData theme) {
    return _card(
      theme,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.dns_outlined,
              size: 36, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('读不到 X2 的状态',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(_error ?? '未知错误',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: () => _load(), child: const Text('重试')),
        ],
      ),
    );
  }

  Widget _skeleton(ThemeData theme) {
    Widget block(double height, {double width = double.infinity}) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        block(148),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: block(96)),
            const SizedBox(width: 10),
            Expanded(child: block(96)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: block(96)),
            const SizedBox(width: 10),
            Expanded(child: block(96)),
          ],
        ),
        const SizedBox(height: 12),
        block(64),
        const SizedBox(height: 12),
        block(240),
      ],
    );
  }
}

// ---------------- 趋势页 ----------------

class ServerTrendPage extends StatefulWidget {
  const ServerTrendPage({super.key, this.initialRange = '24h'});

  final String initialRange;

  @override
  State<ServerTrendPage> createState() => _ServerTrendPageState();
}

class _ServerTrendPageState extends State<ServerTrendPage> {
  late String _range = widget.initialRange;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await DeviceHubClient.serverHistory(range: _range);
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
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
    return Theme(
      data: _fixedServerTheme(context),
      child: Builder(builder: (context) {
        final theme = Theme.of(context);
        return Scaffold(
      appBar: AppBar(
        title: const Text('趋势'),
        actions: [
          IconButton(
              onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _rangeSwitch(theme),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_data == null)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Center(
                  child: Text('读不到趋势数据（$_error）',
                      style: theme.textTheme.bodyMedium)),
            )
          else
            ..._charts(theme, _data!),
        ],
      ),
        );
      }),
    );
  }

  Widget _rangeSwitch(ThemeData theme) {
    const options = {'1h': '1 小时', '6h': '6 小时', '24h': '24 小时'};
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          for (final entry in options.entries)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  if (_range == entry.key) return;
                  setState(() => _range = entry.key);
                  _load();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: _range == entry.key
                        ? theme.colorScheme.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    entry.value,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: _range == entry.key
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: _range == entry.key
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _charts(ThemeData theme, Map<String, dynamic> data) {
    final points = (data['points'] as List?) ?? const [];
    if (points.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '正在积累数据。服务端每分钟采样一次，看 24 小时需要等一天才完整。',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.6),
          ),
        ),
      ];
    }
    final stats = (data['stats'] as Map?) ?? const {};
    List<double?> pick(String key) =>
        points.map<double?>((p) => _asNumOrNull((p as Map)[key])).toList();

    return [
      _chartCard(theme, 'CPU', pick('cpu'),
          stats: stats['cpu'] as Map?,
          color: theme.colorScheme.primary,
          unit: '%',
          maxY: 100,
          formatter: (v) => '${v.toStringAsFixed(0)}%'),
      const SizedBox(height: 10),
      _chartCard(theme, '内存', pick('mem'),
          stats: stats['mem'] as Map?,
          color: theme.colorScheme.primary,
          unit: ' MB',
          formatter: (v) => '${(v / 1024).toStringAsFixed(1)} GB'),
      const SizedBox(height: 10),
      _chartCard(theme, '温度', pick('temp'),
          stats: stats['temp'] as Map?,
          color: theme.colorScheme.primary,
          formatter: (v) => '${v.toStringAsFixed(0)}°C'),
      const SizedBox(height: 14),
      Text(
        '每分钟采样一次，只保留最近 24 小时；服务端本地存储，不上传。',
        style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
      ),
    ];
  }

  Widget _chartCard(
    ThemeData theme,
    String title,
    List<double?> values, {
    Map? stats,
    required Color color,
    String unit = '',
    double? maxY,
    required String Function(double) formatter,
  }) {
    final valid = values.whereType<double>().toList();
    final avg = _asNum(stats?['avg']);
    final max = _asNum(stats?['max']);
    final points = _data?['points'] as List? ?? const [];
    final startTs = points.isEmpty ? 0 : _asNum((points.first as Map)['t']).toInt();
    final endTs = points.isEmpty ? 0 : _asNum((points.last as Map)['t']).toInt();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              if (valid.isNotEmpty)
                Text('均 ${formatter(avg)} · 峰 ${formatter(max)}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: title == 'CPU' ? 96 : 72,
            width: double.infinity,
            child: valid.length < 2
                ? Center(
                    child: Text('数据点还不够',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  )
                : CustomPaint(
                    painter: _LineChartPainter(
                      values: values,
                      color: color,
                      gridColor:
                          theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                      maxY: maxY,
                    ),
                  ),
          ),
          if (points.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Text(_hhmm(startTs),
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant)),
                  const Spacer(),
                  Text(_hhmm(endTs),
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.values,
    required this.color,
    required this.gridColor,
    this.maxY,
  });

  final List<double?> values;
  final Color color;
  final Color gridColor;
  final double? maxY;

  @override
  void paint(Canvas canvas, Size size) {
    final valid = values.whereType<double>().toList();
    if (valid.length < 2) return;

    var top = maxY ?? valid.reduce(math.max) * 1.15;
    var bottom = 0.0;
    if (maxY == null) {
      // 温度这类不需要从 0 起，留点余量更好看
      bottom = math.max(valid.reduce(math.min) * 0.85, 0);
      if (top - bottom < 1) top = bottom + 1;
    }

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;
    for (var i = 0; i <= 2; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    double xAt(int index) => size.width * index / (values.length - 1);
    double yAt(double v) {
      final ratio = ((v - bottom) / (top - bottom)).clamp(0.0, 1.0);
      return size.height - ratio * size.height;
    }

    final line = Path();
    final fill = Path();
    var started = false;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      final point = Offset(xAt(i), yAt(v));
      if (!started) {
        line.moveTo(point.dx, point.dy);
        fill.moveTo(point.dx, size.height);
        fill.lineTo(point.dx, point.dy);
        started = true;
      } else {
        line.lineTo(point.dx, point.dy);
        fill.lineTo(point.dx, point.dy);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();

    canvas.drawPath(
        fill, Paint()..color = color.withValues(alpha: 0.07));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );

    final lastIndex = values.lastIndexWhere((v) => v != null);
    if (lastIndex >= 0) {
      final v = values[lastIndex]!;
      canvas.drawCircle(
          Offset(xAt(lastIndex), yAt(v)), 2.4, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.values != values || old.color != color;
}

// ---------------- 小工具 ----------------

class _Level {
  const _Level(this.label, this.color);
  final String label;
  final Color color;
}

_Level _overallLevel(Map<String, dynamic> data) {
  final cpu = (data['cpu'] as Map?) ?? const {};
  final mem = (data['mem'] as Map?) ?? const {};
  final cpuPct = _asNum(cpu['usage_pct']);
  final memPct = _asNum(mem['pct']);
  final temp = _asNum(cpu['temp_c']);
  final disks = (data['disk'] as List?) ?? const [];
  final worstDisk = disks.isEmpty
      ? 0.0
      : disks
          .map((d) => _asNum((d as Map)['pct']))
          .reduce((a, b) => a > b ? a : b);
  final worst = [cpuPct, memPct, worstDisk].reduce((a, b) => a > b ? a : b);
  if (worst >= 90 || temp >= 80) {
    return const _Level('压力偏高', _badColor);
  }
  if (worst >= 70 || temp >= 70) {
    return const _Level('有点忙', _warnColor);
  }
  return const _Level('运行正常', _okColor);
}

Color _levelColor(double pct) {
  if (pct >= 90) return _badColor;
  if (pct >= 70) return _warnColor;
  return _okColor;
}

Widget _dot(Color color, {double size = 6}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

double _asNum(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

double? _asNumOrNull(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

String _fmtDuration(int seconds) {
  if (seconds <= 0) return '—';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (days > 0) return '$days天$hours时';
  if (hours > 0) return '$hours时$minutes分';
  return '$minutes分';
}

String _fmtRate(double bps) {
  if (bps >= 1048576) return '${(bps / 1048576).toStringAsFixed(1)} MB/s';
  if (bps >= 1024) return '${(bps / 1024).toStringAsFixed(0)} KB/s';
  return '${bps.toStringAsFixed(0)} B/s';
}

String _hhmm(int seconds) {
  if (seconds <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String _ago(Object? iso) {
  final text = iso?.toString();
  if (text == null || text.isEmpty) return '';
  final at = DateTime.tryParse(text);
  if (at == null) return '';
  final diff = DateTime.now().difference(at);
  if (diff.inSeconds < 10) return '刚刚更新';
  if (diff.inSeconds < 90) return '${diff.inSeconds} 秒前更新';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前更新';
  return '${diff.inHours} 小时前更新';
}
