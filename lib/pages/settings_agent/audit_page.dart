import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:flutter/material.dart';

/// Qing · 查询审计
///
/// 小爱每查一次数据、改一次人设都会在 hub 落一条审计（只有动作，不含内容）。
/// 这一页就是「我的数据被谁动过」的流水账。
class AuditPage extends StatefulWidget {
  const AuditPage({super.key});

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  static const _filters = <String, String>{
    'all': '全部',
    'hermes': '小爱',
    'device': '手机',
  };

  String _filter = 'all';
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  static const _actionZh = <String, String>{
    'query.notifications': '查通知',
    'query.calendar': '查日历',
    'query.contacts': '查通讯录',
    'query.sms': '查短信',
    'query.usage': '查应用时长',
    'query.devices': '查设备',
    'query.todos': '查待办',
    'query.routines': '查定时任务',
    'query.memory': '查记忆',
    'query.memory.vault': '查记忆库',
    'query.skills': '查技能',
    'query.persona': '查人设',
    'query.sessions.digest': '查会话摘要',
    'query.agent.model': '查模型配置',
    'query.usage.stat': '查用量',
    'persona.write': '改人设',
    'memory.write': '写记忆',
    'skill.write': '改技能',
    'skill.delete': '删技能',
    'briefing.publish': '写简报',
    'briefing.request': '让小爱写简报',
    'mcp.call': '调用 MCP',
    'agent.model.switch': '切换模型',
    'agent.candidate.add': '新增候选模型',
    'agent.candidate.update': '改候选模型',
    'agent.candidate.delete': '删候选模型',
    'agent.fallback.write': '改备用链',
    'cron.run': '手动运行任务',
    'env.write': '写入密钥',
    'settings.retention': '改保留策略',
    'pair.success': '设备配对',
  };

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
      final items = await DeviceHubClient.audit(limit: 300);
      if (!mounted) return;
      setState(() {
        _items = items;
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

  List<Map<String, dynamic>> get _visible {
    if (_filter == 'all') return _items;
    return _items.where((e) {
      final actor = '${e['actor'] ?? ''}';
      final isHermes = actor == 'hermes' || actor.contains('小爱');
      return _filter == 'hermes' ? isHermes : !isHermes;
    }).toList();
  }

  String _actionText(String action) {
    final zh = _actionZh[action];
    if (zh != null) return zh;
    if (action.startsWith('connector.')) return '连接器 ${action.substring(10)}';
    return action;
  }

  String _timeText(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    final now = DateTime.now();
    final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (sameDay) return '今天 $hh:$mm';
    return '${local.month}/${local.day} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: qingPageBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('查询审计')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: QingSegmented(
              values: _filters.keys.toList(),
              labels: _filters.values.toList(),
              selected: _filter,
              onChanged: (v) => setState(() => _filter = v),
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('读取失败', style: theme.textTheme.titleSmall),
                                  const SizedBox(height: 6),
                                  Text(_error!,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant)),
                                  const SizedBox(height: 12),
                                  FilledButton.tonal(
                                      onPressed: _load, child: const Text('重试')),
                                ],
                              ),
                            ),
                          ],
                        )
                      : _visible.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.only(top: 80),
                              children: const [
                                QingEmpty(
                                  icon: Icons.verified_user_outlined,
                                  title: '还没有审计记录',
                                  subtitle: '小爱查过数据后，这里会逐条记下来',
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _visible.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final e = _visible[i];
                                final action = '${e['action'] ?? ''}';
                                return QingCard(
                                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.only(top: 5),
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: '${e['actor']}'.contains('hermes')
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.onSurfaceVariant
                                                  .withValues(alpha: 0.5),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(_actionText(action),
                                                      style: theme.textTheme.bodyMedium
                                                          ?.copyWith(
                                                              fontWeight: FontWeight.w600)),
                                                ),
                                                Text(_timeText('${e['at'] ?? ''}'),
                                                    style: theme.textTheme.bodySmall
                                                        ?.copyWith(
                                                            color: theme.colorScheme
                                                                .onSurfaceVariant,
                                                            fontSize: 11)),
                                              ],
                                            ),
                                            if ('${e['detail'] ?? ''}'.isNotEmpty) ...[
                                              const SizedBox(height: 3),
                                              Text('${e['detail']}',
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                      color:
                                                          theme.colorScheme.onSurfaceVariant)),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}
