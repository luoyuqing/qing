import 'package:material_ui/material_ui.dart';

/// 清助理 · 淡雅主题色板
///
/// 设置 → 主题 → 配色用。全部是低饱和度莫兰迪色，
/// Material 3 的 fromSeed 派生出来的浅色档都很素净，不会出现大红大紫。
class QingAccent {
  const QingAccent(this.name, this.color);

  final String name;
  final Color color;
}

const List<QingAccent> qingAccents = <QingAccent>[
  QingAccent('雾紫', Color(0xFF7A6A9C)),
  QingAccent('灰蓝', Color(0xFF6E87A6)),
  QingAccent('鼠尾草', Color(0xFF7D9B87)),
  QingAccent('雾青', Color(0xFF6E9393)),
  QingAccent('藕荷', Color(0xFFA1839B)),
  QingAccent('陶粉', Color(0xFFB08892)),
  QingAccent('燕麦', Color(0xFF9B8F6F)),
  QingAccent('石墨', Color(0xFF75757C)),
];
