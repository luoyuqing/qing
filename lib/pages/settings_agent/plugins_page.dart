import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:flutter/material.dart';

/// Qing · 插件与能力
///
/// 只读展示：X2 上 hermes 已安装的插件与内置能力。
class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key});

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

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
      final items = await DeviceHubClient.plugins();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installed = _items.where((e) => e['kind'] == 'installed').toList();
    final builtin = _items.where((e) => e['kind'] != 'installed').toList();
    return Scaffold(
      backgroundColor: qingPageBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('插件与能力')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      QingCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('读取失败', style: theme.textTheme.titleSmall),
                            const SizedBox(height: 6),
                            Text('$_error',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 12),
                            FilledButton.tonal(
                                onPressed: _load, child: const Text('重试')),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                    children: [
                      QingSectionTitle('已安装 · ${installed.length}'),
                      if (installed.isEmpty)
                        QingCard(
                            child: Text('没有第三方插件',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)))
                      else
                        for (final p in installed) ...[
                          _pluginCard(theme, p),
                          const SizedBox(height: 10),
                        ],
                      const SizedBox(height: 12),
                      QingSectionTitle('内置 · ${builtin.length}'),
                      for (final p in builtin) ...[
                        _pluginCard(theme, p),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 6),
                      Text('插件只读展示。需要停用请在 X2 上操作，避免误关记忆与取数能力。',
                          style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              height: 1.6,
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
      ),
    );
  }

  Widget _pluginCard(ThemeData theme, Map<String, dynamic> p) {
    final hooks = ((p['hooks'] as List?) ?? const []).map((e) => '$e').toList();
    final desc = '${p['description'] ?? ''}'.trim();
    return QingCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${p['name'] ?? '-'}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if ('${p['version'] ?? ''}'.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('v${p['version']}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10.5, color: theme.colorScheme.primary)),
                ),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(desc,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.45, color: theme.colorScheme.onSurfaceVariant)),
          ],
          if (hooks.isNotEmpty) ...[
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final h in hooks.take(4))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: theme.colorScheme.outlineVariant, width: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(h,
                        style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10.5,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
