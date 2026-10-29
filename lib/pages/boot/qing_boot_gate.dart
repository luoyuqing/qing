// SPDX-FileCopyrightText: 2026 Qing
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/qing_boot.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:material_ui/material_ui.dart';

/// 启动门
///
/// 全 App 唯一的 `runApp` 入口。先渲染启动页拿到首帧，等 [QingBoot]
/// 把重活干完再切到真正的 [FluffyChatApp]。
///
/// 启动页**与原生启动图完全一致**（同色底 + 居中同尺寸头像），不放进度条、
/// 不放转圈、不放任何阶段耗时数字 —— 它只负责顶住等待，不表演加载。
/// 排障信息只出现在启动失败页。
class QingBootGate extends StatelessWidget {
  const QingBootGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<QingBootState>(
      valueListenable: QingBoot.state,
      builder: (context, state, _) {
        if (!state.finished) {
          return const _QingBootSplash();
        }
        if (state.failed) {
          return _QingBootFailed(state: state);
        }
        final store = QingBoot.store;
        if (store == null) {
          // 理论上不会走到这里（store 为空时一定先 fail），兜底避免崩溃
          return _QingBootFailed(
            state: state.copyWith(
              phase: QingBootPhase.failed,
              error: '本地配置未就绪',
            ),
          );
        }
        return FluffyChatApp(
          clients: QingBoot.clients,
          appLockSettings: QingBoot.appLockSettings,
          store: store,
        );
      },
    );
  }
}

const _bgTop = Color(0xFFF7FAFF);
const _ink = Color(0xFF1B2532);
const _inkSoft = Color(0xFF6B7A8C);
const _inkFaint = Color(0xFFA7B3C2);
const _accent = Color(0xFF5B87C4);

/// 阶段名称：**只用于启动失败页**的耗时明细，正常启动不展示任何阶段信息。
const _stageLabels = <String, String>{
  'first_frame': '首帧',
  'config': '读取配置',
  'crypto': '加密引擎',
  'database': '本地数据库',
  'rooms': '会话数据',
  'applock': '应用锁',
  'total': '合计',
};

String _fmtMs(int ms) {
  if (ms == -1) return '超时';
  if (ms == -2) return '异常';
  if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(1)}s';
  return '${ms}ms';
}

/// 启动页：与原生启动图完全一致（同色底 + 居中同尺寸品牌头像）
///
/// 设计约束（2026-10-27）：**不展示任何诊断信息**。
/// 这里原本有一张「读取配置 / 加密引擎 / 本地数据库 / 会话数据」四阶段耗时
/// 清单，属于排障界面，正常用户在启动页和主页之间会看到它一闪而过。
/// 现在改成照抄原生启动图的构图（177dp 居中头像，与
/// res/drawable-*/splash.png 的 177dp 一致），系统启动图交接到 Flutter 时
/// 在视觉上是连续的，用户只会感觉「图标 → 主页」。
/// 阶段耗时只在 [QingBootFailed] 里出现。
class _QingBootSplash extends StatefulWidget {
  const _QingBootSplash();

  @override
  State<_QingBootSplash> createState() => _QingBootSplashState();
}

class _QingBootSplashState extends State<_QingBootSplash> {
  bool _showSkip = false;
  Timer? _skipTimer;

  /// 卡这么久还没进主界面，才给一个出口。正常启动（<1s）根本看不到。
  static const _skipAfter = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _skipTimer = Timer(_skipAfter, () {
      if (mounted) setState(() => _showSkip = true);
    });
  }

  @override
  void dispose() {
    _skipTimer?.cancel();
    super.dispose();
  }

  /// 打开启动诊断：当前阶段 + 本阶段已用时长 + 各阶段耗时。
  /// 只由「长按头像」或「慢启动 → 诊断」触发，正常启动不会出现。
  void _openDiag(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _BootDiagSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 跟随系统深浅色：原生启动图夜间是黑底，这里保持一致
    final dark =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: dark ? Colors.black : Colors.white,
        body: Stack(
          children: [
            Center(
              // 长按头像 = 打开启动诊断。平时完全不可见：
              // 正常启动（<1s）用户根本来不及长按，也不会看到任何诊断信息。
              child: GestureDetector(
                onLongPress: () => _openDiag(context),
                child: SizedBox(
                  width: 177,
                  height: 177,
                  child: Image.asset(
                    'assets/qing_splash.png',
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
            // 6 秒后才出现的兜底出口（静置，不是加载动画）
            if (_showSkip)
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => QingBoot.skip(),
                      child: Text(
                        '启动较慢，点这里直接进入',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: dark ? const Color(0xFF8FB4E0) : _accent,
                        ),
                      ),
                    ),
                    Text(
                      '·',
                      style: TextStyle(
                        color: dark ? const Color(0xFF8FB4E0) : _accent,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _openDiag(context),
                      child: Text(
                        '诊断',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: dark ? const Color(0xFF8FB4E0) : _accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 启动诊断面板
///
/// 只在「长按启动页头像」或「慢启动 → 诊断」时出现，正常启动永远看不到。
/// 展示当前阶段、本阶段已用时长、各阶段耗时（-1 超时 / -2 异常），
/// 截图即可定位卡在哪一步。每秒自刷新，卡住的阶段能看到数字在走。
class _BootDiagSheet extends StatefulWidget {
  const _BootDiagSheet();

  @override
  State<_BootDiagSheet> createState() => _BootDiagSheetState();
}

class _BootDiagSheetState extends State<_BootDiagSheet> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Widget _row(String label, String value, {Color? valueColor}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, color: _inkSoft)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: valueColor ?? _ink,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<QingBootState>(
      valueListenable: QingBoot.state,
      builder: (context, state, _) {
        final started = state.phaseStartedAtMs;
        final elapsedMs = started == null
            ? 0
            : DateTime.now().millisecondsSinceEpoch - started;
        final rows = state.timingsMs.entries.toList();

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDDE3EA),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '启动诊断',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _row('当前阶段', state.phase.label),
                  if (started != null)
                    _row('本阶段已用', '${(elapsedMs / 1000).toStringAsFixed(1)}s'),
                  if (state.error != null)
                    _row('错误', '${state.error}', valueColor: const Color(0xFFB08892)),
                  if (rows.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      '各阶段耗时',
                      style: TextStyle(fontSize: 12.5, color: _inkSoft),
                    ),
                    const SizedBox(height: 4),
                    for (final e in rows)
                      _row(_stageLabels[e.key] ?? e.key, _fmtMs(e.value)),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => QingBoot.skip(),
                      child: const Text('跳过等待，直接进入'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '截图这一页发给开发者，就能定位卡在哪一阶段。',
                    style: TextStyle(fontSize: 11, color: _inkFaint),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 启动失败页：给出可操作的出口，而不是一直转圈
class _QingBootFailed extends StatelessWidget {
  const _QingBootFailed({required this.state});

  final QingBootState state;

  @override
  Widget build(BuildContext context) {
    final timings = state.timingsMs;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: _bgTop,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 44,
                  color: Color(0xFFB08892),
                ),
                const SizedBox(height: 16),
                const Text(
                  '启动没有完成',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${state.error ?? '未知原因'}',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: _inkSoft,
                  ),
                ),
                const SizedBox(height: 20),
                if (timings.isNotEmpty)
                  _TimingsBox(timings: timings)
                else
                  const SizedBox.shrink(),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: () => QingBoot.retry(),
                    child: const Text('重试'),
                  ),
                ),
                const SizedBox(height: 10),
                // store 没读到时无法构建真实界面，此时不提供"跳过"
                if (QingBoot.store != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: () => QingBoot.skip(),
                      child: const Text('跳过等待，直接进入'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    '「跳过等待」不会删除任何数据，只是先进入界面（历史会话可能稍后才会出现）。',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: _inkFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimingsBox extends StatelessWidget {
  const _TimingsBox({required this.timings});

  final Map<String, int> timings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '本次启动各阶段耗时',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
          const SizedBox(height: 8),
          for (final entry in timings.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _stageLabels[entry.key] ?? entry.key,
                    style: const TextStyle(fontSize: 12, color: _inkSoft),
                  ),
                  Text(
                    _fmtMs(entry.value),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: entry.value < 0 ? const Color(0xFFB08892) : _ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
