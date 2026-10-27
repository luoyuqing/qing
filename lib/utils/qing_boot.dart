// SPDX-FileCopyrightText: 2026 清助理
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 启动阶段
///
/// 每个阶段都有**独立超时**：超时只降级不阻塞，保证一定能进主界面。
enum QingBootPhase {
  idle('准备启动'),
  config('读取本地配置'),
  crypto('初始化加密引擎'),
  database('打开本地数据库'),
  rooms('加载会话数据'),
  ready('准备就绪'),
  failed('启动失败');

  const QingBootPhase(this.label);

  final String label;
}

@immutable
class QingBootState {
  const QingBootState({
    this.phase = QingBootPhase.idle,
    this.detail,
    this.error,
    this.timingsMs = const <String, int>{},
    this.phaseStartedAtMs,
    this.finished = false,
  });

  final QingBootPhase phase;

  /// 阶段附加说明（用于启动页第二行文案）
  final String? detail;

  final Object? error;

  /// 各阶段耗时（毫秒）。负数表示：-1 超时、-2 异常
  final Map<String, int> timingsMs;

  /// 当前阶段的开始时间（毫秒时间戳），用于显示「本阶段已用 X 秒」
  final int? phaseStartedAtMs;

  /// 是否已完成（成功或失败）
  final bool finished;

  bool get failed => phase == QingBootPhase.failed;

  QingBootState copyWith({
    QingBootPhase? phase,
    String? detail,
    Object? error,
    Map<String, int>? timingsMs,
    int? phaseStartedAtMs,
    bool? finished,
  }) => QingBootState(
    phase: phase ?? this.phase,
    detail: detail ?? this.detail,
    error: error ?? this.error,
    timingsMs: timingsMs ?? this.timingsMs,
    phaseStartedAtMs: phaseStartedAtMs ?? this.phaseStartedAtMs,
    finished: finished ?? this.finished,
  );
}

/// 清助理 · 启动流程编排
///
/// ## 为什么要有这个类
///
/// v1.8.0 之前 `main()` 是这样的顺序：
///
/// ```
/// AppSettings.init()        // 配置
/// vod.init()                // WASM 加密引擎
/// ClientManager.getClients()// 打开 SQLCipher 数据库 + 解锁加密账号
/// await roomsLoading        // 从库里把全部房间读进内存
/// await accountDataLoading
/// runApp()                  // ← 到这里才有第一帧
/// ```
///
/// 也就是**所有重活都在第一帧之前**完成。任何一个环节慢或卡住，用户看到
/// 的就是一直停在开机图（launch_background）——这就是"卡在开屏页面"。
///
/// 现在改成：先 `runApp` 渲染启动页，上面这条链在后台跑，每个阶段有超时，
/// 并把当前阶段文案显示出来。用户始终能看到"在做什么"。
class QingBoot {
  QingBoot._();

  static final ValueNotifier<QingBootState> state =
      ValueNotifier<QingBootState>(const QingBootState());

  static SharedPreferences? store;
  static List<Client> clients = const <Client>[];
  static String? pin;
  static bool useBiometrics = false;

  static bool _vodozemacInitialized = false;
  static bool _running = false;

  /// 从 main() 第一行开始计时，用于区分「引擎启动」与「我们自己的初始化」
  static final Stopwatch _sinceMain = Stopwatch();

  /// 在 main() 最开头调用
  static void markMainEntry() {
    if (!_sinceMain.isRunning) _sinceMain.start();
  }

  /// 首帧渲染完成后调用（runApp 之后 addPostFrameCallback）
  static void markFirstFrame() {
    final ms = _sinceMain.elapsedMilliseconds;
    _timings['first_frame'] = ms;
    Logs().i('[boot] 首帧 $ms ms');
    // run() 可能已经先落盘过一次，这里补写，保证「启动诊断」里能看到首帧耗时
    unawaited(_persistTimings());
  }

  static ({String? pincode, bool useBiometrics}) get appLockSettings =>
      (pincode: pin, useBiometrics: useBiometrics);

  /// 超时阈值
  ///
  /// 数据库给得最宽：升级首启可能要跑 SQLCipher 加密/迁移，慢设备上确实会久，
  /// 但再久也不能无限等——120s 之后让用户选择重试或清理本地库。
  static const _configTimeout = Duration(seconds: 15);
  static const _cryptoTimeout = Duration(seconds: 25);
  static const _databaseTimeout = Duration(seconds: 120);
  static const _roomsTimeout = Duration(seconds: 8);

  static Map<String, int> _timings = <String, int>{};

  /// 执行完整启动流程。调用前必须先 `runApp(QingBootGate())`。
  static Future<void> run() async {
    if (_running) return;
    _running = true;
    final total = Stopwatch()..start();
    _timings = <String, int>{};

    try {
      // ── 1. 本地配置 ───────────────────────────────────────
      _emit(QingBootPhase.config);
      final s = await _stage(
        'config',
        () => AppSettings.init(),
        _configTimeout,
      );
      if (s == null) {
        _fail('读取本地配置失败或超时');
        return;
      }
      store = s;
      kEnableMatrixSdkBenchmarks = AppSettings.benchmarksInLogs.value;
      Logs().i(
        'Welcome to ${AppSettings.applicationName.value} <3',
      );

      // ── 2. WASM 加密引擎 ──────────────────────────────────
      _emit(QingBootPhase.crypto);
      final cryptoOk = await _run(
        'crypto',
        () async {
          if (_vodozemacInitialized) return;
          await vod.init(
            wasmPath:
                './assets/assets/vodozemac/${AppConfig.vodozemacVersion}/',
          );
          _vodozemacInitialized = true;
        },
        _cryptoTimeout,
      );
      if (!cryptoOk) {
        // 加密引擎起不来时 matrix 会自动跳过加密（init 里有 isInitialized 判断），
        // 属于降级可用，不拦启动。
        Logs().w('[boot] vodozemac 未就绪，加密功能将不可用');
      }

      // ── 3. 数据库 + 客户端 ────────────────────────────────
      _emit(QingBootPhase.database);
      final list = await _stage(
        'database',
        () => ClientManager.getClients(store: store!),
        _databaseTimeout,
      );
      if (list == null) {
        _fail('打开本地数据库超时。\n可能是正在迁移旧版本数据，或设备存储较慢。');
        return;
      }
      clients = list;

      // ── 4. 预载会话（可降级）──────────────────────────────
      _emit(QingBootPhase.rooms);
      final first = clients.isEmpty ? null : clients.first;
      if (first != null) {
        await _run(
          'rooms',
          () async {
            await first.roomsLoading;
            await first.accountDataLoading;
          },
          _roomsTimeout,
        );
      }

      // ── 5. 应用锁 PIN ────────────────────────────────────
      await _run('applock', _loadAppLock, const Duration(seconds: 5));

      total.stop();
      // 合计 = 从 main() 入口算起（含引擎启动），更贴近"点图标到能用"的体感
      _timings['total'] = _sinceMain.elapsedMilliseconds > 0
          ? _sinceMain.elapsedMilliseconds
          : total.elapsedMilliseconds;
      await _persistTimings();

      state.value = QingBootState(
        phase: QingBootPhase.ready,
        detail: '${clients.length} 个账号 · '
            '${total.elapsedMilliseconds} ms',
        timingsMs: Map<String, int>.unmodifiable(_timings),
        finished: true,
      );
      Logs().i('[boot] ready in ${total.elapsedMilliseconds}ms $_timings');
    } catch (e, s) {
      Logs().wtf('[boot] 启动异常', e, s);
      _fail('$e');
    } finally {
      _running = false;
    }
  }

  /// 失败后重试（保留已有 store，跳过配置读取）
  static Future<void> retry() async {
    _running = false;
    state.value = const QingBootState();
    // 重试要重新计时，否则「合计」会把上一次的时间也算进去
    _sinceMain
      ..reset()
      ..start();
    await run();
  }

  /// 跳过剩余等待直接进入界面
  ///
  /// 不删除任何数据。clients 为空时会落到登录/引导页，用户可重新登录。
  static void skip() {
    Logs().w('[boot] 用户选择跳过等待，直接进入');
    state.value = QingBootState(
      phase: QingBootPhase.ready,
      detail: '已跳过等待',
      timingsMs: Map<String, int>.unmodifiable(_timings),
      finished: true,
    );
  }

  static Future<void> _loadAppLock() async {
    if (!PlatformInfos.supportsAppLock) return;
    try {
      pin = await const FlutterSecureStorage().read(
        key: 'chat.fluffy.app_lock',
      );
      useBiometrics =
          (await const FlutterSecureStorage().read(
            key: 'chat.fluffy.use_biometrics',
          )) ==
          'true';
    } catch (e, s) {
      Logs().d('Unable to read PIN from Secure storage', e, s);
    }
  }

  static void _emit(QingBootPhase phase, {String? detail}) {
    state.value = state.value.copyWith(
      phase: phase,
      detail: detail,
      phaseStartedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  static void _fail(String message) {
    state.value = QingBootState(
      phase: QingBootPhase.failed,
      error: message,
      detail: null,
      timingsMs: Map<String, int>.unmodifiable(_timings),
      finished: true,
    );
    Logs().e('[boot] 失败：$message  耗时=$_timings');
  }

  /// 有返回值的阶段：超时/异常返回 null
  static Future<T?> _stage<T>(
    String name,
    Future<T> Function() action,
    Duration timeout,
  ) async {
    final sw = Stopwatch()..start();
    try {
      final value = await action().timeout(timeout);
      _timings[name] = sw.elapsedMilliseconds;
      Logs().i('[boot] $name ${sw.elapsedMilliseconds}ms');
      return value;
    } on TimeoutException {
      _timings[name] = -1;
      Logs().w('[boot] $name 超时（${timeout.inSeconds}s）');
      return null;
    } catch (e, s) {
      _timings[name] = -2;
      Logs().w('[boot] $name 异常', e, s);
      return null;
    }
  }

  /// 无返回值的阶段：返回是否成功
  static Future<bool> _run(
    String name,
    Future<void> Function() action,
    Duration timeout,
  ) async {
    final sw = Stopwatch()..start();
    try {
      await action().timeout(timeout);
      _timings[name] = sw.elapsedMilliseconds;
      Logs().i('[boot] $name ${sw.elapsedMilliseconds}ms');
      return true;
    } on TimeoutException {
      _timings[name] = -1;
      Logs().w('[boot] $name 超时（${timeout.inSeconds}s）');
      return false;
    } catch (e, s) {
      _timings[name] = -2;
      Logs().w('[boot] $name 异常', e, s);
      return false;
    }
  }

  // ── 耗时持久化（供设置页展示，用于真机核对）────────────────

  static Future<void> _persistTimings() async {
    try {
      await store?.setString(
        AppSettings.qingBootTimings.key,
        jsonEncode(_timings),
      );
    } catch (_) {}
  }

  /// 读取上次启动耗时。返回空 Map 表示没有记录。
  static Map<String, int> lastTimings() {
    try {
      final raw = store?.getString(AppSettings.qingBootTimings.key);
      if (raw == null || raw.isEmpty) return const <String, int>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, int>{};
      return decoded.map(
        (k, v) => MapEntry(k.toString(), v is int ? v : 0),
      );
    } catch (_) {
      return const <String, int>{};
    }
  }
}
