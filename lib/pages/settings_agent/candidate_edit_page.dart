import 'package:fluffychat/pages/settings_agent/model_picker.dart';
import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:flutter/material.dart';

/// Qing · 新增 / 编辑候选模型
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
  String _apiMode = 'chat_completions';
  String _reasoning = 'medium';

  /// Hermes 认可的思考档位（hermes_constants.VALID_REASONING_EFFORTS + none）
  static const Map<String, String> _reasoningLabels = {
    'none': '关闭思考',
    'minimal': '最低',
    'low': '低',
    'medium': '中（默认）',
    'high': '高',
    'xhigh': '很高',
    'max': '最高',
    'ultra': '极限',
  };
  List<Map<String, dynamic>> _creds = const [];
  String _credQuery = '';
  final TextEditingController _credSearch = TextEditingController();

  // 校验失败时把错误直接标在对应输入框下面，避免只弹一个被键盘遮住的
  // SnackBar，让用户以为「点保存没反应」。
  String? _errKey;
  String? _errModel;
  String? _errBaseUrl;
  String? _errNewEnv;
  final ScrollController _scroll = ScrollController();
  final GlobalKey _credAnchor = GlobalKey();

  /// 只把「像密钥」的变量放进快选区，避免把 SMTP_PASS 之类也塞进来。
  /// 注意不能只认 _API_KEY / KEY：CF2_PAGES_TOKEN、comfy-token 这类会漏。
  List<Map<String, dynamic>> get _filteredCreds {
    final q = _credQuery.trim().toUpperCase();
    if (q.isEmpty) return _creds;
    return _creds
        .where((e) => '${e['name']}'.toUpperCase().contains(q))
        .toList(growable: false);
  }

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
    // 空值按聊天补全处理，与后端默认一致
    _apiMode = '${e['api_mode'] ?? ''}'.trim();
    if (_apiMode.isEmpty) _apiMode = 'chat_completions';
    // 思考模式：老候选没配过时按默认 medium
    final savedReasoning = '${e['reasoning_effort'] ?? ''}'.trim().toLowerCase();
    _reasoning = _reasoningLabels.containsKey(savedReasoning)
        ? savedReasoning
        : 'medium';
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
    _credSearch.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadCreds() async {
    try {
      final items = await DeviceHubClient.credentials();
      if (!mounted) return;
      setState(() => _creds = items.where((e) {
            final n = '${e['name']}'.toUpperCase();
            return n.contains('KEY') ||
                n.contains('TOKEN') ||
                n.contains('SECRET');
          }).toList());
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

  /// 把任意输入规整成合法的候选标识：小写、非 a-z0-9_ 一律转下划线、≤24 位
  static String _slugKey(String raw) {
    var s = raw.toLowerCase().trim();
    s = s.replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
    s = s.replaceAll(RegExp(r'^_+|_+$'), '');
    if (s.length > 24) s = s.substring(0, 24);
    return s;
  }

  static final RegExp _keyRe = RegExp(r'^[a-z0-9_]{2,24}$');

  Future<void> _save() async {
    final label = _label.text.trim();
    final model = _model.text.trim();
    final baseUrl = _baseUrl.text.trim();

    // 标识是内部唯一键，不该因为用户填了中文就卡住保存：
    // 非法时先用「模型 ID」规整，再不行才报错。
    var key = _key.text.trim();
    String? errKey;
    if (!_isEdit && !_keyRe.hasMatch(key)) {
      final auto = _slugKey(model);
      if (_keyRe.hasMatch(auto)) {
        key = auto;
        _key.text = auto;
      } else {
        errKey = '标识只能用英文/数字/下划线（2-24 位），或留空自动取模型名';
      }
    }

    final errModel = model.isEmpty ? '模型 ID 不能为空' : null;
    final errBaseUrl = baseUrl.isEmpty
        ? '端点不能为空'
        : (!baseUrl.startsWith('http') ? '端点必须以 http:// 或 https:// 开头' : null);
    final errNewEnv = (_useNewEnv && _newEnv.text.trim().isEmpty)
        ? '填一下密钥值，或关掉「新建一个环境变量」'
        : null;
    setState(() {
      _errKey = errKey;
      _errModel = errModel;
      _errBaseUrl = errBaseUrl;
      _errNewEnv = errNewEnv;
    });
    if (errKey != null ||
        errModel != null ||
        errBaseUrl != null ||
        errNewEnv != null) {
      final message = errKey ?? errModel ?? errBaseUrl ?? errNewEnv!;
      _toast(message);
      _revealError(cred: errNewEnv != null);
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
        put('api_mode', _apiMode);
        put('reasoning_effort', _reasoning);
        final ke = _keyEnv.text.trim();
        if (ke.isNotEmpty && ke != '${e['key_env'] ?? ''}') payload['key_env'] = ke;
        // 「新建一个环境变量」在编辑态同样生效：把密钥值交给服务端写入 .env
        if (_useNewEnv) {
          payload['new_env_value'] = _newEnv.text.trim();
        }
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
          apiMode: _apiMode,
          reasoningEffort: _reasoning,
          // 新增时也尊重用户填的「新变量名」；留空才由服务端按 KEY 自动生成
          keyEnv: _keyEnv.text.trim(),
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
    // 先收键盘：否则 SnackBar 会被软键盘整个盖住，看起来像「点了没反应」
    FocusManager.instance.primaryFocus?.unfocus();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// 把出错的字段滚进视野：凭据区的问题滚到凭据卡，其余滚回顶部信息卡
  void _revealError({required bool cred}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (cred) {
        final ctx = _credAnchor.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignment: 0.05,
          );
        }
        return;
      }
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
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
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          QingCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _field(
                  theme,
                  '标识（内部唯一键）',
                  _key,
                  enabled: !_isEdit,
                  helperText: '留空自动取模型名，如 kimi_k3；只能用英文/数字/下划线',
                  errorText: _errKey,
                  onErrorClear: () => _errKey = null,
                ),
                _field(theme, '显示名（如 MiMo 备用）', _label),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _model,
                    onChanged: (_) {
                      if (_errModel != null) setState(() => _errModel = null);
                    },
                    decoration: InputDecoration(
                      labelText: '模型 ID（如 mimo-v2.6-flash）',
                      isDense: true,
                      errorText: _errModel,
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
                _field(
                  theme,
                  '端点（如 https://api.xiaomimimo.com/v1）',
                  _baseUrl,
                  errorText: _errBaseUrl,
                  onErrorClear: () => _errBaseUrl = null,
                ),
                const SizedBox(height: 2),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '接口类型',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'chat_completions',
                      label: Text('聊天补全'),
                      icon: Icon(Icons.chat_outlined, size: 16),
                    ),
                    ButtonSegment(
                      value: 'codex_responses',
                      label: Text('Responses'),
                      icon: Icon(Icons.data_object, size: 16),
                    ),
                  ],
                  selected: {_apiMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) =>
                      setState(() => _apiMode = v.first),
                ),
                const SizedBox(height: 6),
                Text(
                  _apiMode == 'codex_responses'
                      ? '走 /v1/responses，适合支持 Responses 协议的端点；'
                          '普通 OpenAI 兼容中转多数用聊天补全。'
                      : '走 /v1/chat/completions，兼容性最好。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10.5,
                    height: 1.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _reasoning,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: '思考模式',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final e in _reasoningLabels.entries)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _reasoning = v ?? 'medium'),
                ),
                const SizedBox(height: 6),
                Text(
                  '切到这个候选时写入人设的 agent.reasoning_effort；'
                  '默认「中」，选「关闭思考」表示不向端点请求推理。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10.5,
                    height: 1.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          KeyedSubtree(
            key: _credAnchor,
            child: const QingSectionTitle('凭据'),
          ),
          QingCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('密钥统一写在系统级 /etc/hermes/.env，所有页面共用一份。',
                    style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.5, color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                if (!_useNewEnv) ...[
                  if (_creds.isNotEmpty) ...[
                    if (_creds.length > 10)
                      TextField(
                        controller: _credSearch,
                        onChanged: (v) => setState(() => _credQuery = v),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: '搜索凭据（共 ${_creds.length} 个）',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _credQuery.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: '清空搜索',
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    _credSearch.clear();
                                    setState(() => _credQuery = '');
                                  },
                                ),
                        ),
                      ),
                    if (_creds.length > 10) const SizedBox(height: 8),
                    if (_filteredCreds.isEmpty)
                      Text(
                        '没有匹配的凭据',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final c in _filteredCreds)
                            ChoiceChip(
                              label: Text('${c['name']}',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(fontSize: 11)),
                              selected: _keyEnv.text == '${c['name']}',
                              onSelected: (_) =>
                                  setState(() => _keyEnv.text = '${c['name']}'),
                            ),
                        ],
                      ),
                  ],
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
                    onChanged: (_) {
                      if (_errNewEnv != null) {
                        setState(() => _errNewEnv = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: '密钥值（只写不读，保存后不再显示）',
                      isDense: true,
                      errorText: _errNewEnv,
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
      {bool enabled = true,
      String? errorText,
      String? helperText,
      VoidCallback? onErrorClear}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          helperText: helperText,
          errorText: errorText,
        ),
        onChanged: (_) {
          if (errorText != null) {
            setState(() => onErrorClear?.call());
          }
        },
      ),
    );
  }
}
