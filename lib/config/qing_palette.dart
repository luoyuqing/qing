import 'package:material_ui/material_ui.dart';

/// Qing · 淡雅主题色板
///
/// 设置 → 主题 → 配色用。全部是低饱和度莫兰迪色，
/// Material 3 的 fromSeed 派生出来的浅色档都很素净，不会出现大红大紫。
///
/// v1.10.4：移除全部紫色系（雾紫 / 藕荷），换成晴空蓝一族。
/// 「晴空蓝 #5B87C4」与聊天气泡默认色、全局默认主色是同一个值；
/// 老用户存过紫的，由 themes.dart 的 kLegacyPurpleSeeds 自动迁过来。
class QingAccent {
  const QingAccent(this.name, this.color);

  final String name;
  final Color color;
}

const List<QingAccent> qingAccents = <QingAccent>[
  QingAccent('晴空蓝', Color(0xFF5B87C4)),
  QingAccent('浅空蓝', Color(0xFF7FA6D9)),
  QingAccent('灰蓝', Color(0xFF6E87A6)),
  QingAccent('鼠尾草', Color(0xFF7D9B87)),
  QingAccent('雾青', Color(0xFF6E9393)),
  QingAccent('陶粉', Color(0xFFB08892)),
  QingAccent('燕麦', Color(0xFF9B8F6F)),
  QingAccent('石墨', Color(0xFF75757C)),
];
