// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../../config/app_config.dart';

class ReplyContent extends StatelessWidget {
  final Event replyEvent;
  final Timeline? timeline;

  /// 引用框的基准色（Qing）
  ///
  /// 气泡里必须传**气泡自身的文字色**：Qing 的两侧气泡永远是浅底深字
  /// （对方纯白 / 我方主色兑白 30%），而 FluffyChat 原来的实现用
  /// `tertiary` / `tertiaryContainer` / `onTertiary` 上色 —— 这几个在浅蓝气泡
  /// 上几乎是同色，引用框会糊成一片看不见（用户截图里的情况）。
  ///
  /// 输入框上方那条引用预览没有气泡底，不传即可，跟随主题的 onSurface。
  final Color? textColor;

  const ReplyContent(
    this.replyEvent, {
    this.timeline,
    this.textColor,
    super.key,
  });

  static const BorderRadius borderRadius = BorderRadius.only(
    topRight: Radius.circular(AppConfig.borderRadius / 2),
    bottomRight: Radius.circular(AppConfig.borderRadius / 2),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final timeline = this.timeline;
    final displayEvent = timeline != null
        ? replyEvent.getDisplayEvent(timeline)
        : replyEvent;
    const fontSize = AppConfig.messageFontSize;

    // 三种深浅都从同一个基准色派生，保证在任何气泡底色上都成对成立：
    // 竖条 35%（弱提示）、发件人 100% 加粗（第一眼）、正文 74%（次级信息）。
    final baseColor = textColor ?? theme.colorScheme.onSurface;
    final barColor = baseColor.withAlpha(90);
    final nameColor = baseColor;
    final bodyColor = baseColor.withAlpha(190);

    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      child: Row(
        mainAxisSize: .min,
        children: <Widget>[
          Container(
            width: 5,
            height: fontSize * 2 + 16,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
              color: barColor,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: .start,
              mainAxisAlignment: .center,
              children: <Widget>[
                FutureBuilder<User?>(
                  initialData: displayEvent.senderFromMemoryOrFallback,
                  future: displayEvent.fetchSenderUser(),
                  builder: (context, snapshot) {
                    return Text(
                      '${snapshot.data?.calcDisplayname() ?? displayEvent.senderFromMemoryOrFallback.calcDisplayname()}:',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: nameColor,
                        fontSize: fontSize,
                      ),
                    );
                  },
                ),
                Text(
                  displayEvent
                      .calcLocalizedBodyFallback(
                        MatrixLocals(L10n.of(context)),
                        withSenderNamePrefix: false,
                        hideReply: true,
                        plaintextBody: true,
                      )
                      .trim()
                      .replaceAll('\n', ' '),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(color: bodyColor, fontSize: fontSize),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}
