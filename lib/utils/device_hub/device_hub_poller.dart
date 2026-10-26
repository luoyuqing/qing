import 'dart:async';
import 'dart:math';

import 'package:fluffychat/utils/device_hub/device_data_bridge.dart';
import 'package:fluffychat/utils/device_hub/device_hub_client.dart';

/// 清助理 · 按需取数应答器
///
/// 架构：**AI 需要数据时才向手机要**（不是手机主动上传）。
/// 手机在前台/后台存活期间长轮询 `/device/poll`，收到命令后现场读取并回传。
/// 读完的数据由 hub 决定是否缓存，手机会话里不做任何主动上报。
class DeviceHubPoller {
  static bool _running = false;
  static bool _started = false;

  static void start() {
    if (_started) return;
    _started = true;
    unawaited(_loop());
  }

  static Future<void> _loop() async {
    if (_running) return;
    _running = true;
    while (true) {
      try {
        if (!await DeviceHubClient.isPaired()) {
          await Future<void>.delayed(const Duration(seconds: 15));
          continue;
        }
        final cmd = await DeviceHubClient.pollDevice(waitSeconds: 20);
        if (cmd == null) continue;
        await _handle(cmd);
      } catch (_) {
        // 网络抖动 / hub 重启：退避后继续
        await Future<void>.delayed(Duration(seconds: 3 + Random().nextInt(5)));
      }
    }
  }

  static Future<void> _handle(Map<String, dynamic> cmd) async {
    final id = '${cmd['id'] ?? ''}';
    final kind = '${cmd['kind'] ?? ''}';
    final params = (cmd['params'] as Map?) ?? const {};
    if (id.isEmpty) return;
    try {
      switch (kind) {
        case 'notifications':
          final items = await DeviceDataBridge.notifications(
            limit: (params['limit'] as num?)?.toInt() ?? 50,
          );
          await DeviceHubClient.respondDevice(id,
              ok: true, data: {'items': items.map((e) => e.toJson()).toList()});
          break;
        case 'calendar':
          final now = DateTime.now();
          final items = await DeviceDataBridge.calendar(
            fromMs: (params['fromMs'] as num?)?.toInt() ??
                now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
            toMs: (params['toMs'] as num?)?.toInt() ??
                now.add(const Duration(days: 30)).millisecondsSinceEpoch,
          );
          await DeviceHubClient.respondDevice(id, ok: true, data: {'items': items});
          break;
        case 'contacts':
          final items = await DeviceDataBridge.contacts(
            limit: (params['limit'] as num?)?.toInt() ?? 500,
          );
          await DeviceHubClient.respondDevice(id, ok: true, data: {'items': items});
          break;
        case 'usage':
          final now = DateTime.now();
          final dayStart = DateTime(now.year, now.month, now.day);
          final items = await DeviceDataBridge.usage(
            fromMs: (params['fromMs'] as num?)?.toInt() ?? dayStart.millisecondsSinceEpoch,
            toMs: (params['toMs'] as num?)?.toInt() ?? now.millisecondsSinceEpoch,
          );
          await DeviceHubClient.respondDevice(id, ok: true, data: {'items': items});
          break;
        case 'location':
          final loc = await DeviceDataBridge.location();
          if (loc['error'] != null) {
            await DeviceHubClient.respondDevice(id, ok: false, error: '${loc['error']}');
          } else {
            await DeviceHubClient.respondDevice(id, ok: true, data: loc);
          }
          break;
        case 'files':
          final items = await DeviceDataBridge.files(
            limit: (params['limit'] as num?)?.toInt() ?? 30,
            query: '${params['query'] ?? ''}',
          );
          await DeviceHubClient.respondDevice(id, ok: true, data: {'items': items});
          break;
        default:
          await DeviceHubClient.respondDevice(id, ok: false, error: '不支持的类型 $kind');
      }
    } catch (e) {
      await DeviceHubClient.respondDevice(id, ok: false, error: '$e');
    }
  }
}
