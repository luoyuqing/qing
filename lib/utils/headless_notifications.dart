// SPDX-FileCopyrightText: 2026 Qingliao contributors
//
// SPDX-License-Identifier: AGPL-3-0-or-later

import 'dart:async';
import 'dart:ui';

import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/push_helper.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';

import '../l10n/l10n.dart';

/// Qing：detached（无 GUI）引擎里的本地通知。
///
/// 后台服务（dataSync）拉起的引擎没有 GUI，也就没有 MatrixState，
/// 上游的通知订阅（MatrixState._registerSubs）不存在。上游 main.dart 的
/// detached 分支原本为 FCM 推送设计：backgroundSync=false、干等推送。
/// Qing 是纯客户端方案，/sync 长轮询本身就是推送，所以这个引擎必须
/// 持续同步，并且自己订阅 onNotification 弹本地通知。
StreamSubscription? _headlessOnSyncSub;
StreamSubscription? _headlessNotificationSub;

void startHeadlessNotificationSync(List<Client> clients) {
  cancelHeadlessNotificationSync();
  for (final client in clients) {
    if (!client.isLogged()) continue;
    // 首次同步完成后再订阅，避免把历史消息全部翻出来弹一遍。
    unawaited(
      client.onSync.stream.first.then((_) {
        _headlessNotificationSub = client.onNotification.stream.listen(
          (event) => unawaited(_showHeadlessNotification(client, event)),
        );
      }),
    );
  }
}

/// GUI 启动后调用：MatrixState 会接管通知（带前台抑制逻辑），避免重复弹。
void cancelHeadlessNotificationSync() {
  _headlessOnSyncSub?.cancel();
  _headlessNotificationSub?.cancel();
  _headlessOnSyncSub = null;
  _headlessNotificationSub = null;
}

L10n? _headlessL10n;

Future<L10n> _loadL10n() async {
  return _headlessL10n ??= await L10n.delegate.load(
    PlatformDispatcher.instance.locale,
  );
}

Future<void> _showHeadlessNotification(Client client, Event event) async {
  try {
    final l10n = await _loadL10n();
    final title = event.room.getLocalizedDisplayname(MatrixLocals(l10n));

    // 来电（RTC ring）与入会邀请在无界面引擎里没有可交互 UI，只弹普通通知
    String body;
    if (event.eventId.startsWith('invite_for_')) {
      body =
          '${event.senderFromMemoryOrFallback.calcDisplayname()} 邀请你加入会话';
    } else {
      body = await event.calcLocalizedBody(
        MatrixLocals(l10n),
        withSenderNamePrefix:
            !event.room.isDirectChat ||
            event.room.lastEvent?.senderId == client.userID,
        plaintextBody: true,
        hideReply: true,
        hideEdit: true,
        removeMarkdown: true,
      );
    }

    final id = '${client.clientName}_${event.room.id}'.hashCode;
    await FlutterLocalNotificationsPlugin().show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'qchat_messages',
          '新消息',
          channelDescription: '聊天新消息通知',
          importance: Importance.high,
          priority: Priority.high,
          onlyAlertOnce: false,
        ),
      ),
      payload: FluffyChatPushPayload(
        client.clientName,
        event.room.id,
        event.eventId,
      ).toString(),
    );
  } catch (e, s) {
    Logs().w('[HeadlessNotify] Unable to show notification', e, s);
  }
}
