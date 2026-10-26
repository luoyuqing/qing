import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_bottom_nav.dart';
import 'package:material_ui/material_ui.dart';

/// 清助理 · 记忆（仅办公小爱）
///
/// 展示办公小爱的长期记忆（Hermes MEMORY.md，只读）。
/// 记忆由小爱在日常对话中自行沉淀，这里给用户一个「她都记得什么」的透明视图。
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key});

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  bool _loading = true;
  String? _error;
  String? _content;
  String? _updatedAt;
  List<String> _files = const [];

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
      final data = await DeviceHubClient.getJson('/memory');
      if (!mounted) return;
      setState(() {
        _content = data['content'] as String?;
        _updatedAt = data['updated_at'] as String?;
        _files = (data['files'] as List? ?? []).map((e) => '$e').toList();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blocks = (_content ?? '')
        .split('§')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    const Icon(Icons.psychology_outlined, size: 40),
                    const SizedBox(height: 12),
                    const Text('读取失败'),
                    const SizedBox(height: 8),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 12),
                    FilledButton.tonal(onPressed: _load, child: const Text('重试')),
                  ]),
                ),
              )
            else if (blocks.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Icon(Icons.psychology_outlined,
                        size: 40, color: theme.colorScheme.outline),
                    const SizedBox(height: 12),
                    const Text('还没有记忆'),
                    const SizedBox(height: 8),
                    Text('和小爱多聊聊，她会把重要的事记在这里',
                        style: theme.textTheme.bodySmall),
                  ]),
                ),
              )
            else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.tertiaryContainer,
                      theme.colorScheme.primaryContainer,
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.psychology, color: theme.colorScheme.onTertiaryContainer),
                      const SizedBox(width: 8),
                      Text('办公小爱的记忆',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onTertiaryContainer,
                          )),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      '${blocks.length} 条记忆'
                      '${_updatedAt == null ? '' : ' · 更新于 ${_updatedAt!.substring(0, 16).replaceFirst('T', ' ')}'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer.withAlpha(200),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < blocks.length; i++)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.secondaryContainer,
                          ),
                          child: Text('${i + 1}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSecondaryContainer,
                              )),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(_stripLeadingMarker(blocks[i]),
                              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_files.length > 1) ...[
                const SizedBox(height: 8),
                Text('记忆文件：${_files.join('、')}',
                    style: theme.textTheme.bodySmall),
              ],
            ],
          ],
        ),
      ),
      bottomNavigationBar: const QingBottomNav(currentIndex: 3),
    );
  }

  String _stripLeadingMarker(String s) {
    var t = s;
    while (t.startsWith('-') || t.startsWith('*')) {
      t = t.substring(1).trimLeft();
    }
    return t;
  }
}
