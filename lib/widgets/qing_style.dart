import 'package:material_ui/material_ui.dart';

/// Qing · 统一视觉规范
///
/// 参照 today.ai 的 Today 页：大留白、柔和底色、白卡片 + 细描边、
/// 渐变 Hero、圆角胶囊。五个 Tab 共用这里的组件，保证风格一致。
Color qingPageBackground(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return Color.alphaBlend(cs.primary.withAlpha(7), cs.surface);
}

/// 卡片：白底 + 细描边 + 大圆角
class QingCard extends StatelessWidget {
  const QingCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 16),
    this.margin,
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(22);
    final inner = onTap == null
        ? Padding(padding: padding, child: child)
        : InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          );
    final content = Container(
      decoration: BoxDecoration(
        color: color ?? cs.surfaceContainerLowest,
        borderRadius: radius,
        border: Border.all(color: cs.outlineVariant.withAlpha(70)),
      ),
      child: ClipRRect(borderRadius: radius, child: inner),
    );
    return margin == null ? content : Padding(padding: margin!, child: content);
  }
}

/// 渐变 Hero：页面顶部的主视觉
class QingHero extends StatelessWidget {
  const QingHero({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.chips = const [],
    this.trailing,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String? subtitle;
  final List<String> chips;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary,
            Color.alphaBlend(cs.tertiary.withAlpha(180), cs.primary),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withAlpha(isDark ? 60 : 44),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -34,
            top: -46,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withAlpha(22),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 14, color: Colors.white.withAlpha(210)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              eyebrow,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                letterSpacing: .4,
                                color: Colors.white.withAlpha(210),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.45,
                            color: Colors.white.withAlpha(215),
                          ),
                        ),
                      ],
                      if (chips.isNotEmpty) ...[
                        const SizedBox(height: 13),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final chip in chips)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(36),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  chip,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withAlpha(235),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 段落小标题
class QingSectionTitle extends StatelessWidget {
  const QingSectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: .2,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 空状态
class QingEmpty extends StatelessWidget {
  const QingEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primaryContainer.withAlpha(110),
            ),
            child: Icon(icon, size: 26, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.5,
                color: cs.onSurfaceVariant.withAlpha(200),
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// 分段切换（晨报/晚报、记忆/画像/技能…）
class QingSegmented extends StatelessWidget {
  const QingSegmented({
    super.key,
    required this.values,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.dots,
  });

  final List<String> values;
  final List<String> labels;
  final String selected;
  final ValueChanged<String> onChanged;
  final Set<String>? dots;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withAlpha(150),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(values[i]),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: selected == values[i]
                        ? cs.surfaceContainerLowest
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: selected == values[i]
                        ? [
                            BoxShadow(
                              color: Colors.black.withAlpha(12),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          labels[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: selected == values[i]
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected == values[i]
                                ? cs.onSurface
                                : cs.onSurfaceVariant.withAlpha(170),
                          ),
                        ),
                      ),
                      if (dots != null) ...[
                        const SizedBox(width: 5),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (dots!.contains(values[i]))
                                ? cs.primary
                                : cs.outlineVariant.withAlpha(120),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

