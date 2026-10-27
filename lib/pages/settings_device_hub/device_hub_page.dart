import 'package:fluffychat/utils/device_hub/device_data_bridge.dart';
import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:fluffychat/utils/qing_boot.dart';
import 'package:go_router/go_router.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:material_ui/material_ui.dart';

/// 清助理 · 设备数据设置页
///
/// 用户在这里：填服务器地址 → 输入配对码 → 逐项授权 → 手动/自动同步。
/// 所有开关都由系统权限决定，App 不绕过任何授权。
class DeviceHubPage extends StatefulWidget {
  const DeviceHubPage({super.key});

  @override
  State<DeviceHubPage> createState() => _DeviceHubPageState();
}

class _DeviceHubPageState extends State<DeviceHubPage> with WidgetsBindingObserver {
  final _urlController = TextEditingController();
  final _codeController = TextEditingController();

  DevicePermissionStatus? _status;
  bool _paired = false;
  bool _busy = false;
  String? _lastSync;
  String? _lastReport;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从系统设置页返回时刷新权限状态
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _load() async {
    final url = await DeviceHubClient.baseUrl();
    final paired = await DeviceHubClient.isPaired();
    final lastSync = await DeviceHubClient.lastSync();
    final lastReport = await DeviceHubClient.lastReport();
    final status = await _safeStatus();
    if (!mounted) return;
    setState(() {
      _urlController.text = url;
      _paired = paired;
      _lastSync = lastSync;
      _lastReport = lastReport;
      _status = status;
    });
  }

  Future<DevicePermissionStatus?> _safeStatus() async {
    try {
      return await DeviceDataBridge.status();
    } catch (_) {
      return null;
    }
  }

  Future<DevicePermissionStatus?> _statusNow() async {
    try {
      final s = await DeviceDataBridge.status();
      if (mounted) setState(() => _status = s);
      return s;
    } catch (_) {
      return _status;
    }
  }

  Future<void> _refreshStatus() async {
    final status = await _safeStatus();
    if (!mounted) return;
    setState(() => _status = status);
  }

  void _notify(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = msg;
      _messageIsError = error;
    });
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    if (!url.startsWith('http')) {
      _notify('地址要以 http:// 开头，例如 http://192.168.0.102:8787', error: true);
      return;
    }
    await DeviceHubClient.setBaseUrl(url);
    setState(() => _busy = true);
    try {
      final health = await DeviceHubClient.health(url: url);
      _notify('连接成功：hub ${health['version'] ?? ''}');
    } catch (e) {
      _notify('连不上 hub：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pair() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      _notify('请输入 6 位配对码', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final status = await _safeStatus();
      final name = status?.model.isNotEmpty == true ? status!.model : '我的手机';
      await DeviceHubClient.pair(code: code, deviceName: name);
      _codeController.clear();
      final paired = await DeviceHubClient.isPaired();
      if (mounted) setState(() => _paired = paired);
      _notify('配对成功，可以同步了');
    } catch (e) {
      _notify('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      final report = await DeviceHubClient.syncAll();
      final lastSync = await DeviceHubClient.lastSync();
      if (!mounted) return;
      setState(() {
        _lastSync = lastSync;
        _lastReport = report;
      });
      _notify('同步完成：$report');
      await _refreshStatus();
    } catch (e) {
      _notify('同步失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unpair() async {
    await DeviceHubClient.unpair();
    if (!mounted) return;
    setState(() {
      _paired = false;
      _lastSync = null;
      _lastReport = null;
    });
    _notify('已解除配对（服务器侧可再手动吊销）');
  }

  /// 短信读取自检
  ///
  /// 授权后点一下就能看到**真机上实际读到的条数与摘要**，用来确认
  /// 「权限 → 原生读取」这一段是通的，不必先绕一圈服务器。
  Future<void> _testSms() async {
    setState(() => _busy = true);
    try {
      final items = await DeviceDataBridge.sms(limit: 5);
      if (!mounted) return;
      final preview = items.isEmpty
          ? '没有读到短信。\n可能原因：收件箱为空、系统限制了短信读取，或权限被回收。'
          : items.map((e) {
              final t = DateTime.fromMillisecondsSinceEpoch(e.dateMs);
              final who = e.person.isNotEmpty ? e.person : e.address;
              final dir = e.isIncoming ? '收到' : '发出';
              final body = e.body.length > 48
                  ? '${e.body.substring(0, 48)}…'
                  : e.body;
              return '$dir · $who\n'
                  '${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}  $body';
            }).join('\n\n');
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('短信读取自检 · ${items.length} 条'),
          content: SingleChildScrollView(
            child: Text(
              preview,
              style: const TextStyle(fontSize: 13, height: 1.55),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      _notify('读取短信失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;

    return Scaffold(
      backgroundColor: qingPageBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('设备数据'),
        leading: Center(
          child: BackButton(onPressed: () => context.go('/rooms/settings')),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _sectionTitle(context, '连接我的服务器'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'device-hub 地址',
                helperText: '内网：http://192.168.0.102:8787',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  onPressed: _busy ? null : _saveUrl,
                  icon: const Icon(Icons.link),
                  tooltip: '保存并测试',
                ),
              ),
            ),
          ),
          if (!_paired)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: '配对码',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _busy ? null : _pair,
                    child: const Text('配对'),
                  ),
                ],
              ),
            )
          else
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('已配对'),
              subtitle: Text(_lastSync == null ? '尚未同步过' : '上次同步：$_lastSync'),
              trailing: TextButton(
                onPressed: _busy ? null : _unpair,
                child: const Text('解除'),
              ),
            ),
          const Divider(),

          _sectionTitle(context, '数据授权（逐项开启）'),
          _permissionTile(
            context,
            icon: Icons.notifications_active_outlined,
            title: '通知',
            subtitle: '读取微信、短信等所有通知（本地缓存最近 300 条）',
            granted: status?.notification ?? false,
            onTap: () => DeviceDataBridge.openNotificationSettings(),
          ),
          _permissionTile(
            context,
            icon: Icons.calendar_month_outlined,
            title: '日历',
            subtitle: '读取日程，用于安排会议、提醒',
            granted: status?.calendar ?? false,
            onTap: () async {
              await DeviceDataBridge.requestCalendarContacts();
              await _refreshStatus();
            },
          ),
          _permissionTile(
            context,
            icon: Icons.contact_phone_outlined,
            title: '通讯录',
            subtitle: '按姓名查电话（只读，可随时关闭）',
            granted: status?.contacts ?? false,
            onTap: () async {
              await DeviceDataBridge.requestCalendarContacts();
              await _refreshStatus();
            },
          ),
          _permissionTile(
            context,
            icon: Icons.sms_outlined,
            title: '短信',
            subtitle: (status?.sms ?? false)
                ? '可读取收件箱与已发送（只读，点一下做自检）'
                : '读取短信内容，供小爱查验证码、银行/快递通知（只读，不发送）',
            granted: status?.sms ?? false,
            onTap: () async {
              if (status?.sms == true) {
                await _testSms();
              } else {
                await DeviceDataBridge.requestSms();
                await _refreshStatus();
              }
            },
          ),
          _permissionTile(
            context,
            icon: Icons.bar_chart_outlined,
            title: '应用使用时长',
            subtitle: '统计各 App 使用时间（系统「使用情况访问」）',
            granted: status?.usage ?? false,
            onTap: () => DeviceDataBridge.openUsageSettings(),
          ),
          _permissionTile(
            context,
            icon: Icons.location_on_outlined,
            title: '定位',
            subtitle: '小爱需要「你在哪」时才读取最后已知位置',
            granted: status?.location ?? false,
            onTap: () async {
              await DeviceDataBridge.requestLocation();
              await _refreshStatus();
            },
          ),
          _permissionTile(
            context,
            icon: Icons.folder_outlined,
            title: '文件',
            subtitle: (status?.allFiles ?? false)
                ? '可列出完整路径（含下载/文档）；不读取文件内容'
                : '按需查文件名/大小。要给小爱完整路径，点一下开「所有文件访问」',
            granted: status?.files ?? false,
            onTap: () async {
              await DeviceDataBridge.requestFiles();
              await _refreshStatus();
              final now = await _statusNow();
              // 只给媒体权限时仍拿不到文档的真实路径，继续引导开「所有文件访问」
              if (now?.allFiles != true) {
                await DeviceDataBridge.openAllFilesAccess();
              }
            },
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${status.model} · Android ${status.androidVersion} · '
                '已授权 ${status.grantedCount}/${DevicePermissionStatus.totalCount}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const Divider(),

          _sectionTitle(context, '同步'),
          ListTile(
            leading: const Icon(Icons.bolt_outlined),
            title: const Text('测试取数（可选）'),
            subtitle: Text(
              _lastReport ?? '平时不需要同步：小爱要用数据时会自动向手机要。这里只是自检一次。',
            ),
            trailing: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.chevron_right),
            onTap: _busy ? null : _sync,
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                _message!,
                style: TextStyle(
                  color: _messageIsError ? theme.colorScheme.error : null,
                ),
              ),
            ),
          const Divider(),
          _sectionTitle(context, '启动诊断'),
          _bootTimingsTile(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Text(
              '数据只在你手机与自己的服务器之间传输。通知/短信内容可在 hub 侧按保留策略自动清理。',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      );

  Widget _permissionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required VoidCallback onTap,
  }) =>
      ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: granted
            ? const Icon(
                Icons.check_circle,
                color: Color(0xFF2E7D52),
              )
            : FilledButton.tonal(
                onPressed: onTap,
                child: const Text('去开启'),
              ),
        onTap: onTap,
      );

  /// 启动诊断：展示上次启动各阶段耗时
  ///
  /// 真机上核对「冷启动/热启动是否达标」就看这里，不用连电脑抓日志。
  Widget _bootTimingsTile(BuildContext context) {
    final timings = QingBoot.lastTimings();
    const labels = <String, String>{
      'config': '配置',
      'crypto': '加密引擎',
      'database': '数据库',
      'rooms': '会话',
      'applock': '应用锁',
      'total': '合计',
    };
    final parts = <String>[];
    for (final entry in labels.entries) {
      final ms = timings[entry.key];
      if (ms == null) continue;
      parts.add('${entry.value} ${_fmtMs(ms)}');
    }
    final ok = parts.isNotEmpty;
    final total = timings['total'];
    return ListTile(
      leading: Icon(
        Icons.speed_outlined,
        color: ok ? null : Theme.of(context).colorScheme.outline,
      ),
      title: const Text('上次启动耗时'),
      subtitle: Text(
        ok ? parts.join(' · ') : '还没有记录（本次是启动后的第一个会话）',
      ),
      trailing: total == null
          ? null
          : Text(
              _fmtMs(total),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: total < 0
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
      isThreeLine: ok,
    );
  }

  static String _fmtMs(int ms) {
    if (ms == -1) return '超时';
    if (ms == -2) return '异常';
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(1)}s';
    return '${ms}ms';
  }
}
