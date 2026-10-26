import 'package:fluffychat/pages/memory/text_editor_page.dart';
import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_bottom_nav.dart';
import 'package:material_ui/material_ui.dart';

/// 清助理 · 记忆
///
/// 三个 Tab：记忆（MEMORY.md） / 画像（USER.md） / 技能（skills/*）
/// 顶部可切换人设，覆盖 default（办公小爱）、intimate、tavern 等所有 profile。
/// 记忆与画像可直接编辑（保存前服务端自动 .bak 备份）；技能可查看、编辑、删除。
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key, this.initialPersona = 'default'});

  final String initialPersona;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  late String _persona = widget.initialPersona;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _personas = const [];
  Map<String, dynamic>? _memoryData;
  List<Map<String, dynamic>> _skills = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_personas.isEmpty) {
        _personas = await DeviceHubClient.personas();
      }
      final results = await Future.wait([
        DeviceHubClient.memory(persona: _persona),
        DeviceHubClient.skills(persona: _persona),
      ]);
      if (!mounted) return;
      setState(() {
        _memoryData = results[0];
        _skills = results[1];
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

  Future<void> _switchPersona(String pid) async {
    if (pid == _persona) return;
    setState(() {
      _persona = pid;
      _memoryData = null;
      _skills = const [];
    });
    await _load();
  }

  String get _personaLabel {
    final hit = _personas.firstWhere(
      (p) => p['id'] == _persona,
      orElse: () => <String, dynamic>{},
    );
    return '${hit['label'] ?? _persona}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆'),
        actions: [
          PopupMenuButton<String>(
            tooltip: '切换人设',
            onSelected: _switchPersona,
            itemBuilder: (context) => [
              for (final p in _personas)
                PopupMenuItem(
                  value: '${p['id']}',
                  child: Row(
                    children: [
                      Icon(
                        p['id'] == _persona
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${p['label'] ?? p['id']}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${p['skill_count'] ?? 0} 技能',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.face_outlined, size: 18),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(
                      _personaLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '记忆'),
            Tab(text: '画像'),
            Tab(text: '技能'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView(theme)
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _docTab(theme, 'memory'),
                    _docTab(theme, 'profile'),
                    _skillsTab(theme),
                  ],
                ),
      bottomNavigationBar: const QingBottomNav(currentIndex: 3),
    );
  }

  Widget _errorView(ThemeData theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, size: 40),
            const SizedBox(height: 8),
            const Text('读取失败'),
            const SizedBox(height: 6),
            Text(_error!,
                textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: _load, child: const Text('重试')),
          ]),
        ),
      );

  // ---------------- 记忆 / 画像 ----------------

  Widget _docTab(ThemeData theme, String kind) {
    final doc = (_memoryData?[kind] as Map?) ?? const {};
    final content = doc['content'] as String?;
    final isMemory = kind == 'memory';
    final title = isMemory ? '办公小爱的记忆' : '小爱对你的了解';
    final subtitle = isMemory
        ? '她在对话中自己沉淀的长期记忆'
        : '画像：你的偏好、习惯与背景';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.tertiaryContainer,
                  theme.colorScheme.primaryContainer,
                ],
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isMemory ? Icons.psychology : Icons.person_pin_outlined,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${subtitle}'
                        '${doc['updated_at'] == null ? '' : ' · 更新于 ${_shortTime(doc['updated_at'])}'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer
                              .withAlpha(210),
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _editDoc(kind, content ?? ''),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('编辑'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (content == null || content.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(children: [
                Icon(Icons.article_outlined,
                    size: 40, color: theme.colorScheme.outline),
                const SizedBox(height: 8),
                Text('这个文件还是空的，点「编辑」可以写下第一段',
                    style: theme.textTheme.bodySmall),
              ]),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                child: SelectableText(
                  content,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editDoc(String kind, String current) async {
    final label = kind == 'memory' ? '编辑记忆' : '编辑画像';
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => TextEditorPage(
          title: label,
          initialText: current,
          hint: kind == 'memory'
              ? '记忆是给模型看的长期事实，建议一条一行，别写太长'
              : '画像是「小爱眼中的你」，写清偏好/习惯/背景，她会照此调整',
        ),
      ),
    );
    if (result == null) return;
    try {
      await DeviceHubClient.saveMemory(
        persona: _persona,
        kind: kind,
        content: result,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  // ---------------- 技能 ----------------

  Widget _skillsTab(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _load,
      child: _skills.isEmpty
          ? ListView(
              padding: const EdgeInsets.symmetric(vertical: 60),
              children: [
                Icon(Icons.auto_awesome_outlined,
                    size: 40, color: theme.colorScheme.outline),
                const SizedBox(height: 8),
                Center(
                  child: Text('这个人设还没有技能',
                      style: theme.textTheme.bodySmall),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _skills.length,
              itemBuilder: (context, i) {
                final skill = _skills[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.secondaryContainer,
                      child: const Icon(Icons.auto_awesome, size: 18),
                    ),
                    title: Text('${skill['name'] ?? ''}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 3),
                        Text(
                          '${skill['description'] ?? ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_shortTime(skill['updated_at'])} · '
                          '${((skill['size'] as num?) ?? 0) ~/ 1024} KB',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      tooltip: '删除',
                      icon: Icon(Icons.delete_outline,
                          color: theme.colorScheme.error),
                      onPressed: () => _deleteSkill(skill),
                    ),
                    onTap: () => _openSkill(skill),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _openSkill(Map<String, dynamic> skill) async {
    final path = '${skill['path']}';
    try {
      final data = await DeviceHubClient.skill(path, persona: _persona);
      if (!mounted) return;
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => TextEditorPage(
            title: '${skill['name']}',
            initialText: '${data['content'] ?? ''}',
            hint: '技能文件（SKILL.md），删掉整段就会失效；保存后立即对小爱生效',
            monospace: true,
          ),
        ),
      );
      if (result == null) return;
      await DeviceHubClient.saveSkill(path, persona: _persona, content: result);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('技能已保存')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败：$e')),
      );
    }
  }

  Future<void> _deleteSkill(Map<String, dynamic> skill) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除技能？'),
        content: Text('「${skill['name']}」会被整个删除，删除后小爱将失去这项能力。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DeviceHubClient.deleteSkill(
        '${skill['path']}',
        persona: _persona,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('技能已删除')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    }
  }

  String _shortTime(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return value.replaceFirst('T', ' ').split('+').first;
    }
    if (value is num) {
      final dt = DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
      return '${dt.month}-${dt.day} ${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    }
    return '';
  }
}
