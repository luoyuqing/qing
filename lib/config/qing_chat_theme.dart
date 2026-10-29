// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/widgets/theme_builder.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Qing · 聊天气泡专属配色
///
/// ## 与全局主题色的关系（重要）
///
/// v1.8.0 起，两套配色**完全独立**：
///
/// | 范围 | 由谁控制 | 存储位置 | 默认值 |
/// |---|---|---|---|
/// | 全站主色（简报/任务/记忆/设置/会话列表…） | 全局种子色，**v1.7.1 原机制不动** | `chat.fluffy.color_scheme_seed` | 保持 v1.7.1 |
/// | **聊天气泡底色** | 本文件的聊天主题色 | `chat.fluffy.chat_accent` | 晴空蓝 `#5B87C4` |
///
/// 用户明确要求「除聊天界面外的其他配色保留 1.7.1 不变」，
/// 所以这里**不去改** `colorSchemeSeedInt` / `primary_color`，
/// 也不碰 `ColorScheme.fromSeed` 的派生逻辑。
///
/// ## 为什么聊天色要独立
///
/// 1.7.1 的聊天气泡跟全局种子色联动，用户换主色时气泡跟着变，
/// 但用户想保留全局 1.7.1 的观感、只让聊天界面变成淡蓝。
/// 独立出来才能同时满足两个诉求。
class QingChatTheme {
  const QingChatTheme._();

  /// 聊天气泡候选色
  ///
  /// 全部低饱和度莫兰迪色，与全局色板同一质感。
  /// 顺序即设置页展示顺序，按色相环绕排列。
  static const List<QingChatAccent> accents = <QingChatAccent>[
    QingChatAccent('晴空蓝', Color(0xFF5B87C4)), // ★ 默认
    QingChatAccent('海蓝', Color(0xFF3F6A9E)),
    QingChatAccent('浅空蓝', Color(0xFF7FA6D9)),
    QingChatAccent('灰蓝', Color(0xFF6E87A6)),
    QingChatAccent('鼠尾草', Color(0xFF7D9B87)),
    QingChatAccent('雾青', Color(0xFF6E9393)),
    QingChatAccent('陶粉', Color(0xFFB08892)),
    QingChatAccent('燕麦', Color(0xFF9B8F6F)),
    QingChatAccent('石墨', Color(0xFF75757C)),
    QingChatAccent('砖红', Color(0xFF905651)),
    QingChatAccent('琥珀', Color(0xFF82715E)),
    QingChatAccent('苔绿', Color(0xFF78A25B)),
    QingChatAccent('黛蓝', Color(0xFF8297A6)),
    QingChatAccent('湖蓝', Color(0xFF4E8FB8)),
    QingChatAccent('靛蓝', Color(0xFF5B5BA2)),
  ];

  /// 默认聊天主题色：晴空蓝
  ///
  /// 用户指定。主色 `#5B87C4` 兑白 30% 得到我方气泡底 `#CEDBED`，
  /// 即 v1.8.0 原型里用户认可的那一版观感。
  static const Color defaultAccent = Color(0xFF5B87C4);

  /// 我方气泡底色 = 主色兑白 30%
  static Color ownBubble(Color accent) => _mixWhite(accent, 0.30);

  /// 我方气泡描边 = 主色 22% 透明
  static Color ownBubbleBorder(Color accent) => accent.withAlpha(56);

  /// 对方气泡底色：纯白
  static const Color otherBubble = Color(0xFFFFFFFF);

  /// 对方气泡描边：冷灰
  static const Color otherBubbleBorder = Color(0xFFE4EAF2);

  /// 气泡文字色（两侧共用，固定深色）
  ///
  /// 固定而非跟随主色，保证任意主色下对比度都 ≥ 10:1
  /// （最浅的苔绿气泡底 #D7E3CE 上仍有 11.8:1）。
  static const Color bubbleText = Color(0xFF16233A);

  /// 气泡内时间戳色：主色压暗一档
  static Color bubbleTimestamp(Color accent) => _scale(accent, 0.52);

  /// 按色值反查候选色名。找不到返回 null。
  static String? accentName(Color color) {
    for (final a in accents) {
      if (a.color.toARGB32() == color.toARGB32()) return a.name;
    }
    return null;
  }

  /// 与白色按比例调和。[pct] = 0 全白，1 = 原色
  ///
  /// ⚠️ Flutter 3.27+ 的 Color.from 签名：
  ///   const Color.from({required double alpha, red, green, blue})
  ///   四个分量都是 **double 且取值 0~1**（不是 0~255）。
  ///   已对照 flutter 3.47.8 engine/src/flutter/lib/ui/painting.dart 核实。
  static Color _mixWhite(Color color, double pct) {
    return Color.from(
      alpha: color.a,
      red: color.r * pct + (1 - pct),
      green: color.g * pct + (1 - pct),
      blue: color.b * pct + (1 - pct),
    );
  }

  /// 直接缩放（压暗用），factor < 1 变暗
  static Color _scale(Color color, double factor) {
    return Color.from(
      alpha: color.a,
      red: color.r * factor,
      green: color.g * factor,
      blue: color.b * factor,
    );
  }
}

/// 聊天气泡候选色
class QingChatAccent {
  const QingChatAccent(this.name, this.color);

  final String name;
  final Color color;
}

/// 聊天主题色控制器
///
/// 独立于 [ThemeController]（全局主色），只管聊天气泡。
/// 通过 Provider 提供，任何页面都能读；改完立即生效并持久化。
class QingChatThemeController extends ChangeNotifier {
  final SharedPreferences? _prefs;

  /// 无 Provider 时的降级实例（用默认色，不写存储）
  factory QingChatThemeController.fallback() =>
      QingChatThemeController(null);

  QingChatThemeController(this._prefs) {
    _load();
  }

  Color _accent = QingChatTheme.defaultAccent;

  /// 当前聊天主题色
  Color get accent => _accent;

  /// 当前聊天主题色名（不在候选列表里时返回 null）
  String? get accentName => QingChatTheme.accentName(_accent);

  /// 是否已经是默认配色
  bool get isDefault =>
      _accent.toARGB32() == QingChatTheme.defaultAccent.toARGB32();

  void _load() {
    final raw = _prefs?.getInt(AppSettings.chatAccentInt.key);
    if (raw != null) {
      _accent = Color(raw);
    }
  }

  /// 设置聊天主题色
  Future<void> setAccent(Color color) async {
    await _prefs?.setInt(AppSettings.chatAccentInt.key, color.toARGB32());
    _accent = color;
    notifyListeners();
  }

  /// 一键恢复默认配色（晴空蓝）
  Future<void> resetToDefault() async {
    await setAccent(QingChatTheme.defaultAccent);
  }
}

/// 聊天主题色作用域
///
/// 用 [Provider] 提供 [QingChatThemeController]。
/// 挂在 MaterialApp 的 builder 里，全局可达。
class QingChatThemeScope extends StatelessWidget {
  final Widget child;

  const QingChatThemeScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return child;
        return ChangeNotifierProvider<QingChatThemeController>(
          create: (_) => QingChatThemeController(snapshot.data!),
          child: child,
        );
      },
    );
  }
}

/// 取聊天主题色控制器
extension QingChatThemeContext on BuildContext {
  /// 取聊天主题色控制器
  ///
  /// ⚠️ 必须用 **watch**（listen: true）：气泡需要随主题色变化而重建，
  ///    用 listen: false 的话切换颜色后气泡不会更新。
  ///
  /// Provider 不在树上时（例如深链接直接进房间）降级为默认色，不崩。
  QingChatThemeController get qingChatTheme {
    try {
      return Provider.of<QingChatThemeController>(this);
    } catch (_) {
      return QingChatThemeController.fallback();
    }
  }
}
