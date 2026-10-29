import 'package:fluffychat/utils/device_hub/device_hub_client.dart';

/// Qing · 自动同步
///
/// 应用进入聊天列表时触发；距上次同步不足 30 分钟则跳过。
/// 失败静默（不打扰聊天），下次打开再试。
class DeviceHubAutoSync {
  static const interval = Duration(minutes: 30);
  static bool _running = false;

  static Future<void> maybeSync() async {
    if (_running) return;
    _running = true;
    try {
      if (!await DeviceHubClient.isPaired()) return;
      final last = await DeviceHubClient.lastSyncAt();
      if (last != null && DateTime.now().difference(last) < interval) return;
      await DeviceHubClient.syncAll(includeContacts: last == null);
    } catch (_) {
      // 静默失败：网络不可用 / hub 未启动 / 权限未开都不该影响聊天
    } finally {
      _running = false;
    }
  }
}
