// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:async/async.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/settings_agent/diagnose_page.dart';
import 'package:fluffychat/pages/settings_agent/model_page.dart';
import 'package:fluffychat/pages/settings_agent/plugins_page.dart';
import 'package:fluffychat/pages/settings_agent/usage_page.dart';
import 'package:fluffychat/utils/app_update_service.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../widgets/mxc_image_viewer.dart';
import '../../widgets/qing_bottom_nav.dart';
import 'settings.dart';

/// 「关于」入口：发现新版本时在标题右侧显示小红点。
///
/// 检查更新发生在启动时（静默）或对话框内（手动），这里只负责读结果；
/// 从对话框返回后重新读一次，红点能立即反映最新状态。
class _AboutTile extends StatefulWidget {
  const _AboutTile({required this.onOpen});

  final Future<void> Function() onOpen;

  @override
  State<_AboutTile> createState() => _AboutTileState();
}

class _AboutTileState extends State<_AboutTile> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasUpdate = AppUpdateService.hasUpdate;
    final version = AppUpdateService.availableVersion;
    return ListTile(
      leading: const Icon(Icons.info_outline_rounded),
      title: Row(
        children: [
          Text(L10n.of(context).about),
          if (hasUpdate) ...[
            const SizedBox(width: 8),
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFC05552),
              ),
            ),
          ],
        ],
      ),
      subtitle: hasUpdate
          ? Text(
              '有新版本 $version',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: const Color(0xFFC05552),
              ),
            )
          : null,
      onTap: () async {
        await widget.onOpen();
        if (mounted) setState(() {});
      },
    );
  }
}

class SettingsView extends StatelessWidget {
  final SettingsController controller;

  const SettingsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeRoute = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;

    return Scaffold(
      bottomNavigationBar: const QingBottomNav(currentIndex: 4),
      appBar: AppBar(
        title: Text(L10n.of(context).settings),
        leading: Center(
          child: BackButton(onPressed: () => context.go('/rooms')),
        ),
      ),
      body: ListTileTheme(
        iconColor: theme.colorScheme.onSurface,
        child: ListView(
          key: const Key('SettingsListViewContent'),
          children: <Widget>[
            FutureBuilder<Profile>(
              future: controller.profileFuture,
              builder: (context, snapshot) {
                final profile = snapshot.data;
                final avatar = profile?.avatarUrl;
                final mxid =
                    Matrix.of(context).client.userID ?? L10n.of(context).user;
                final displayname =
                    profile?.displayName ?? mxid.localpart ?? mxid;
                final avatarActions = [
                  if (PlatformInfos.isMobile) AvatarAction.camera,
                  AvatarAction.file,
                  if (avatar != null) AvatarAction.remove,
                ];
                final avatarButtonStyle = IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  shadowColor: theme.colorScheme.shadow,
                  elevation: 2,
                );
                return Column(
                  crossAxisAlignment: .center,
                  mainAxisSize: .min,
                  children: [
                    Stack(
                      children: [
                        Avatar(
                          mxContent: avatar,
                          name: displayname,
                          size: Avatar.defaultSize * 2.5,
                          animated: true,
                          onTap: avatar != null
                              ? () => showDialog(
                                  context: context,
                                  builder: (_) => MxcImageViewer(avatar),
                                )
                              : null,
                        ),
                        if (profile != null)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: avatarActions.length == 1
                                ? IconButton(
                                    style: avatarButtonStyle,
                                    tooltip: L10n.of(context).changeYourAvatar,
                                    onPressed: () => controller.setAvatarAction(
                                      avatarActions.single,
                                    ),
                                    icon: const Icon(Icons.camera_alt_outlined),
                                  )
                                : PopupMenuButton<AvatarAction>(
                                    style: avatarButtonStyle,
                                    tooltip: L10n.of(context).changeYourAvatar,
                                    onSelected: controller.setAvatarAction,
                                    icon: const Icon(Icons.camera_alt_outlined),
                                    itemBuilder: (context) => [
                                      for (final action in avatarActions)
                                        PopupMenuItem(
                                          value: action,
                                          child: Row(
                                            mainAxisSize: .min,
                                            spacing: 12,
                                            children: [
                                              Icon(switch (action) {
                                                AvatarAction.camera =>
                                                  Icons.camera_alt_outlined,
                                                AvatarAction.file =>
                                                  Icons.photo_outlined,
                                                AvatarAction.remove =>
                                                  Icons.delete_outlined,
                                              }),
                                              Text(switch (action) {
                                                AvatarAction.camera => L10n.of(
                                                  context,
                                                ).openCamera,
                                                AvatarAction.file => L10n.of(
                                                  context,
                                                ).openGallery,
                                                AvatarAction.remove => L10n.of(
                                                  context,
                                                ).removeYourAvatar,
                                              }),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: controller.setDisplaynameAction,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurface,
                        iconColor: theme.colorScheme.onSurface,
                      ),
                      label: Text(
                        displayname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 18),
                      ),
                    ),
                    TextButton(
                      onPressed: () => FluffyShare.share(mxid, context),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.secondary,
                        iconColor: theme.colorScheme.secondary,
                      ),
                      child: Text(
                        mxid,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
            SwitchListTile.adaptive(
              controlAffinity: ListTileControlAffinity.trailing,
              value: controller.cryptoIdentityConnected == true,
              secondary: const Icon(Icons.backup_outlined),
              title: Text(L10n.of(context).chatBackup),
              onChanged: controller.firstRunBootstrapAction,
              contentPadding: EdgeInsets.only(left: 16, right: 8),
            ),
            FutureBuilder(
              future: Result.capture(
                Matrix.of(context).client.getAuthMetadata(),
              ).then((result) => result.asValue?.value),
              builder: (context, snapshot) {
                final accountManageUrl = snapshot.data?.accountManagementUri;
                if (accountManageUrl == null) {
                  return const SizedBox.shrink();
                }
                return ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(L10n.of(context).manageAccount),
                  trailing: const Icon(Icons.open_in_new_outlined),
                  onTap: () => launchUrl(
                    accountManageUrl,
                    mode: LaunchMode.inAppBrowserView,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.format_paint_outlined),
              title: Text(L10n.of(context).changeTheme),
              tileColor: activeRoute.startsWith('/rooms/settings/style')
                  ? theme.colorScheme.surfaceContainerHigh
                  : null,
              onTap: () => context.go('/rooms/settings/style'),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: Text(L10n.of(context).notifications),
              tileColor: activeRoute.startsWith('/rooms/settings/notifications')
                  ? theme.colorScheme.surfaceContainerHigh
                  : null,
              onTap: () => context.go('/rooms/settings/notifications'),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: QingSectionTitle('Qing'),
            ),
            ListTile(
              leading: const Icon(Icons.memory_outlined),
              title: const Text('设备数据'),
              subtitle: const Text('通知 · 日历 · 通讯录 · 应用时长'),
              tileColor: activeRoute.startsWith('/rooms/settings/device-hub')
                  ? theme.colorScheme.surfaceContainerHigh
                  : null,
              onTap: () => context.go('/rooms/settings/device-hub'),
            ),
            ListTile(
              leading: const Icon(Icons.health_and_safety_outlined),
              title: const Text('体检'),
              subtitle: const Text('配置、模型、凭据、记忆、任务一次查完'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DiagnosePage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('模型与推理'),
              subtitle: const Text('端点 · 模型 · 候选池 · 备用链（按人设独立）'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AgentModelPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: const Text('插件与能力'),
              subtitle: const Text('X2 上已安装 / 内置的插件'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PluginsPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: const Text('用量'),
              subtitle: const Text('请求数 · Tokens · 预估花费（按模型/人设）'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UsagePage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: const Text('连接应用'),
              subtitle: const Text('MCP 服务（由 X2 代理，凭据不上手机）'),
              tileColor: activeRoute.startsWith('/rooms/settings/connectors')
                  ? theme.colorScheme.surfaceContainerHigh
                  : null,
              onTap: () => context.go('/rooms/settings/connectors'),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('数据与隐私'),
              subtitle: const Text('数据保留策略 · 存储位置'),
              tileColor: activeRoute.startsWith('/rooms/settings/privacy')
                  ? theme.colorScheme.surfaceContainerHigh
                  : null,
              onTap: () => context.go('/rooms/settings/privacy'),
            ),
            ListTile(
              leading: const Icon(Icons.devices_outlined),
              title: Text(L10n.of(context).devices),
              onTap: () => context.go('/rooms/settings/devices'),
              tileColor: activeRoute.startsWith('/rooms/settings/devices')
                  ? theme.colorScheme.surfaceContainerHigh
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: Text(L10n.of(context).chat),
              onTap: () => context.go('/rooms/settings/chat'),
              tileColor: activeRoute.startsWith('/rooms/settings/chat')
                  ? theme.colorScheme.surfaceContainerHigh
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(L10n.of(context).security),
              onTap: () => context.go('/rooms/settings/security'),
              tileColor: activeRoute.startsWith('/rooms/settings/security')
                  ? theme.colorScheme.surfaceContainerHigh
                  : null,
            ),
            Divider(color: theme.dividerColor),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(
                L10n.of(context).aboutHomeserver(
                  Matrix.of(context).client.userID?.domain ?? 'homeserver',
                ),
              ),
              onTap: () => context.go('/rooms/settings/homeserver'),
              tileColor: activeRoute.startsWith('/rooms/settings/homeserver')
                  ? theme.colorScheme.surfaceContainerHigh
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(L10n.of(context).privacy),
              onTap: () => launchUrlString(AppSettings.privacyPolicy.value),
            ),
            _AboutTile(
              onOpen: () => PlatformInfos.showDialog(context),
            ),
            Divider(color: theme.dividerColor),
            ListTile(
              leading: const Icon(Icons.logout_outlined),
              title: Text(L10n.of(context).logout),
              onTap: controller.logoutAction,
            ),
          ],
        ),
      ),
    );
  }
}
