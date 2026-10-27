// SPDX-FileCopyrightText: 2026 清助理
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/qing_boot.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:material_ui/material_ui.dart';

/// 启动门
///
/// 全 App 唯一的 `runApp` 入口。先渲染启动页拿到首帧，等 [QingBoot]
/// 把重活干完再切到真正的 [FluffyChatApp]。
///
/// 启动页**刻意做成静止的**：不放进度条、不放转圈，只有文字与耗时数字。
/// 之前那版放了 LinearProgressIndicator，被反馈"多了个进度条动画，体验差"，
/// 已去掉 —— 启动页的存在目的是"让你知道没死机"，不是"表演加载中"。
class QingBootGate extends StatelessWidget {
  const QingBootGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<QingBootState>(
      valueListenable: QingBoot.state,
      builder: (context, state, _) {
        if (!state.finished) {
          return _QingBootSplash(state: state);
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
const _bgBottom = Color(0xFFEAF1FA);
const _ink = Color(0xFF1B2532);
const _inkSoft = Color(0xFF6B7A8C);
const _inkFaint = Color(0xFFA7B3C2);
const _accent = Color(0xFF5B87C4);

/// 阶段在界面上固定展示的顺序（与耗时 key 对应）
const _stageKeys = <String>['config', 'crypto', 'database', 'rooms'];
const _stageLabels = <String, String>{
  'first_frame': '首帧',
  'config': '读取配置',
  'crypto': '加密引擎',
  'database': '本地数据库',
  'rooms': '会话数据',
  'applock': '应用锁',
  'total': '合计',
};

/// 当前阶段对应到哪个展示项（null 表示不在上面四项里）
String? _currentStageKey(QingBootPhase phase) => switch (phase) {
  QingBootPhase.config => 'config',
  QingBootPhase.crypto => 'crypto',
  QingBootPhase.database => 'database',
  QingBootPhase.rooms => 'rooms',
  _ => null,
};

String _fmtMs(int ms) {
  if (ms == -1) return '超时';
  if (ms == -2) return '异常';
  if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(1)}s';
  return '${ms}ms';
}

/// 启动页（静止，不依赖任何主题/存储）
class _QingBootSplash extends StatefulWidget {
  const _QingBootSplash({required this.state});

  final QingBootState state;

  @override
  State<_QingBootSplash> createState() => _QingBootSplashState();
}

class _QingBootSplashState extends State<_QingBootSplash> {
  Timer? _ticker;

  /// 显示「跳过等待」的门槛：超过这个时长还没进主界面，就给用户一个出口
  static const _skipAfter = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    // 每秒刷新一次：只为了让「本阶段 X.Xs」这个数字走字，
    // 让人知道程序还活着。这不是加载动画。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _elapsedText() {
    final started = widget.state.phaseStartedAtMs;
    if (started == null) return '';
    final ms = DateTime.now().millisecondsSinceEpoch - started;
    if (ms < 1000) return '';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }

  bool get _showSkip {
    final started = widget.state.phaseStartedAtMs;
    if (started == null) return false;
    return DateTime.now().millisecondsSinceEpoch - started >
        _skipAfter.inMilliseconds;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    // 启动页可能在 AppSettings.init() 之前就渲染，此时不能读 store，
    // 用与应用名一致的常量兜底，避免首帧刷一堆 "Unable to fetch" 错误日志。
    final appName =
        QingBoot.store == null ? '清助理' : AppSettings.applicationName.value;
    final currentKey = _currentStageKey(state.phase);
    final elapsed = _elapsedText();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [_bgTop, _bgBottom],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_accent, Color(0xFF8FB4E0)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withAlpha(46),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '清',
                    style: TextStyle(
                      fontSize: 36,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  appName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                // 当前在做什么 + 本阶段已用多久（唯一会变的东西）
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.phase.label,
                      style: const TextStyle(fontSize: 12.5, color: _inkSoft),
                    ),
                    if (elapsed.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        elapsed,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: _inkFaint,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
                const Spacer(flex: 2),
                // 四阶段固定清单：已完成的显示耗时，当前项高亮，未开始灰显。
                // 位置固定不跳动，卡在哪一步一眼能看出来。
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 46),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final key in _stageKeys)
                        _StageRow(
                          label: _stageLabels[key]!,
                          ms: state.timingsMs[key],
                          isCurrent: key == currentKey,
                        ),
                    ],
                  ),
                ),
                const Spacer(flex: 3),
                // 超过 6 秒仍未完成 → 给出口，不等超时
                if (_showSkip)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextButton(
                      onPressed: () => QingBoot.skip(),
                      child: const Text(
                        '启动较慢，点这里直接进入',
                        style: TextStyle(fontSize: 12.5, color: _accent),
                      ),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    '数据只存在你自己的设备与服务器上',
                    style: TextStyle(fontSize: 11, color: _inkFaint),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一行阶段状态：✓ 已完成 / · 进行中 / 灰 未开始
class _StageRow extends StatelessWidget {
  const _StageRow({
    required this.label,
    required this.ms,
    required this.isCurrent,
  });

  final String label;

  /// null = 未开始；-1 = 超时；-2 = 异常；其它 = 毫秒
  final int? ms;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final done = ms != null && ms! >= 0;
    final failed = ms != null && ms! < 0;
    final color = done
        ? _inkSoft
        : failed
        ? const Color(0xFFB08892)
        : isCurrent
        ? _ink
        : _inkFaint;
    final marker = done
        ? '✓'
        : failed
        ? '!'
        : isCurrent
        ? '·'
        : ' ';
    final trailing = done
        ? _fmtMs(ms!)
        : failed
        ? _fmtMs(ms!)
        : isCurrent
        ? '进行中'
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: Text(
              marker,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: isCurrent ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
          const Spacer(),
          Text(
            trailing,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
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
