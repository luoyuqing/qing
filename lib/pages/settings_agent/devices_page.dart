import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:flutter/material.dart';

/// 清助理 · 已配对设备
///
/// 每台手机一个 token；丢了或换机就在这里吊销。
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
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
      final items = await DeviceHubClient.devices();
      if (!mounted) return;
      setState(() {
        _items = items.where((e) => e['revoked'] != 1).toList();
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

  Future<void> _revoke(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('吊销这台设备'),
        content: Text('吊销后「${d['name']}」需要重新配对才能同步数据。\n'
            '如果这是当前手机，吊销后本机也会失去连接。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('吊销'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DeviceHubClient.revokeDevice('${d['id']}');
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已吊销')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('吊销失败：$e')));
    }
  }

  String _ago(Object? iso) {
    final dt = DateTime.tryParse('${iso ?? ''}');
    if (dt == null) return '从未同步';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return '刚刚同步';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: qingPageBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('已配对设备')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      QingCard(child: Text('读取失败：$_error', style: theme.textTheme.bodySmall)),
                    ],
                  )
                : _items.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.only(top: 80),
                        children: const [
                          QingEmpty(
                            icon: Icons.phonelink_lock_outlined,
                            title: '还没有配对的设备',
                            subtitle: '在这台手机上完成配对后会出现在这里',
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final d = _items[i];
                          return QingCard(
                            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${d['name'] ?? '未命名设备'}',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${d['id']}',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                            fontSize: 10.5,
                                            color: theme.colorScheme.onSurfaceVariant),
                                      ),
                                      const SizedBox(height: 1),
                                      Text('${_ago(d['last_seen'])} · 配对于 ${d['created_at'] ?? ''}'.split('T').first,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                              fontSize: 10.5,
                                              color: theme.colorScheme.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _revoke(d),
                                  style: TextButton.styleFrom(
                                    foregroundColor: theme.colorScheme.error,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: const Text('吊销', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
