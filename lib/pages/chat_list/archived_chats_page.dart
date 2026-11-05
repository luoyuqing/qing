// SPDX-FileCopyrightText: 2026 Qing
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/utils/chat_archive.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Qing · 归档聊天列表页（仿 TG 的「Archived chats」独立页）
///
/// 入口只有一个：聊天列表下拉露出的归档卡片。这里不参与聊天列表的筛选
/// （全部/未读/群组），归档就是归档，只按时间排序。
class ArchivedChatsPage extends StatelessWidget {
  const ArchivedChatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('归档'),
      ),
      body: ListenableBuilder(
        listenable: ChatArchive.instance,
        builder: (context, _) {
          final client = Matrix.of(context).client;
          final rooms = client.rooms
              .where((room) => ChatArchive.instance.contains(room.id))
              .toList();
          if (rooms.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.archive_outlined,
                      size: 64,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '还没有归档的聊天',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '在聊天列表长按会话，选择「归档聊天」',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(top: 6, bottom: 24),
            itemCount: rooms.length,
            itemBuilder: (context, i) {
              final room = rooms[i];
              return ChatListItem(
                room,
                key: Key('archived_chat_${room.id}'),
                onTap: () => context.push('/rooms/${room.id}'),
                onLongPress: (posContext) =>
                    _showRoomActions(posContext, room),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _showRoomActions(BuildContext context, Room room) async {
    final unarchive = await showModalActionPopup<bool>(
      context: context,
      cancelLabel: L10n.of(context).cancel,
      actions: [
        AdaptiveModalAction(
          label: '取消归档',
          value: true,
          icon: const Icon(Icons.unarchive),
        ),
      ],
    );
    if (unarchive != true) return;
    await ChatArchive.instance.setArchived(room.id, false);
  }
}
