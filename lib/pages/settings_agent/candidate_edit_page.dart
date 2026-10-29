import 'package:fluffychat/pages/settings_agent/model_picker.dart';
import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:flutter/material.dart';

/// 清助理 · 新增 / 编辑候选模型
///
/// 候选池同时是「端点 + 凭据」的注册表：切模型时运行时靠它找回 key。
class CandidateEditPage extends StatefulWidget {
  const CandidateEditPage({
    super.key,
    required this.persona,
    this.existing,
    this.scopes = const [],
    this.diffs,
    this.personaLabels = const {},
  });

  final String persona;
  final Map<String, dynamic>? existing;

  /// 这条候选存在于哪些人设（新增时为空）
  final List<String> scopes;

  /// 各人设间有差异的字段，如 {'model': {'default': 'x', 'tavern': 'y'}}
  final Map<String, dynamic>? diffs;

  /// 人设 id -> 显示名
  final Map<String, String> personaLabels;

  @override
  State<CandidateEditPage> createState() => _CandidateEditPageState();
}

class _CandidateEditPageState extends State<CandidateEditPage> {
  late final TextEditingController _key;
  late final TextEditingController _label;
  late final TextEditingController _model;
  late final TextEditingController _baseUrl;
  late final TextEditingController _keyEnv;
  late final TextEditingController _newEnv;

  bool _useNewEnv = false;
  bool _allScopes = true;
  bool _saving = false;
  bool _fetching = false;
  List<Map<String, dynamic>> _creds = const [];

  bool get _isEdit => widget.existing != null;

  bool get _canSync => !_isEdit || widget.scopes.length > 1;

  String get _scopeHint {
    if (!_isEdit) return '候选池按人设各存一份，建议三份保持一致';
    if (widget.scopes.length <= 1) return '这条候选只在当前人设里';
    final names =
        widget.scopes.map((p) => widget.personaLabels[p] ?? p).join('、');
    return '这条候选存在于 $names';
  }

  /// 其他处人设与本条取值不同的字段，提醒同步会覆盖哪些差异
  List<String> get _diffNotes {
    final d = widget.diffs;
    if (d == null || d.isEmpty) return const [];
    final out = <String>[];
    final model = (d['model'] as Map?)?.cast<String, dynamic>();
    if (model != null && model.isNotEmpty) {
      final parts = model.entries
          .where((e) => e.key != widget.persona)
          .map((e) => '${widget.personaLabels[e.key] ?? e.key}=${e.value}')
          .toList();
      if (parts.isNotEmpty) {
        out.add('模型在其他处不同：${parts.join('、')}。'
            '若你把模型也改了并开启同步，这些差异会被统一。');
      }
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? const <String, dynamic>{};
    _key = TextEditingController(text: '${e['key'] ?? ''}');
    _label = TextEditingController(text: '${e['label'] ?? ''}');
    _model = TextEditingController(text: '${e['model'] ?? ''}');
    _baseUrl = TextEditingController(text: '${e['base_url'] ?? ''}');
    _keyEnv = TextEditingController(text: '${e['key_env'] ?? ''}');
    _newEnv = TextEditingController();
    // 新增默认同步；编辑时只有这条本来就在多人设里才默认同步
    _allScopes = !_isEdit || widget.scopes.length > 1;
    _loadCreds();
  }

  @override
  void dispose() {
    _key.dispose();
    _label.dispose();
    _model.dispose();
    _baseUrl.dispose();
    _keyEnv.dispose();
    _newEnv.dispose();
    super.dispose();
  }

  Future<void> _loadCreds() async {
    try {
      final items = await DeviceHubClient.credentials();
      if (!mounted) return;
      setState(() => _creds = items
          .where((e) => '${e['name']}'.endsWith('_API_KEY') || '${e['name']}'.contains('KEY'))
          .toList());
    } catch (_) {}
  }

  Future<void> _pickModel() async {
    final base = _baseUrl.text.trim();
    if (!base.startsWith('http')) {
      _toast('先把端点填好，再拉模型列表');
      return;
    }
    setState(() => _fetching = true);
    try {
      final picked = await pickEndpointModel(
        context,
        baseUrl: base,
        keyEnv: _keyEnv.text.trim(),
        current: _model.text.trim(),
      );
      if (picked != null && mounted) {
        setState(() => _model.text = picked);
      }
    } catch (e) {
      _toast('拉取失败：$e');
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _save() async {
    final key = _key.text.trim();
    final label = _label.text.trim();
    final model = _model.text.trim();
    final baseUrl = _baseUrl.text.trim();
    if (model.isEmpty || baseUrl.isEmpty) {
      _toast('模型名与端点不能为空');
      return;
    }
    if (!baseUrl.startsWith('http')) {
      _toast('端点必须以 http:// 或 https:// 开头');
      return;
    }
    if (!_isEdit && !RegExp(r'^[a-z0-9_]{2,24}$').hasMatch(key)) {
      _toast('标识只能用小写字母/数字/下划线，2-24 位');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEdit) {
        final e = widget.existing ?? const <String, dynamic>{};
        final payload = <String, dynamic>{};
        void put(String f, String v) {
          if ('${e[f] ?? ''}' != v) payload[f] = v;
        }

        // 只提交真正改动的字段：同步到全部人设时，没动的字段各人设保留原值
        put('label', label.isEmpty ? model : label);
        put('model', model);
        put('base_url', baseUrl);
        put('provider', 'custom');
        put('api_mode', 'chat_completions');
        final ke = _keyEnv.text.trim();
        if (ke.isNotEmpty && ke != '${e['key_env'] ?? ''}') payload['key_env'] = ke;
        if (payload.isEmpty) {
          if (mounted) Navigator.pop(context, false);
          return;
        }
        await DeviceHubClient.updateCandidate(
          persona: widget.persona,
          key: key,
          fields: payload,
          scope: (_allScopes && widget.scopes.length > 1) ? 'all' : 'persona',
        );
      } else {
        await DeviceHubClient.addCandidate(
          persona: widget.persona,
          key: key,
          label: label.isEmpty ? model : label,
          model: model,
          baseUrl: baseUrl,
          keyEnv: _useNewEnv ? '' : _keyEnv.text.trim(),
          newEnvValue: _useNewEnv ? _newEnv.text.trim() : '',
          scope: _allScopes ? 'all' : 'persona',
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('保存失败：$e');
    }
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: qingPageBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(_isEdit ? '编辑候选模型' : '新增候选模型')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          QingCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _field(theme, '标识（小写英文，如 mimo2）', _key, enabled: !_isEdit),
                _field(theme, '显示名（如 MiMo 备用）', _label),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _model,
                    decoration: InputDecoration(
                      labelText: '模型 ID（如 mimo-v2.6-flash）',
                      isDense: true,
                      suffixIcon: _fetching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              tooltip: '从端点拉取模型列表',
                              onPressed: _pickModel,
                              icon: const Icon(Icons.list_alt, size: 20),
                            ),
                    ),
                  ),
                ),
                _field(theme, '端点（如 https://api.xiaomimimo.com/v1）', _baseUrl),
              ],
            ),
          ),
          const SizedBox(height: 14),
          QingSectionTitle('凭据'),
          QingCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('密钥统一写在系统级 /etc/hermes/.env，所有页面共用一份。',
                    style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.5, color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                if (!_useNewEnv) ...[
                  if (_creds.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in _creds.take(12))
                          ChoiceChip(
                            label: Text('${c['name']}',
                                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                            selected: _keyEnv.text == '${c['name']}',
                            onSelected: (_) =>
                                setState(() => _keyEnv.text = '${c['name']}'),
                          ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _keyEnv,
                    decoration: const InputDecoration(
                      labelText: '环境变量名（如 MY_API_KEY）',
                      isDense: true,
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _keyEnv,
                    decoration: const InputDecoration(
                      labelText: '新变量名（留空自动生成）',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _newEnv,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '密钥值（只写不读，保存后不再显示）',
                      isDense: true,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text('新建一个环境变量',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                    Switch(
                      value: _useNewEnv,
                      onChanged: (v) => setState(() => _useNewEnv = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          QingCard(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              _canSync
                                  ? (_isEdit ? '同步到 ${widget.scopes.length} 个人设' : '同步到三个人设')
                                  : '仅当前人设',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(_scopeHint,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _allScopes && _canSync,
                      onChanged:
                          _canSync ? (v) => setState(() => _allScopes = v) : null,
                    ),
                  ],
                ),
                if (_allScopes && _canSync) ...[
                  const SizedBox(height: 6),
                  Text(
                    _isEdit
                        ? '只覆盖你改动的字段；没动的字段各人设保持原值'
                        : '会把这条候选写进全部人设，便于各人设都能一键切换',
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                for (final note in _diffNotes)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            size: 12, color: Color(0xFFB5822C)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(note,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 10.5,
                                  height: 1.5,
                                  color: const Color(0xFFB5822C))),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }

  Widget _field(ThemeData theme, String label, TextEditingController c,
      {bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        enabled: enabled,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }
}
