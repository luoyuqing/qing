import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:flutter/material.dart';

/// 清助理 · 编辑辅助模型
///
/// 对应 config.yaml 的 `auxiliary.<key>`：上下文压缩、图片理解等不直接参与聊天、
/// 但会消耗额度的后台任务。改完下一轮生效。
class AuxiliaryEditPage extends StatefulWidget {
  const AuxiliaryEditPage({
    super.key,
    required this.persona,
    required this.item,
  });

  final String persona;
  final Map<String, dynamic> item;

  @override
  State<AuxiliaryEditPage> createState() => _AuxiliaryEditPageState();
}

class _AuxiliaryEditPageState extends State<AuxiliaryEditPage> {
  late final TextEditingController _model =
      TextEditingController(text: '${widget.item['model'] ?? ''}');
  late final TextEditingController _baseUrl =
      TextEditingController(text: '${widget.item['base_url'] ?? ''}');
  late final TextEditingController _keyEnv =
      TextEditingController(text: '${widget.item['key_env'] ?? ''}');

  List<Map<String, dynamic>> _creds = const [];
  bool _saving = false;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    _loadCreds();
  }

  @override
  void dispose() {
    _model.dispose();
    _baseUrl.dispose();
    _keyEnv.dispose();
    super.dispose();
  }

  Future<void> _loadCreds() async {
    try {
      final items = await DeviceHubClient.credentials();
      if (!mounted) return;
      setState(() => _creds = items
          .where((e) => '${e['name']}'.contains('KEY'))
          .toList());
    } catch (_) {}
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pickModel() async {
    final base = _baseUrl.text.trim();
    if (!base.startsWith('http')) {
      _toast('先把端点填好，再拉模型列表');
      return;
    }
    setState(() => _fetching = true);
    try {
      final data = await DeviceHubClient.endpointModels(
        baseUrl: base,
        keyEnv: _keyEnv.text.trim(),
      );
      final models =
          ((data['models'] as List?) ?? const []).map((e) => '$e').toList();
      if (!mounted) return;
      if (models.isEmpty) {
        _toast('该端点没有返回模型列表');
        return;
      }
      final picked = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.6,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                  child: Row(
                    children: [
                      Text('选择模型（${models.length}）',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text(base,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const Divider(height: 0.5),
                Expanded(
                  child: ListView.builder(
                    itemCount: models.length,
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      title: Text(models[i],
                          style: Theme.of(context).textTheme.bodySmall),
                      trailing: models[i] == _model.text
                          ? Icon(Icons.check,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary)
                          : null,
                      onTap: () => Navigator.pop(context, models[i]),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
    final model = _model.text.trim();
    final base = _baseUrl.text.trim();
    if (model.isEmpty || base.isEmpty) {
      _toast('模型与端点不能为空');
      return;
    }
    setState(() => _saving = true);
    try {
      await DeviceHubClient.saveAuxiliary(
        persona: widget.persona,
        key: '${widget.item['key']}',
        model: model,
        baseUrl: base,
        keyEnv: _keyEnv.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('保存失败：$e');
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
        title: Text('编辑${widget.item['label'] ?? widget.item['key']}'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          QingCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _model,
                  decoration: InputDecoration(
                    labelText: '模型 ID',
                    isDense: true,
                    suffixIcon: _fetching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: '从端点拉取模型列表',
                            onPressed: _pickModel,
                            icon: const Icon(Icons.list_alt, size: 20),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _baseUrl,
                  decoration: const InputDecoration(
                    labelText: '端点（如 http://127.0.0.1:3010/v1）',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Text('凭据（环境变量）',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                if (_creds.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in _creds.take(12))
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
                const SizedBox(height: 8),
                TextField(
                  controller: _keyEnv,
                  decoration: const InputDecoration(
                    labelText: '环境变量名（如 GPTLOAD_API_KEY）',
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '上下文压缩用的模型只处理长对话摘要，换它不会影响聊天主模型。'
            '改完下一轮对话生效，不需要重启。',
            style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11, height: 1.6, color: theme.colorScheme.onSurfaceVariant),
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
}
