// SPDX-FileCopyrightText: 2026 Qingliao contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/utils/background_sync_host.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Qing的「纯客户端推送」控制器。
///
/// 方案：不注册 FCM / ntfy 之类服务器推送，而是
///  - Matrix SDK 的 `/sync` 长轮询常驻（backgroundSync 保持 true）
///  - Android 前台服务（dataSync）保住进程 + 2 分钟 watchdog + 开机自启
///  - 新消息由 `Client.onNotification` → 本地通知
class LocalSyncService {
  static const _askedBatteryOptimizationKey =
      'chat.qingliao.asked_battery_optimization';

  static bool _started = false;

  /// App 启动 / 登录后调用：把后台同步服务拉起来。
  static Future<void> ensureRunning(List<Client> clients) async {
    if (!PlatformInfos.isAndroid) return;
    final loggedIn = clients.where((c) => c.isLogged()).toList();
    if (loggedIn.isEmpty) {
      await stop();
      return;
    }
    await _requestNotificationPermission();
    await BackgroundSyncHost.start();
    _started = true;
    unawaited(_maybeAskBatteryOptimization());
  }

  static Future<void> stop() async {
    if (!PlatformInfos.isAndroid) return;
    _started = false;
    await BackgroundSyncHost.stop();
  }

  static Future<void> _requestNotificationPermission() async {
    try {
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (e, s) {
      Logs().w('[Push] Unable to request notification permission', e, s);
    }
  }

  /// 只在前台（有界面）时弹一次「忽略电池优化」，避免国产 ROM 杀后台。
  static Future<void> _maybeAskBatteryOptimization() async {
    if (!PlatformInfos.isAndroid || _started == false) return;
    try {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      final store = await SharedPreferences.getInstance();
      if (store.getBool(_askedBatteryOptimizationKey) == true) return;
      if (await BackgroundSyncHost.isIgnoringBatteryOptimizations()) {
        await store.setBool(_askedBatteryOptimizationKey, true);
        return;
      }
      await store.setBool(_askedBatteryOptimizationKey, true);
      await BackgroundSyncHost.requestIgnoreBatteryOptimizations();
    } catch (e, s) {
      Logs().w('[Push] Battery-optimization prompt failed', e, s);
    }
  }
}
