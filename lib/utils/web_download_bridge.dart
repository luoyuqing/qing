// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// WebView 内网页触发下载时的原生落盘桥。
///
/// Android 的 WebView 在被宿主 App 未注册 DownloadListener 时，会把
/// `Content-Disposition: attachment` 的响应静默丢弃（点下载毫无反应）。
/// webview_flutter_android 至今没有暴露下载回调，因此这里用
/// JavaScriptChannel 拦截 `a[download]`，再把 URL 交给原生
/// DownloadManager：由原生读取 WebView CookieManager 里的会话 Cookie，
/// 保证需要登录的页面（如凌烟阁）也能下载成功。
///
/// 非 Android 平台不注册原生实现，调用方需处理 [supported] == false。
class WebDownloadBridge {
  const WebDownloadBridge._();

  static const MethodChannel _channel = MethodChannel(
    'chat.qingzhuli/web_download',
  );

  /// 仅 Android 提供原生下载器；其余平台返回 false，由 UI 提示改用浏览器。
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 交给系统下载队列。
  ///
  /// [filename] 可为空，原生侧会从 URL path 推断；[url] 必须是 http/https。
  /// 返回 `{ok: true, id, filename, dir}` 或 `{ok: false, error}`。
  static Future<Map<String, dynamic>> enqueue({
    required String url,
    String filename = '',
  }) async {
    if (!supported) {
      return const {'ok': false, 'error': '当前平台不支持内置下载'};
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'enqueue',
        {'url': url, 'filename': filename},
      );
      return result ?? const {'ok': false, 'error': '原生下载器无返回'};
    } on PlatformException catch (e) {
      return {'ok': false, 'error': e.message ?? e.code};
    } on MissingPluginException {
      return const {'ok': false, 'error': '当前版本未包含下载组件'};
    }
  }
}
