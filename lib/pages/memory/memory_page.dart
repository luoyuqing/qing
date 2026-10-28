import 'package:fluffychat/pages/memory/text_editor_page.dart';
import 'package:fluffychat/pages/settings_agent/memory_vault_page.dart';
import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_bottom_nav.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:material_ui/material_ui.dart';

/// 清助理 · 记忆
///
/// 四个 Tab：记忆（MEMORY.md） / 画像（USER.md） / 技能（skills/*） / 人设（config.yaml 里的设定）
/// 顶部可切换人设，覆盖 default（办公小爱）、intimate、tavern 等所有 profile。
/// 记忆与画像可直接编辑（保存前服务端自动 .bak 备份）；技能可查看、编辑、删除；
/// 人设（主设定 / 角色卡）可查看与编辑，改动会写回 Hermes 配置。
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key, this.initialPersona = 'default'});

  final String initialPersona;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  late String _persona = widget.initialPersona;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _personas = const [];
  Map<String, dynamic>? _memoryData;
  List<Map<String, dynamic>> _skills = const [];
  List<Map<String, dynamic>> _personaEntries = const [];

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
      final memory = await DeviceHubClient.memory(persona: _persona);
      final skills = await DeviceHubClient.skills(persona: _persona);
      final personaData = await DeviceHubClient.personaEntries(persona: _persona);
      if (!mounted) return;
      setState(() {
        _memoryData = memory;
        _skills = skills;
        _personaEntries = (personaData['items'] as List? ?? [])
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
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
      _personaEntries = const [];
    });
    await _load();
  }

  /// 当前人设的名字（办公小爱 / 亲密小爱 / 酒馆角色卡…）
  String get _personaLabel {
    final hit = _personas.firstWhere(
      (p) => p['id'] == _persona,
      orElse: () => <String, dynamic>{},
    );
    final label = '${hit['label'] ?? ''}';
    return label.isEmpty ? _persona : label;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: qingPageBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
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
            tooltip: '记忆库（向量记忆条目）',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MemoryVaultPage(persona: _persona),
              ),
            ),
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            const Tab(text: '记忆'),
            const Tab(text: '画像'),
            const Tab(text: '技能'),
            Tab(text: '人设${_personaEntries.isEmpty ? '' : ' · ${_personaEntries.length}'}'),
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
                    _personaTab(theme),
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
    final title = isMemory ? '${_personaLabel}的记忆' : '${_personaLabel}眼中的你';
    final subtitle = isMemory
        ? '她在对话中自己沉淀的长期记忆'
        : '画像：你的偏好、习惯与背景';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          QingCard(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primaryContainer.withAlpha(130),
                  ),
                  child: Icon(
                    isMemory ? Icons.psychology : Icons.person_pin_outlined,
                    size: 20,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$subtitle'
                        '${doc['updated_at'] == null ? '' : ' · 更新于 ${_shortTime(doc['updated_at'])}'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          color: theme.colorScheme.onSurfaceVariant
                              .withAlpha(190),
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
            QingEmpty(
              icon: Icons.article_outlined,
              title: '还没有内容',
              subtitle: '点「编辑」写下第一段，$title 会立刻生效。',
            )
          else
            QingCard(
              child: SelectableText(
                content,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editDoc(String kind, String current) async {
    final label = kind == 'memory'
        ? '编辑${_personaLabel}的记忆'
        : '编辑${_personaLabel}的画像';
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => TextEditorPage(
          title: label,
          initialText: current,
          hint: kind == 'memory'
              ? '记忆是给模型看的长期事实，建议一条一行，别写太长'
              : '画像是「${_personaLabel}眼中的你」，写清偏好/习惯/背景，她会照此调整',
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
                QingEmpty(
                  icon: Icons.auto_awesome_outlined,
                  title: '还没有技能',
                  subtitle: '$_personaLabel 还没有装任何技能（SKILL.md）。',
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              itemCount: _skills.length,
              itemBuilder: (context, i) {
                final skill = _skills[i];
                return QingCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
                  onTap: () => _openSkill(skill),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.secondaryContainer
                              .withAlpha(140),
                        ),
                        child: Icon(Icons.auto_awesome,
                            size: 18,
                            color: theme.colorScheme.onSecondaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${skill['name'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${skill['description'] ?? ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(height: 1.4),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_shortTime(skill['updated_at'])} · '
                              '${((skill['size'] as num?) ?? 0) ~/ 1024} KB',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withAlpha(160),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '删除',
                        icon: Icon(Icons.delete_outline,
                            color: theme.colorScheme.error),
                        onPressed: () => _deleteSkill(skill),
                      ),
                    ],
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
            title: '$_personaLabel · ${skill['name']}',
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

  // ---------------- 人设 ----------------

  Widget _personaTab(ThemeData theme) {
    if (_personaEntries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 60),
          children: [
            QingEmpty(
              icon: Icons.face_retouching_natural,
              title: '没有找到人设文件',
              subtitle: '$_personaLabel 的 Hermes 配置里没读到 agent.personalities，'
                  '可能这个 profile 还没设置。',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        itemCount: _personaEntries.length,
        itemBuilder: (context, i) {
          final entry = _personaEntries[i];
          final content = '${entry['content'] ?? ''}';
          final preview = content
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          return QingCard(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            onTap: () => _openPersona(entry),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      entry['primary'] == true
                          ? Icons.star_rounded
                          : Icons.auto_stories_outlined,
                      size: 18,
                      color: entry['primary'] == true
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant
                              .withAlpha(180),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${entry['label'] ?? entry['key']}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${entry['key']}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            theme.colorScheme.onSurfaceVariant.withAlpha(150),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_outlined, size: 15),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  preview.isEmpty ? '（空）' : preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.55,
                    color: theme.colorScheme.onSurface.withAlpha(200),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openPersona(Map<String, dynamic> entry) async {
    final key = '${entry['key']}';
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => TextEditorPage(
          title: '$_personaLabel · ${entry['label'] ?? key}',
          initialText: '${entry['content'] ?? ''}',
          hint: '人设设定：写清她的身份、语气、边界和做事方式；'
              '保存后写回 Hermes 配置（新会话生效）',
        ),
      ),
    );
    if (result == null) return;
    try {
      await DeviceHubClient.savePersona(
        persona: _persona,
        key: key,
        content: result,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('人设已保存，新会话生效')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
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
