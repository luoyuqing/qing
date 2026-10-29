import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:flutter/material.dart';

/// Qing · 用量统计
///
/// 数据来自 X2 上 hermes 的 state.db（session_model_usage），
/// 按模型/人设聚合，成本是官方单价估算值。
class UsagePage extends StatefulWidget {
  const UsagePage({super.key});

  @override
  State<UsagePage> createState() => _UsagePageState();
}

class _UsagePageState extends State<UsagePage> {
  static const _ranges = <String, String>{'today': '今日', '7d': '7 天', '30d': '30 天'};

  String _range = '7d';
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

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
      final data = await DeviceHubClient.usage(range: _range);
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

  double _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  String _tokens(double n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: qingPageBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('用量')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: QingSegmented(
              values: _ranges.keys.toList(),
              labels: _ranges.values.toList(),
              selected: _range,
              onChanged: (v) {
                if (v == _range) return;
                setState(() => _range = v);
                _load();
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            QingCard(
                              child: Text('读取失败：$_error',
                                  style: theme.textTheme.bodySmall),
                            ),
                          ],
                        )
                      : _buildBody(theme, _data ?? const {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, Map<String, dynamic> data) {
    final totals = (data['totals'] as Map?) ?? const {};
    final models = ((data['by_model'] as List?) ?? const []);
    final personas = ((data['by_persona'] as List?) ?? const []);
    final calls = _num(totals['calls']);
    final tin = _num(totals['input_tokens']);
    final tout = _num(totals['output_tokens']);
    final cost = _num(totals['cost_usd']);
    final maxCalls = models.isEmpty
        ? 1.0
        : models
            .map((e) => _num((e as Map)['calls']))
            .reduce((a, b) => a > b ? a : b)
            .clamp(1.0, double.infinity);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Row(
          children: [
            Expanded(child: _statCard(theme, '请求', '${calls.toInt()}', '次')),
            const SizedBox(width: 10),
            Expanded(child: _statCard(theme, 'Tokens', _tokens(tin + tout), '输入 ${_tokens(tin)}')),
          ],
        ),
        const SizedBox(height: 10),
        _statCard(theme, '预估花费', '\$${cost.toStringAsFixed(2)}',
            '按官方单价估算，仅供参考'),
        const SizedBox(height: 20),
        const QingSectionTitle('按模型'),
        QingCard(
          child: models.isEmpty
              ? Text('这段时间还没有调用记录',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
              : Column(
                  children: [
                    for (var i = 0; i < models.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text('${(models[i] as Map)['model'] ?? '-'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall),
                          ),
                          const SizedBox(width: 8),
                          Text('${_num((models[i] as Map)['calls']).toInt()} 次',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: (_num((models[i] as Map)['calls']) / maxCalls)
                              .clamp(0.02, 1.0),
                          minHeight: 5,
                          backgroundColor:
                              theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            theme.colorScheme.primary
                                .withValues(alpha: (1.0 - i * 0.12).clamp(0.35, 1.0)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 20),
        const QingSectionTitle('按人设'),
        QingCard(
          child: personas.isEmpty
              ? Text('暂无数据',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
              : Column(
                  children: [
                    for (var i = 0; i < personas.length; i++) ...[
                      if (i > 0)
                        Divider(
                            height: 16,
                            thickness: 0.5,
                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
                      Row(
                        children: [
                          Expanded(
                            child: Text('${(personas[i] as Map)['persona'] ?? 'default'}',
                                style: theme.textTheme.bodyMedium),
                          ),
                          Text(
                            '${_num((personas[i] as Map)['calls']).toInt()} 次 · '
                            '\$${_num((personas[i] as Map)['cost_usd']).toStringAsFixed(2)}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 14),
        Text(
          '数据来自 X2 本地的 state.db，每 60 秒刷新一次；成本为估算值，'
          '实际账单以各厂商为准。',
          style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11, height: 1.6, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _statCard(ThemeData theme, String label, String value, String sub) {
    return QingCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(value,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 2),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
