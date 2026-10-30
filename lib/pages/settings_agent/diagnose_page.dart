import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:flutter/material.dart';

/// Qing · 体检
///
/// 一次跑完关键健康检查（配置、模型、凭据、记忆、记忆库、定时任务、设备通道），
/// 全部由服务端聚合，单次约 50ms、缓存 30 秒。
/// 向量索引状态单独查询——服务端跑 `zg status` 需要 3~6 秒，不能拖慢这一页。
class DiagnosePage extends StatefulWidget {
  const DiagnosePage({super.key, this.persona = 'default'});

  final String persona;

  @override
  State<DiagnosePage> createState() => _DiagnosePageState();
}

class _DiagnosePageState extends State<DiagnosePage> {
  static const _ok = Color(0xFF4E8A67);
  static const _warn = Color(0xFFB5822C);
  static const _bad = Color(0xFFC05552);

  late String _persona = widget.persona;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  List<String> _personas = const [];
  Map<String, String> _labels = const {};

  Map<String, dynamic>? _vaultStatus;
  bool _indexLoading = false;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  Future<void> _load({bool initial = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (initial) {
        final ps = await DeviceHubClient.personas();
        _personas = ps.map((e) => '${e['id'] ?? e['persona'] ?? ''}').where((e) => e.isNotEmpty).toList();
        _labels = {
          for (final p in ps)
            '${p['id'] ?? p['persona'] ?? ''}': '${p['label'] ?? p['name'] ?? p['id'] ?? ''}',
        };
      }
      final data = await DeviceHubClient.diagnose(persona: _persona);
      if (!mounted) return;
      setState(() {
        _data = data;
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

  Future<void> _checkIndex() async {
    setState(() => _indexLoading = true);
    try {
      final data = await DeviceHubClient.vaultStatus(persona: _persona);
      if (!mounted) return;
      setState(() => _vaultStatus = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _vaultStatus = {'ok': false, 'error': '$e'});
    } finally {
      if (mounted) setState(() => _indexLoading = false);
    }
  }

  Color _colorOf(String status) {
    switch (status) {
      case 'ok':
        return _ok;
      case 'warn':
        return _warn;
      case 'bad':
        return _bad;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  String _labelOf(String pid) => _labels[pid] ?? pid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: qingPageBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('体检'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            if (_personas.isNotEmpty) ...[
              _personaBar(theme),
              const SizedBox(height: 12),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              QingCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('读取失败', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(_error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                        onPressed: () => _load(), child: const Text('重试')),
                  ],
                ),
              )
            else ...[
              _summaryCard(theme),
              const SizedBox(height: 14),
              const QingSectionTitle('检查项'),
              QingCard(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                child: Column(
                  children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0)
                        Divider(
                            height: 0.5,
                            thickness: 0.5,
                            color: theme.colorScheme.outlineVariant
                                .withValues(alpha: 0.6)),
                      _itemRow(theme, _items[i]),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const QingSectionTitle('向量索引'),
              _indexCard(theme),
              const SizedBox(height: 12),
              Text(
                '检查结果缓存 30 秒；索引状态单独查询并缓存 5 分钟。'
                '出现红色项时，先看详情里的原因，再决定是否要动配置。',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  height: 1.6,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _items =>
      (((_data?['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList());

  Widget _personaBar(ThemeData theme) {
    return Wrap(
      spacing: 8,
      children: [
        for (final p in _personas)
          ChoiceChip(
            label: Text(_labelOf(p)),
            selected: p == _persona,
            onSelected: (_) {
              if (p == _persona) return;
              setState(() {
                _persona = p;
                _vaultStatus = null;
              });
              _load();
            },
          ),
      ],
    );
  }

  Widget _summaryCard(ThemeData theme) {
    final bad = (_data?['bad'] as num?)?.toInt() ?? 0;
    final warn = (_data?['warn'] as num?)?.toInt() ?? 0;
    final ok = bad == 0;
    final color = bad > 0 ? _bad : (warn > 0 ? _warn : _ok);
    final title = bad > 0 ? '$bad 项需要处理' : (warn > 0 ? '基本正常，$warn 项提醒' : '全部正常');
    final checkedAt = '${_data?['checked_at'] ?? ''}'.replaceFirst('T', ' ').split('+').first;
    return QingCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
            ),
            child: Icon(ok ? Icons.check_circle_outline : Icons.report_outlined,
                size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600, color: color)),
                const SizedBox(height: 2),
                Text('${_labelOf(_persona)} · 检查于 ${checkedAt.isEmpty ? '-' : checkedAt}',
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemRow(ThemeData theme, Map<String, dynamic> item) {
    final status = '${item['status'] ?? 'unknown'}';
    final color = _colorOf(status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${item['label'] ?? ''}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if ('${item['detail'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('${item['detail']}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        height: 1.45,
                        color: status == 'bad' || status == 'warn'
                            ? color
                            : theme.colorScheme.onSurfaceVariant,
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _indexCard(ThemeData theme) {
    final st = _vaultStatus;
    return QingCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (st == null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    '索引状态要跑一次 zg status（约 3~6 秒），按需查询',
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _indexLoading ? null : _checkIndex,
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: _indexLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('检查'),
                ),
              ],
            )
          else if (st['error'] != null || st['ok'] == false)
            Text('读取失败：${st['error'] ?? '未知原因'}',
                style: theme.textTheme.bodySmall?.copyWith(color: _bad))
          else ...[
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: _ok),
                ),
                const SizedBox(width: 8),
                Text('索引就绪',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (st['cached'] == true)
                  Text('缓存',
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              [
                if (st['coverage'] != null) '覆盖 ${st['coverage']}%（${st['files']}/${st['total']} 文件）',
                if (st['entities'] != null) '${st['entities']} 个片段',
                if (st['pending'] != null) '队列 ${st['pending']} 待处理',
                if (st['failed'] != null && (st['failed'] as num) > 0) '${st['failed']} 个失败',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
