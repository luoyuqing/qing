// SPDX-FileCopyrightText: 2026 Qing
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/foundation.dart';

/// Qing · 本机「聊天归档」清单
///
/// 为什么单独做个 ChangeNotifier，而不是把状态放在 ChatListController 里：
/// 归档页是**另一条路由**，在那边取消归档后主列表要立刻跟着变；
/// 两边共用一个实例最省事，也避免「退回来还看得见」的错位。
///
/// 只存 roomId，落在本机 SharedPreferences（[AppSettings.archivedRooms]），
/// 不上传服务端，也不写 m.tag / m.lowpriority —— 归档是「这台手机上怎么显示」
/// 的偏好，不该在服务器留下任何痕迹。
class ChatArchive extends ChangeNotifier {
  ChatArchive._();

  static final ChatArchive instance = ChatArchive._();

  Set<String>? _ids;

  Set<String> get ids => _ids ??= AppSettings.archivedRooms.value.toSet();

  bool get isEmpty => ids.isEmpty;
  bool get isNotEmpty => ids.isNotEmpty;
  int get length => ids.length;

  bool contains(String roomId) => ids.contains(roomId);

  /// 归档 / 取消归档；已处于目标状态时什么也不做
  Future<void> setArchived(String roomId, bool archived) async {
    final next = Set<String>.from(ids);
    final changed = archived ? next.add(roomId) : next.remove(roomId);
    if (!changed) return;
    _ids = next;
    notifyListeners();
    await AppSettings.archivedRooms.setItem(next.toList());
  }
}
