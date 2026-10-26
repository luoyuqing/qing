import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// 清助理 · 数据与隐私
///
/// 控制 device-hub 上各类数据的保留天数：到期自动清理，随时可改。
class RetentionPage extends StatefulWidget {
  const RetentionPage({super.key});

  @override
  State<RetentionPage> createState() => _RetentionPageState();
}

class _RetentionPageState extends State<RetentionPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  final _notify = TextEditingController(text: '30');
  final _location = TextEditingController(text: '14');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notify.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await DeviceHubClient.retention();
      if (!mounted) return;
      setState(() {
        _notify.text = '${data['notify_days'] ?? 30}';
        _location.text = '${data['location_days'] ?? 14}';
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

  Future<void> _save() async {
    final notifyDays = int.tryParse(_notify.text.trim());
    final locationDays = int.tryParse(_location.text.trim());
    if (notifyDays == null || locationDays == null || notifyDays < 1 || locationDays < 1) {
      _snack('请输入大于 0 的天数');
      return;
    }
    setState(() => _saving = true);
    try {
      await DeviceHubClient.setRetention(
        notifyDays: notifyDays,
        locationDays: locationDays,
      );
      _snack('已保存，下一次清理按新策略执行');
      await _load();
    } catch (e) {
      _snack('保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据与隐私'),
        leading: Center(
          child: BackButton(onPressed: () => context.go('/rooms/settings')),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text('保留策略', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '到期后 device-hub 会自动删除对应数据；应用使用时长与日程属于长期数据，不在此列。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  const Icon(Icons.lock_outline, size: 40),
                  const SizedBox(height: 8),
                  Text('读取失败：$_error', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.tonal(onPressed: _load, child: const Text('重试')),
                ]),
              ),
            )
          else ...[
            TextField(
              controller: _notify,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '通知保留天数',
                helperText: '微信/短信等通知内容，默认 30 天',
                suffixText: '天',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _location,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '定位记录保留天数',
                helperText: '默认 14 天；定位采集在 P1 开放',
                suffixText: '天',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('保存'),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('数据在哪里', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 6),
                    Text(
                      '全部在你自己家里那台 X2（/data/device-hub）上，MCP 调用结果默认不落盘，'
                      '只记一条「谁在何时查了什么」的审计。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
