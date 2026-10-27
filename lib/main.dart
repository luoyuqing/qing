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
  // 启动计时起点：这里的耗时包含引擎初始化，是用户"点图标到看见画面"的真实时间
  QingBoot.markMainEntry();

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

  // 判定依据打进日志：真机 logcat 里就能核对这次到底是"后台引擎"还是误判
  final lifecycle = WidgetsBinding.instance.lifecycleState;
  final viewCount = WidgetsBinding.instance.platformDispatcher.views.length;
  final backgroundMode =
      PlatformInfos.isAndroid && AppLifecycleState.detached == lifecycle;

  // ── 清助理 v1.9.6 关键修复：不再用 detached 决定「要不要画界面」 ──
  //
  // Android 上（尤其装完包第一次启动）Activity 还没 attach 时，
  // lifecycleState 会先报 detached。旧逻辑据此判定"后台引擎"→ 不调 runApp
  // → 屏幕停在系统启动图，等系统补一个 resumed 事件才渲染（1~2 秒起，
  // 冷启动更久），表现就是"卡开屏"；更糟的是旧逻辑把 addObserver 放在
  // `await QingBoot.run()` 之后，冷启动时 resume 事件早已过去，observer
  // 永远收不到，就会一直白屏。
  //
  // 现在无条件先 runApp：真有窗口就立刻可见；真正的后台引擎没有窗口，
  // 建好的树不会被光栅化，代价可忽略。
  runApp(const QingBootGate());
  _initialGuiRendered = true;

  // 首帧一出来就打点，用于区分「引擎慢」还是「初始化慢」
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => QingBoot.markFirstFrame(),
  );

  // 清助理：长轮询要尽早起来，AI 随时可能来要数据。
  // 只依赖 SharedPreferences，不依赖 Matrix 初始化。
  DeviceHubPoller.start();

  Logs().i(
    '[boot] lifecycle=$lifecycle views=$viewCount backgroundMode=$backgroundMode',
  );

  if (backgroundMode) {
    // 后台引擎（开机自启 / 前台服务拉起）：初始化照常走，另外把常驻同步架起来
    await QingBoot.run();

    // Qchat：纯客户端方案没有服务器推送器（FCM/UnifiedPush 都不用），
    // /sync 长轮询本身就是推送。detached 引擎必须保持持续同步，不能像上游
    // FCM 方案那样停掉 sync 干等推送 —— 否则服务活着但永远收不到消息。
    for (final client in QingBoot.clients) {
      client.backgroundSync = true;
      client.syncPresence = PresenceType.offline;
    }

    // BackgroundPush 构造函数里会初始化本地通知插件；
    // 无 GUI 引擎没有 MatrixState，通知订阅由 headless 模块独立完成。
    BackgroundPush.clientOnly(QingBoot.clients);
    startHeadlessNotificationSync(QingBoot.clients);

    // 这个引擎之后可能被 MainActivity 复用，所以仍要监听 resume；
    // 但界面已经画过了，AppStarter 里不会再 runApp 一次。
    WidgetsBinding.instance.addObserver(AppStarter());
    Logs().i(
      '${AppSettings.applicationName.value} started in background-fetch mode. '
      'GUI tree is prepared; it becomes visible when an activity attaches.',
    );
    return;
  }

  await QingBoot.run();

  Logs().i('[boot] 启动流程结束，阶段=${QingBoot.state.value.phase.name}');
}, ErrorReporter.onFlutterError);

/// 启动页是否已经 runApp 过（后台模式也会先画，避免误判时白屏）
bool _initialGuiRendered = false;

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
    // 已经在 main() 里 runApp 过就别再建一次树（后台引擎被 Activity 复用时
    // 那棵树会直接显示出来）
    if (!_initialGuiRendered) {
      runApp(const QingBootGate());
      _initialGuiRendered = true;
    }
    // We must make sure that the GUI is only started once.
    guiStarted = true;
  }
}
