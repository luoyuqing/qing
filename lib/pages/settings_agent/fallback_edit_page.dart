import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:flutter/material.dart';

/// 清助理 · 备用链编辑
///
/// 主模型失败（超时/限流/连不上）时按这里的顺序降级。
/// 保存是整链替换，服务端会先备份再校验。
class FallbackEditPage extends StatefulWidget {
  const FallbackEditPage({
    super.key,
    required this.persona,
    required this.chain,
    required this.candidates,
  });

  final String persona;
  final List<Map<String, dynamic>> chain;
  final List<Map<String, dynamic>> candidates;

  @override
  State<FallbackEditPage> createState() => _FallbackEditPageState();
}

class _FallbackEditPageState extends State<FallbackEditPage> {
  late List<Map<String, dynamic>> _items =
      widget.chain.map((e) => Map<String, dynamic>.from(e)).toList();
  bool _saving = false;

  void _move(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _items.length) return;
    setState(() {
      final tmp = _items[i];
      _items[i] = _items[j];
      _items[j] = tmp;
    });
  }

  Future<void> _add() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('从候选池添加', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            for (final c in widget.candidates)
              ListTile(
                title: Text('${c['label'] ?? c['key']}'),
                subtitle: Text('${c['model']} · ${c['base_url']}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(context, c),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final exists = _items.any((e) =>
        '${e['base_url']}' == '${picked['base_url']}' && '${e['model']}' == '${picked['model']}');
    if (exists) return;
    setState(() {
      _items.add({
        'provider': 'custom',
        'model': '${picked['model']}',
        'base_url': '${picked['base_url']}',
        'key_env': '${picked['key_env'] ?? ''}',
      });
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('备用链不能为空')));
      return;
    }
    setState(() => _saving = true);
    try {
      await DeviceHubClient.saveFallback(
        persona: widget.persona,
        chain: _items
            .map((e) => {
                  'provider': '${e['provider'] ?? 'custom'}',
                  'model': '${e['model']}',
                  'base_url': '${e['base_url']}',
                  'key_env': '${e['key_env'] ?? ''}',
                })
            .toList(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: qingPageBackground(context),
      appBar: AppBar(
        title: const Text('编辑备用链'),
        actions: [
          IconButton(
            tooltip: '添加',
            onPressed: _add,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final e = _items[i];
                return QingCard(
                  padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('${i + 1}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.primary)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${e['model']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('${e['base_url']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '上移',
                        onPressed: i == 0 ? null : () => _move(i, -1),
                        icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                      ),
                      IconButton(
                        tooltip: '下移',
                        onPressed: i == _items.length - 1 ? null : () => _move(i, 1),
                        icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                      ),
                      IconButton(
                        tooltip: '删除',
                        onPressed: () => setState(() => _items.removeAt(i)),
                        icon: Icon(Icons.close,
                            size: 18, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              children: [
                Text('按顺序尝试；保存在服务端会先备份 config.yaml 再整链替换。',
                    style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  child: Text(_saving ? '保存中…' : '保存备用链'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
