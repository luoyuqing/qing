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

  Future<void> _open(Map<String, dynamic> item) async {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
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
                      onPressed: () => Navigator.pop(context),
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
                                      Text('${e['title'] ?? e['name']}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(fontWeight: FontWeight.w600)),
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
