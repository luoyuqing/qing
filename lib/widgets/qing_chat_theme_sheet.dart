// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/qing_chat_theme.dart';
import 'package:fluffychat/utils/color_value.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// 清助理 · 聊天气泡配色选择器
///
/// ## 与全局主题色的边界（v1.8.0）
///
/// 这个选择器**只管聊天气泡**，不碰全局主色。
/// 全站主色仍在「设置 → 改变风格 → 配色」里选，那套机制保持 v1.7.1 原样。
///
/// ## 一键恢复默认
///
/// 顶部有「恢复默认配色」按钮，点击回到默认方案（晴空蓝 #5B87C4，
/// 我方气泡底 #CEDBED）。用户要求任何时候都能一键回到自己的默认配色。
class QingChatThemeButton extends StatelessWidget {
  final double iconSize;

  const QingChatThemeButton({super.key, this.iconSize = 20});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '聊天气泡配色',
      icon: Icon(Icons.palette_outlined, size: iconSize),
      onPressed: () => showQingChatThemeSheet(context),
    );
  }
}

/// 弹出聊天气泡配色选择弹层
Future<void> showQingChatThemeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => const _QingChatThemeSheet(),
  );
}

class _QingChatThemeSheet extends StatelessWidget {
  const _QingChatThemeSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = context.watch<QingChatThemeController>();
    final accent = controller.accent;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '聊天气泡配色',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '只影响聊天界面，其他页面保持不变',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // ★ 一键恢复默认配色
                if (!controller.isDefault)
                  TextButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await controller.resetToDefault();
                      if (context.mounted) Navigator.of(context).pop();
                      messenger.showSnackBar(
                        SnackBar(
                          content: const Text('已恢复默认配色（晴空蓝）'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('恢复默认'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // 当前配色预览
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: QingChatTheme.ownBubble(accent),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: QingChatTheme.ownBubbleBorder(accent)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '我方气泡',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: QingChatTheme.bubbleText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '这是你发出的消息',
                    style: TextStyle(
                      fontSize: 12,
                      color: QingChatTheme.bubbleText.withAlpha(180),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: QingChatTheme.otherBubble,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: QingChatTheme.otherBubbleBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '对方气泡',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: QingChatTheme.bubbleText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '对方的消息始终是白色，不随配色变化',
                    style: TextStyle(
                      fontSize: 12,
                      color: QingChatTheme.bubbleText.withAlpha(180),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '选择配色',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 76,
                  ),
                  itemCount: QingChatTheme.accents.length,
                  itemBuilder: (context, i) {
                    final a = QingChatTheme.accents[i];
                    final selected = a.color.toARGB32() == accent.toARGB32();
                    return Padding(
                      padding: const EdgeInsets.all(6),
                      child: Tooltip(
                        message:
                            // toARGB32 是 0xAARRGGBB，展示时只取后 6 位 RRGGBB
                            '${a.name} · #${(a.color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            controller.setAccent(a.color);
                            Navigator.of(context).pop();
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: a.color,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: selected
                                        ? a.color
                                        : theme.colorScheme.outlineVariant,
                                    width: selected ? 3 : 1,
                                  ),
                                ),
                                child: selected
                                    ? const Icon(
                                        Icons.check,
                                        size: 18,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                a.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: selected
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
