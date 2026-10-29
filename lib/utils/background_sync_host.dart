// SPDX-FileCopyrightText: 2026 Qingliao contributors
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';

/// Android 原生「后台消息同步」前台服务（dataSync）的桥。
///
/// Qing不依赖 Firebase / ntfy：Dart 侧用 `/sync` 长轮询收消息，原生服务只
/// 负责让进程活着、被系统杀掉后自愈、开机自启。
class BackgroundSyncHost {
  static const MethodChannel _channel = MethodChannel(
    'chat.qingliao/background_sync',
  );

  static Future<void> start() async {
    if (!PlatformInfos.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('start');
    } catch (e, s) {
      Logs().w('[Push] Unable to start native background sync service', e, s);
    }
  }

  static Future<void> stop() async {
    if (!PlatformInfos.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (e, s) {
      Logs().w('[Push] Unable to stop native background sync service', e, s);
    }
  }

  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!PlatformInfos.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>(
            'isIgnoringBatteryOptimizations',
          ) ??
          false;
    } catch (e, s) {
      Logs().w('[Push] Unable to query battery optimization state', e, s);
      return false;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!PlatformInfos.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>(
            'requestIgnoreBatteryOptimizations',
          ) ??
          false;
    } catch (e, s) {
      Logs().w('[Push] Unable to request battery optimization exemption', e, s);
      return false;
    }
  }

  static Future<bool> openAutostartSettings() async {
    if (!PlatformInfos.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openAutostartSettings') ?? false;
    } catch (e, s) {
      Logs().w('[Push] Unable to open OEM autostart settings', e, s);
      return false;
    }
  }
}
