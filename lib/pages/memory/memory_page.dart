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
              Text('办公小爱记得的事', style: theme.textTheme.titleSmall),
              if (_updatedAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('更新于 ${_updatedAt!.replaceFirst('T', ' ')}',
                      style: theme.textTheme.bodySmall),
                ),
              const SizedBox(height: 12),
              for (final block in blocks)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(_stripLeadingMarker(block),
                        style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
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
