import 'package:fluffychat/pages/memory/text_editor_page.dart';
import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/markdown_view.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:flutter/material.dart';

/// Qing · 记忆库
///
/// 读的是 X2 上 zvec-memory 的 facts 目录（按人设分开存）。
/// 每条是一个 Markdown 文件，可搜索、可看全文。
class MemoryVaultPage extends StatefulWidget {
  const MemoryVaultPage({super.key, this.persona = 'default'});

  final String persona;

  @override
  State<MemoryVaultPage> createState() => _MemoryVaultPageState();
}

class _MemoryVaultPageState extends State<MemoryVaultPage> {
  final _search = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await DeviceHubClient.vault(persona: widget.persona, q: _q);
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

  /// 剥掉 fact 的标题行与 frontmatter，只留正文给编辑器
  static String _bodyOf(String raw) {
    final lines = raw.split('\n');
    var i = 0;
    while (i < lines.length) {
      final l = lines[i].trim();
      if (i == 0 && l.startsWith('# ')) {
        i++;
        continue;
      }
      if (l.isEmpty || RegExp(r'^[a-z_]+:\s').hasMatch(l)) {
        i++;
        continue;
      }
      break;
    }
    return lines.sublist(i).join('\n').trim();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _edit(Map<String, dynamic> item, BuildContext dialogContext) async {
    String raw;
    try {
      raw = await DeviceHubClient.vaultNote(
        persona: widget.persona,
        name: '${item['name']}',
      );
    } catch (e) {
      _toast('读取失败：$e');
      return;
    }
    if (!mounted) return;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => TextEditorPage(
          title: '编辑记忆',
          initialText: _bodyOf(raw),
          hint: '第一行会成为标题；改完检索立刻生效（向量部分稍后收敛）',
        ),
      ),
    );
    if (result == null || !mounted) return;
    try {
      await DeviceHubClient.vaultNoteSave(
        persona: widget.persona,
        name: '${item['name']}',
        content: result,
      );
      if (!mounted) return;
      Navigator.pop(dialogContext);
      await _load();
      _toast('已保存');
    } catch (e) {
      _toast('保存失败：$e');
    }
  }

  Future<void> _delete(Map<String, dynamic> item, BuildContext dialogContext) async {
    final theme = Theme.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除这条记忆'),
        content: Text(
          '「${item['title'] ?? item['name']}」\n\n'
          '会移到服务器的 .trash 目录（不是立刻真删），但小爱将不再检索到它。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await DeviceHubClient.vaultNoteDelete(
        persona: widget.persona,
        name: '${item['name']}',
      );
      if (!mounted) return;
      Navigator.pop(dialogContext);
      await _load();
      _toast('已删除');
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  Future<void> _open(Map<String, dynamic> item) async {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          height: MediaQuery.sizeOf(dialogContext).height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${item['title'] ?? item['name']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 0.5),
              Expanded(
                child: FutureBuilder<String>(
                  future: DeviceHubClient.vaultNote(
                    persona: widget.persona,
                    name: '${item['name']}',
                  ),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Center(child: Text('读取失败：${snap.error}'));
                    }
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                      child: MarkdownView(data: snap.data ?? ''),
                    );
                  },
                ),
              ),
              const Divider(height: 0.5),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
                child: Row(
                  children: [
                    if (item['editable'] == true) ...[
                      TextButton.icon(
                        onPressed: () => _edit(item, dialogContext),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('编辑'),
                      ),
                      TextButton.icon(
                        onPressed: () => _delete(item, dialogContext),
                        style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('删除'),
                      ),
                      const Spacer(),
                    ] else
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            '来自「记忆/画像」的镜像条目，请到记忆页改原文',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _items.fold<int>(0, (s, e) => s + ((e['size'] as num?)?.toInt() ?? 0));
    return Scaffold(
      backgroundColor: qingPageBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('记忆库')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索记忆标题或内容',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _q.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _q = '');
                          _load();
                        },
                      ),
              ),
              onSubmitted: (v) {
                setState(() => _q = v.trim());
                _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('${_items.length} 条',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const Spacer(),
                Text('${(total / 1024).toStringAsFixed(0)} KB',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
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
                                    style: theme.textTheme.bodySmall)),
                          ],
                        )
                      : _items.isEmpty
                          ? ListView(
                              padding: const EdgeInsets.only(top: 70),
                              children: const [
                                QingEmpty(
                                  icon: Icons.psychology_outlined,
                                  title: '还没有记忆条目',
                                  subtitle: '小爱记住重要的内容后，会出现在这里',
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final e = _items[i];
                                final excerpt = '${e['excerpt'] ?? ''}';
                                return QingCard(
                                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                                  onTap: () => _open(e),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text('${e['title'] ?? e['name']}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: theme.textTheme.bodyMedium
                                                    ?.copyWith(
                                                        fontWeight: FontWeight.w600)),
                                          ),
                                          if (e['is_mirror'] == true)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 5, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant
                                                    .withValues(alpha: 0.08),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text('镜像',
                                                  style: theme.textTheme.bodySmall
                                                      ?.copyWith(
                                                          fontSize: 9.5,
                                                          color: theme.colorScheme
                                                              .onSurfaceVariant)),
                                            ),
                                        ],
                                      ),
                                      if (excerpt.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(excerpt,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall?.copyWith(
                                                height: 1.45,
                                                color:
                                                    theme.colorScheme.onSurfaceVariant)),
                                      ],
                                      const SizedBox(height: 6),
                                      Text('${e['updated_at'] ?? ''}'.replaceFirst('T', ' ').split('+').first,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                              fontSize: 10.5,
                                              color: theme.colorScheme.onSurfaceVariant
                                                  .withValues(alpha: 0.8))),
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
