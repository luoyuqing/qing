// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/pages/boot/qing_boot_gate.dart';
import 'package:fluffychat/utils/background_push.dart';
import 'package:fluffychat/utils/device_hub/device_hub_poller.dart';
import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/headless_notifications.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/qing_boot.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:universal_html/universal_html.dart' as web;

import 'config/setting_keys.dart';

ReceivePort? mainIsolateReceivePort;

bool isIntegrationTest = false;

/// 清助理启动流程（v1.9.0 重构）
///
/// ## 改动要点
///
/// 旧流程把「配置 → 加密引擎 → 打开 SQLCipher 数据库 → 解锁加密账号 →
/// 读全部房间进内存」全部放在 `runApp()` **之前**，所以这段时间用户只能
/// 看着静态开机图。升级安装后若触发数据库加密/迁移或删库重建，这段时间
/// 会拉长到几十秒甚至更久 —— 表现就是"卡在开屏页面"。
///
/// 新流程：
/// 1. `runApp(QingBootGate())` 立刻拿到首帧，显示品牌启动页 + 当前阶段；
/// 2. 上面那串重活交给 [QingBoot] 在后台跑，**每个阶段独立超时**；
/// 3. 全部就绪后由启动门切换到真正的 [FluffyChatApp]。
///
/// 无论哪一步慢，用户都能看见"正在做什么"，且不会无限等待。
void main(List<String> args) => runZonedGuarded(() async {
  // Forward Flutter errors to global error reporter
  FlutterError.onError = (details) => Zone.current.handleUncaughtError(
    details.exception,
    details.stack ?? StackTrace.current,
  );

  isIntegrationTest = args.singleOrNull == 'integration_test';
  if (PlatformInfos.isAndroid) {
    final port = mainIsolateReceivePort = ReceivePort();
    IsolateNameServer.removePortNameMapping(AppConfig.mainIsolatePortName);
    IsolateNameServer.registerPortWithName(
      port.sendPort,
      AppConfig.mainIsolatePortName,
    );
    await waitForPushIsolateDone();
  }

  // Sanitize hash for OIDC:
  if (kIsWeb) {
    final hash = web.window.location.hash;
    if (hash.isNotEmpty && !hash.startsWith('/')) {
      web.window.location.hash = hash.replaceFirst('#', '#?');
    }
  }

  // Our background push shared isolate accesses flutter-internal things very early in the startup proccess
  // To make sure that the parts of flutter needed are started up already, we need to ensure that the
  // widget bindings are initialized already.
  WidgetsFlutterBinding.ensureInitialized();

  Logs().nativeColors = !PlatformInfos.isIOS;

  if (PlatformInfos.isLinux || PlatformInfos.isWindows) {
    JustAudioMediaKit.ensureInitialized();
  }

  // If the app starts in detached mode, we assume that it is in
  // background fetch mode for processing push notifications. This is
  // currently only supported on Android.
  final backgroundMode =
      PlatformInfos.isAndroid &&
      AppLifecycleState.detached == WidgetsBinding.instance.lifecycleState;

  if (backgroundMode) {
    // 后台引擎没有 UI，不需要启动页；初始化照常走（同样带超时）
    await QingBoot.run();

    // 清助理：后台引擎也启动按需取数应答器（AI 随时可能来要数据）
    DeviceHubPoller.start();

    // Qchat：纯客户端方案没有服务器推送器（FCM/UnifiedPush 都不用），
    // /sync 长轮询本身就是推送。detached 引擎（开机自启 / 进程被杀后由
    // 前台服务拉起）必须保持持续同步，不能像上游 FCM 方案那样停掉
    // sync 干等推送 —— 否则服务活着但永远收不到消息。
    for (final client in QingBoot.clients) {
      client.backgroundSync = true;
      client.syncPresence = PresenceType.offline;
    }

    // BackgroundPush 构造函数里会初始化本地通知插件；
    // 无 GUI 引擎没有 MatrixState，通知订阅由 headless 模块独立完成。
    BackgroundPush.clientOnly(QingBoot.clients);
    startHeadlessNotificationSync(QingBoot.clients);

    // To start the flutter engine afterwards we add an custom observer.
    WidgetsBinding.instance.addObserver(AppStarter());
    Logs().i(
      '${AppSettings.applicationName.value} started in background-fetch mode. No GUI will be created unless the app is no longer detached.',
    );
    return;
  }

  // 前台：先出画面，再干活
  runApp(const QingBootGate());

  // 清助理：前台启动即开始长轮询，AI 需要数据时现场读取。
  // 放在 run() 之前：它内部只依赖 SharedPreferences，不依赖 Matrix 初始化，
  // 早点起来可以让「AI 来要数据」更早得到响应。
  DeviceHubPoller.start();

  await QingBoot.run();

  Logs().i('[boot] 启动流程结束，阶段=${QingBoot.state.value.phase.name}');
}, ErrorReporter.onFlutterError);

/// Watches the lifecycle changes to start the application when it
/// is no longer detached.
class AppStarter with WidgetsBindingObserver {
  AppStarter();

  bool guiStarted = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (guiStarted) return;
    if (state == AppLifecycleState.detached) return;

    Logs().i(
      '${AppSettings.applicationName.value} switches from the detached background-fetch mode to ${state.name} mode. Rendering GUI...',
    );
    // Switching to foreground mode needs to reenable send online sync presence.
    for (final client in QingBoot.clients) {
      client.backgroundSync = true;
      client.syncPresence = PresenceType.online;
    }
    // GUI 起来后 MatrixState 接管通知（带前台抑制），headless 订阅撤掉防重复。
    cancelHeadlessNotificationSync();
    runApp(const QingBootGate());
    // We must make sure that the GUI is only started once.
    guiStarted = true;
  }
}
