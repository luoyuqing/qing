import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Qing · 底部导航（五 Tab）
///
/// 聊天 / 简报 / 任务 / 记忆 / 设置。
/// 页面之间用 go_router 切换；当前页高亮由 currentIndex 决定。
class QingBottomNav extends StatelessWidget {
  final int currentIndex;

  const QingBottomNav({super.key, required this.currentIndex});

  static const _routes = [
    '/rooms',
    '/rooms/briefing',
    '/rooms/tasks',
    '/rooms/memory',
    '/rooms/settings',
  ];

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (index) {
        if (index == currentIndex) return;
        context.go(_routes[index]);
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          selectedIcon: Icon(Icons.chat_bubble),
          label: '聊天',
        ),
        NavigationDestination(
          icon: Icon(Icons.article_outlined),
          selectedIcon: Icon(Icons.article),
          label: '简报',
        ),
        NavigationDestination(
          icon: Icon(Icons.task_alt_outlined),
          selectedIcon: Icon(Icons.task_alt),
          label: '任务',
        ),
        NavigationDestination(
          icon: Icon(Icons.psychology_outlined),
          selectedIcon: Icon(Icons.psychology),
          label: '记忆',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '设置',
        ),
      ],
    );
  }
}
