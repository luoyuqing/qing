// SPDX-FileCopyrightText: 2026 清助理
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/qing_boot.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:material_ui/material_ui.dart';

/// 启动门
///
/// 全 App 唯一的 `runApp` 入口。先渲染启动页拿到首帧，等 [QingBoot]
/// 把重活干完再切到真正的 [FluffyChatApp]。
///
/// 这样做的直接收益：用户点开图标后几百毫秒内就能看到画面和阶段进度，
/// 不再是对着一张静态开机图干等（甚至等到以为卡死）。
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
const _accent = Color(0xFF5B87C4);

/// 启动页（轻量，不依赖任何主题/存储）
class _QingBootSplash extends StatelessWidget {
  const _QingBootSplash({required this.state});

  final QingBootState state;

  @override
  Widget build(BuildContext context) {
    // 启动页可能在 AppSettings.init() 之前就渲染，此时不能读 store，
    // 用与应用名一致的常量兜底，避免首帧刷一堆 "Unable to fetch" 错误日志。
    final appName =
        QingBoot.store == null ? '清助理' : AppSettings.applicationName.value;
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
                // 图标
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_accent, Color(0xFF8FB4E0)],
                    ),
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withAlpha(60),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '清',
                    style: TextStyle(
                      fontSize: 40,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  appName,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  state.detail ?? '正在启动',
                  style: const TextStyle(fontSize: 12.5, color: _inkSoft),
                ),
                const Spacer(flex: 2),
                SizedBox(
                  width: 132,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: const LinearProgressIndicator(
                      minHeight: 3,
                      backgroundColor: Color(0xFFDCE6F2),
                      valueColor: AlwaysStoppedAnimation<Color>(_accent),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  state.phase.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _inkSoft,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(flex: 3),
                const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: Text(
                    '数据只存在你自己的设备与服务器上',
                    style: TextStyle(fontSize: 11, color: Color(0xFF97A5B6)),
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
                if (timings.isNotEmpty) _TimingsBox(timings: timings),
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
                      color: Color(0xFF97A5B6),
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

  static const _labels = <String, String>{
    'config': '读取配置',
    'crypto': '加密引擎',
    'database': '打开数据库',
    'rooms': '加载会话',
    'applock': '应用锁',
    'total': '合计',
  };

  String _fmt(int ms) {
    if (ms == -1) return '超时';
    if (ms == -2) return '异常';
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(1)} s';
    return '$ms ms';
  }

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
                    _labels[entry.key] ?? entry.key,
                    style: const TextStyle(fontSize: 12, color: _inkSoft),
                  ),
                  Text(
                    _fmt(entry.value),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: entry.value < 0
                          ? const Color(0xFFB08892)
                          : _ink,
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
