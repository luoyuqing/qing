import 'package:fluffychat/pages/settings_agent/candidate_edit_page.dart';
import 'package:fluffychat/pages/settings_agent/fallback_edit_page.dart';
import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:flutter/material.dart';

/// 清助理 · 模型与推理
///
/// 三个人设各自独立配置模型（config.yaml 里 model / model_candidates /
/// fallback_providers 三块）。这里能看、能切、能增删改候选、能编辑备用链。
/// 保存后下一轮对话即生效（gateway 每轮重载配置），不需要重启服务。
class AgentModelPage extends StatefulWidget {
  const AgentModelPage({super.key, this.initialPersona = 'default'});

  final String initialPersona;

  @override
  State<AgentModelPage> createState() => _AgentModelPageState();
}

class _AgentModelPageState extends State<AgentModelPage> {
  static const _personas = <String, String>{
    'default': '办公',
    'intimate': '亲密',
    'tavern': '酒馆',
  };

  late String _persona = widget.initialPersona;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _state;
  List<Map<String, dynamic>> _creds = const [];

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
      final state = await DeviceHubClient.agentModel(persona: _persona);
      List<Map<String, dynamic>> creds;
      try {
        creds = await DeviceHubClient.credentials();
      } catch (_) {
        creds = const [];
      }
      if (!mounted) return;
      setState(() {
        _state = state;
        _creds = creds;
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

  Map<String, dynamic> get _model =>
      ((_state?['model'] as Map?) ?? const {}).cast<String, dynamic>();

  List<Map<String, dynamic>> get _candidates =>
      (((_state?['candidates'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList());

  List<Map<String, dynamic>> get _fallback =>
      (((_state?['fallback'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList());

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _switchTo(Map<String, dynamic> cand) async {
    if (cand['is_current'] == true) return;
    if (cand['has_key'] != true) {
      _toast('这个候选没有可用凭据（${cand['key_env'] ?? '未声明'}），切过去会 401');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换主模型'),
        content: Text(
          '${_personas[_persona]}人设 将切换到：\n\n'
          '${cand['label']}\n${cand['model']}\n${cand['base_url']}\n\n'
          '下一条消息生效，进行中的会话可能仍用旧模型。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('切换')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await DeviceHubClient.switchModel(
          persona: _persona, candidate: '${cand['key']}');
      if (!mounted) return;
      await _load();
      _toast('已切换到 ${cand['model']}，下一条消息生效');
    } catch (e) {
      _toast('切换失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editCandidate(Map<String, dynamic>? cand) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CandidateEditPage(
          persona: _persona,
          existing: cand,
        ),
      ),
    );
    if (changed == true) {
      await _load();
      _toast('已保存');
    }
  }

  Future<void> _deleteCandidate(Map<String, dynamic> cand) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除候选模型'),
        content: Text(
          '将删除「${cand['label']}」（${cand['model']}）。\n\n'
          '${cand['is_current'] == true ? '它正被当前人设使用：删除后不会立刻影响运行，但会失去切回它的入口。\n\n' : ''}'
          '已配置的密钥不会删除。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DeviceHubClient.deleteCandidate(persona: _persona, key: '${cand['key']}');
      await _load();
      _toast('已删除');
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  Future<void> _probe({String? candidateKey}) async {
    setState(() => _busy = true);
    try {
      final r = candidateKey == null
          ? await DeviceHubClient.testCurrentModel(persona: _persona)
          : await DeviceHubClient.testCandidate(persona: _persona, key: candidateKey);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(r['ok'] == true ? '连接正常' : '连接失败'),
          content: Text(
            r['ok'] == true
                ? '${r['base_url']}\n${r['mode'] == 'chat' ? 'chat 探活' : '模型列表'} · ${r['ms']} ms'
                    '${r['models'] != null ? '\n${r['models']} 个模型' : ''}'
                : '${r['base_url'] ?? ''}\n${r['error'] ?? r['status'] ?? '未知错误'}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('好')),
          ],
        ),
      );
    } catch (e) {
      _toast('测试失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncLabel() async {
    final m = _model;
    try {
      await DeviceHubClient.setModelLabel(
        persona: _persona,
        baseUrl: '${m['base_url']}',
        model: '${m['model']}',
        label: '${m['model']}',
      );
      await _load();
      _toast('备注已同步');
    } catch (e) {
      _toast('同步失败：$e');
    }
  }

  Future<void> _editFallback() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FallbackEditPage(
          persona: _persona,
          chain: _fallback,
          candidates: _candidates,
        ),
      ),
    );
    if (changed == true) {
      await _load();
      _toast('备用链已保存');
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
        title: const Text('模型与推理'),
        actions: [
          IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: QingSegmented(
              values: _personas.keys.toList(),
              labels: _personas.values.toList(),
              selected: _persona,
              onChanged: (v) {
                if (v == _persona) return;
                setState(() => _persona = v);
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
                      : _body(theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    final m = _model;
    final labelMismatch = m['label_matches'] == false;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        QingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: m['has_key'] == true
                          ? const Color(0xFF4E8A67)
                          : const Color(0xFFC05552),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(m['has_key'] == true ? '凭据就绪' : '缺凭据',
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: m['has_key'] == true
                              ? const Color(0xFF4E8A67)
                              : const Color(0xFFC05552))),
                  const Spacer(),
                  Text('${m['api_mode'] ?? ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 8),
              Text('${m['model'] ?? '-'}',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('${m['label'] ?? ''}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text('${m['base_url'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
              if (labelMismatch) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB5822C).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: Color(0xFFB5822C)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('备注和实际模型不一致',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontSize: 11, color: const Color(0xFF8A6520))),
                      ),
                      TextButton(
                        onPressed: _busy ? null : _syncLabel,
                        style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8)),
                        child: const Text('同步备注', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _probe(),
                      icon: const Icon(Icons.network_check, size: 16),
                      label: const Text('测试连接'),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(40)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(child: QingSectionTitle('候选模型')),
            TextButton.icon(
              onPressed: _busy ? null : () => _editCandidate(null),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新增'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        for (final c in _candidates) ...[
          _candidateCard(theme, c),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(child: QingSectionTitle('备用链')),
            TextButton.icon(
              onPressed: _busy ? null : _editFallback,
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('编辑'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        QingCard(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          child: Column(
            children: [
              for (var i = 0; i < _fallback.length; i++) ...[
                if (i > 0)
                  Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 18,
                        child: Text('${i + 1}',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${_fallback[i]['model']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.w500)),
                            Text('${_fallback[i]['base_url']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 10.5,
                                    color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _fallback[i]['has_key'] == true
                              ? const Color(0xFF4E8A67)
                              : const Color(0xFFC05552),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_fallback.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text('没有备用链，主模型挂了就没有兜底',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const QingSectionTitle('凭据健康'),
        QingCard(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
          child: Column(
            children: [
              for (final c in _creds.where((e) {
                final n = '${e['name']}';
                return n.endsWith('_API_KEY') || n.endsWith('_KEY');
              }).take(10)) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${c['name']}',
                                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12)),
                            if (c['shadowed'] == true)
                              Text('user 级遮蔽系统级（以 data/.env 为准）',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      fontSize: 10, color: const Color(0xFFB5822C))),
                          ],
                        ),
                      ),
                      Text(
                        c['in_system'] == true ? '/etc/hermes/.env' : 'data/.env',
                        style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c['resolved'] == true
                              ? const Color(0xFF4E8A67)
                              : const Color(0xFFC05552),
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
        Text(
          '密钥统一存在 X2 的系统级 /etc/hermes/.env，App 只读变量名与状态，永不回显密钥值。'
          '候选池按人设各存一份，新增时默认同步三个人设。',
          style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11, height: 1.6, color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _candidateCard(ThemeData theme, Map<String, dynamic> c) {
    final current = c['is_current'] == true;
    final hasKey = c['has_key'] == true;
    return QingCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: _busy ? null : () => _editCandidate(c),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text('${c['label'] ?? c['key']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      if (current) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('当前',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 9.5, color: theme.colorScheme.primary)),
                        ),
                      ],
                      if (c['shared_endpoint'] == true) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: theme.colorScheme.outlineVariant, width: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('共享端点',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 9.5,
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text('${c['model']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      Expanded(
                        child: Text('${c['base_url']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                      ),
                      if (!hasKey)
                        Text('缺凭据',
                            style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 10, color: const Color(0xFFC05552))),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (!current)
            TextButton(
              onPressed: _busy || !hasKey ? null : () => _switchTo(c),
              style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10)),
              child: const Text('切换', style: TextStyle(fontSize: 12)),
            ),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: Icon(Icons.more_vert,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
            onSelected: (v) {
              if (v == 'edit') _editCandidate(c);
              if (v == 'test') _probe(candidateKey: '${c['key']}');
              if (v == 'delete') _deleteCandidate(c);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('编辑')),
              PopupMenuItem(value: 'test', child: Text('测试连接')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
}
