// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/dummy_chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/search_title.dart';
import 'package:fluffychat/pages/chat_list/space_view.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/public_room_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import '../../widgets/adaptive_dialogs/user_dialog.dart';
import '../../widgets/matrix.dart';
import 'chat_list_header.dart';

class ChatListViewBody extends StatefulWidget {
  final ChatListController controller;

  const ChatListViewBody(this.controller, {super.key});

  @override
  State<ChatListViewBody> createState() => _ChatListViewBodyState();
}

class _ChatListViewBodyState extends State<ChatListViewBody> {
  /// 顶部再往下拖多少像素就把归档卡片拉出来（一次手势内累计）
  static const double _revealPullDistance = 64;

  /// 往上滚多少像素就把归档卡片收回去
  ///
  /// 用很小的阈值而不是等卡片完全滚出屏幕：卡片还在视野里的时候开始收，
  /// 高度动画看起来就是「跟着手指被推上去」，等它滚没了再收反而会跳一下。
  static const double _hideScrollDistance = 8;

  double _pullDownDistance = 0;

  ChatListController get controller => widget.controller;

  /// 归档卡片：下滑出现、上划隐藏（对齐 TG 的手感）
  ///
  /// 两种滚动物理都要处理：
  /// - Android 的 Clamping：越过顶部会产生 OverscrollNotification，overscroll 为负；
  /// - iOS 的 Bouncing：不产生 overscroll 通知，而是让 pixels 直接变成负数。
  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    switch (notification) {
      case OverscrollNotification():
        if (notification.overscroll < 0 &&
            notification.metrics.extentBefore <= 0) {
          _pullDownDistance += -notification.overscroll;
          if (_pullDownDistance >= _revealPullDistance) {
            _pullDownDistance = 0;
            controller.revealArchiveEntry();
          }
        }
      case ScrollUpdateNotification():
        if (notification.metrics.pixels < -_revealPullDistance) {
          _pullDownDistance = 0;
          controller.revealArchiveEntry();
        } else if (notification.metrics.pixels > _hideScrollDistance) {
          // 上划（内容往上走）→ 收起
          _pullDownDistance = 0;
          controller.hideArchiveEntry();
        }
      case ScrollEndNotification():
        _pullDownDistance = 0;
      default:
        break;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final client = Matrix.of(context).client;
    final activeSpace = controller.activeSpaceId;
    if (activeSpace != null) {
      return SpaceView(
        key: ValueKey(activeSpace),
        spaceId: activeSpace,
        onBack: controller.clearActiveSpace,
        onChatTab: controller.onChatTap,
        activeChat: controller.activeChat,
      );
    }
    final spaces = client.rooms.where((r) => r.isSpace);
    final spaceDelegateCandidates = <String, Room>{};
    for (final space in spaces) {
      for (final spaceChild in space.spaceChildren) {
        final roomId = spaceChild.roomId;
        if (roomId == null) continue;
        spaceDelegateCandidates[roomId] = space;
      }
    }

    final publicRooms = controller.roomSearchResult?.chunk
        .where((room) => room.roomType != 'm.space')
        .toList();
    final publicSpaces = controller.roomSearchResult?.chunk
        .where((room) => room.roomType == 'm.space')
        .toList();
    final userSearchResult = controller.userSearchResult;
    const dummyChatCount = 4;
    final filter = controller.searchController.text.toLowerCase();
    return StreamBuilder(
      key: ValueKey(client.userID.toString()),
      stream: client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, _) {
        final baseRooms = controller.filteredRooms
            .where(
              (room) =>
                  !AppSettings.hideRoomsInSpaces.value ||
                  spaceDelegateCandidates[room.id] == null,
            )
            .toList();

        // 归档的会话一律不进主列表（搜索时例外：藏起来的会话也得搜得到）。
        final searching = controller.isSearchMode;
        final rooms = searching
            ? baseRooms
            : baseRooms
                  .where((room) => !controller.isArchived(room.id))
                  .toList();

        // 归档卡片条按「这台机器上归档了多少」算，不受当前筛选影响
        final archivedRooms = client.rooms
            .where((room) => controller.isArchived(room.id))
            .toList();
        // 兜底：所有会话都被归档时把卡片顶上，否则主列表会空得莫名其妙。
        // 注意不能用「当前筛选没结果」来判断 —— 切到「群组」而恰好没有群时
        // 也会命中，那会让归档卡片莫名其妙冒出来。
        final everythingArchived =
            client.rooms.isNotEmpty &&
            !client.rooms.any((room) => !controller.isArchived(room.id));
        // 平时完全看不见；只有下拉露出来，或者全部归档时兜底
        final showArchiveEntry =
            archivedRooms.isNotEmpty &&
            !searching &&
            (controller.archiveEntryVisible || everythingArchived);
        // 归档卡片是否需要在树里（隐藏时高度为 0，但保留动画载体）
        final hasArchiveCard = archivedRooms.isNotEmpty && !searching;
        final archivedUnread = archivedRooms.fold<int>(
          0,
          (sum, room) =>
              sum +
              (room.isUnreadOrInvited
                  ? (room.notificationCount > 0 ? room.notificationCount : 1)
                  : 0),
        );

        return NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: CustomScrollView(
            controller: controller.scrollController,
            // 列表内容不满一屏时也要能下拉（归档就是靠下拉拉出来的）
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              ChatListHeader(controller: controller),
              SliverList(
                delegate: SliverChildListDelegate([
                  if (controller.isSearchMode) ...[
                    SearchTitle(
                      title: L10n.of(context).publicRooms,
                      icon: const Icon(Icons.explore_outlined),
                    ),
                    PublicRoomsHorizontalList(publicRooms: publicRooms),
                    SearchTitle(
                      title: L10n.of(context).publicSpaces,
                      icon: const Icon(Icons.workspaces_outlined),
                    ),
                    PublicRoomsHorizontalList(publicRooms: publicSpaces),
                    SearchTitle(
                      title: L10n.of(context).users,
                      icon: const Icon(Icons.group_outlined),
                    ),
                    AnimatedContainer(
                      clipBehavior: Clip.hardEdge,
                      decoration: const BoxDecoration(),
                      height:
                          userSearchResult == null ||
                              userSearchResult.results.isEmpty
                          ? 0
                          : 106,
                      duration: FluffyThemes.animationDuration,
                      curve: FluffyThemes.animationCurve,
                      child: userSearchResult == null
                          ? null
                          : ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: userSearchResult.results.length,
                              itemBuilder: (context, i) => _SearchItem(
                                title:
                                    userSearchResult.results[i].displayName ??
                                    userSearchResult
                                        .results[i]
                                        .userId
                                        .localpart ??
                                    L10n.of(context).unknownDevice,
                                avatar: userSearchResult.results[i].avatarUrl,
                                onPressed: () => UserDialog.show(
                                  context: context,
                                  profile: userSearchResult.results[i],
                                ),
                              ),
                            ),
                    ),
                  ],
                  if (client.rooms.isNotEmpty && !controller.isSearchMode)
                    Container(
                      height: 36 + 8 + 8,
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        shrinkWrap: true,
                        scrollDirection: Axis.horizontal,
                        children: [
                          ...ActiveFilter.values
                              .where((filter) => filter != ActiveFilter.tag)
                              .map(
                                (filter) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4.0,
                                  ),
                                  child: Center(
                                    child: FilterChip(
                                      selected: filter == controller.activeFilter,
                                      onSelected: (_) => controller
                                          .setActiveFilter(filter, null),
                                      label: Text(
                                        filter.toLocalizedString(context),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ...controller.roomTags.entries.map(
                            (entry) => Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4.0,
                              ),
                              child: Center(
                                child: FilterChip(
                                  selected: entry.key == controller.activeTag,
                                  onSelected: (_) => controller.setActiveFilter(
                                    ActiveFilter.tag,
                                    entry.key,
                                  ),
                                  label: Text(entry.key.replaceFirst('u.', '')),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (controller.isSearchMode)
                    SearchTitle(
                      title: L10n.of(context).chats,
                      icon: const Icon(Icons.forum_outlined),
                    ),
                  if (client.prevBatch != null &&
                      rooms.isEmpty &&
                      !showArchiveEntry &&
                      !controller.isSearchMode) ...[
                    Column(
                      mainAxisAlignment: .center,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            const Column(
                              mainAxisSize: .min,
                              children: [
                                DummyChatListItem(
                                  opacity: 0.5,
                                  animate: false,
                                ),
                                DummyChatListItem(
                                  opacity: 0.3,
                                  animate: false,
                                ),
                              ],
                            ),
                            Icon(
                              CupertinoIcons.chat_bubble_text_fill,
                              size: 128,
                              color: theme.colorScheme.secondary,
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            client.rooms.isEmpty
                                ? L10n.of(context).noChatsFoundHere
                                : L10n.of(context).noMoreChatsFound,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ]),
              ),
              // 只有「一条房间都还没有」时才需要骨架屏。
              // 杀进程重进时 prevBatch 一定是 null，但本地库里房间是齐的，
              // 这时再先刷 8 行灰块（每行还带转圈）就会变成启动页与主页之间
              // 一闪而过的过程页，所以这里以「有没有房间」为准。
              if (client.prevBatch == null && client.rooms.isEmpty)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => DummyChatListItem(
                      opacity: (dummyChatCount - i) / dummyChatCount,
                      animate: false,
                    ),
                    childCount: dummyChatCount,
                  ),
                ),
              // 归档卡片常驻在树里，只做高度动画：
              // 直接插入/移除会因为上方高度突变让列表跳一下，
              // 而「上划收起」本来就在滚动过程中发生，跳动会很明显。
              if (hasArchiveCard)
                SliverToBoxAdapter(
                  child: AnimatedSize(
                    duration: FluffyThemes.animationDuration,
                    curve: FluffyThemes.animationCurve,
                    alignment: Alignment.topCenter,
                    clipBehavior: Clip.hardEdge,
                    child: showArchiveEntry
                        ? ArchivedChatsTile(
                            chatCount: archivedRooms.length,
                            unreadCount: archivedUnread,
                            onTap: controller.openArchive,
                          )
                        : const SizedBox(width: double.infinity, height: 0),
                  ),
                ),
              if (client.prevBatch != null || client.rooms.isNotEmpty)
                SliverSafeArea(
                  top: false,
                  sliver: SliverList.builder(
                    itemCount: rooms.length,
                    itemBuilder: (BuildContext context, int i) {
                      final room = rooms[i];
                      final space = spaceDelegateCandidates[room.id];
                      return ChatListItem(
                        room,
                        space: space,
                        key: Key('chat_list_item_${room.id}'),
                        filter: filter,
                        onTap: () => controller.onChatTap(room),
                        onLongPress: (context) =>
                            controller.chatContextAction(room, context, space),
                        activeChat: controller.activeChat == room.id,
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 归档入口卡片
///
/// 平时它**不在列表里**（[ChatListViewBody] 只有在下拉露出或列表被归档清空时
/// 才把它插进来）；点它进独立的归档页，和 TG 安卓版一样。
class ArchivedChatsTile extends StatelessWidget {
  final int chatCount;
  final int unreadCount;
  final VoidCallback onTap;

  const ArchivedChatsTile({
    super.key,
    required this.chatCount,
    required this.unreadCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Material(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(70),
            width: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surfaceContainerLowest,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.archive_outlined,
                    size: 21,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '归档',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$chatCount 个聊天',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (unreadCount > 0)
                  Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PublicRoomsHorizontalList extends StatelessWidget {
  const PublicRoomsHorizontalList({super.key, required this.publicRooms});

  final List<PublishedRoomsChunk>? publicRooms;

  @override
  Widget build(BuildContext context) {
    final publicRooms = this.publicRooms;
    return AnimatedContainer(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      height: publicRooms == null || publicRooms.isEmpty ? 0 : 106,
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      child: publicRooms == null
          ? null
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: publicRooms.length,
              itemBuilder: (context, i) => _SearchItem(
                title:
                    publicRooms[i].name ??
                    publicRooms[i].canonicalAlias?.localpart ??
                    L10n.of(context).group,
                avatar: publicRooms[i].avatarUrl,
                onPressed: () => showAdaptiveDialog(
                  context: context,
                  barrierDismissible: true,
                  builder: (c) => PublicRoomDialog(
                    roomAlias:
                        publicRooms[i].canonicalAlias ?? publicRooms[i].roomId,
                    chunk: publicRooms[i],
                  ),
                ),
              ),
            ),
    );
  }
}

class _SearchItem extends StatelessWidget {
  final String title;
  final Uri? avatar;
  final void Function() onPressed;

  const _SearchItem({
    required this.title,
    this.avatar,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    child: SizedBox(
      width: 84,
      child: Column(
        mainAxisSize: .min,
        children: [
          const SizedBox(height: 8),
          Avatar(mxContent: avatar, name: title),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}
