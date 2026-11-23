// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../utils/device_hub/service_client.dart';
import '../../utils/web_download_bridge.dart';

/// 「服务」内嵌页面
///
/// 安全约束：
///  - 只放行 https + *.3585616.xyz，file:// / 外链一律拦掉；
///  - 不实现 onSslError，证书错误按平台默认行为直接拒绝；
///  - 票据兑换由 nginx 302 写 HttpOnly Cookie，页面本身不接触凭据。
class ServiceWebViewPage extends StatefulWidget {
  const ServiceWebViewPage({
    super.key,
    required this.title,
    required this.hostname,
    required this.url,
    this.allowExternal = false,
  });

  final String title;
  final String hostname;
  final String url;

  /// 收藏夹条目为 true：允许打开任意 http/https 外站；
  /// 服务页卡片保持 false，只放行 *.3585616.xyz。
  final bool allowExternal;

  @override
  State<ServiceWebViewPage> createState() => _ServiceWebViewPageState();
}

class _ServiceWebViewPageState extends State<ServiceWebViewPage> {
  late final WebViewController _controller;
  int _progress = 0;

  /// 同一个 URL 2 秒内重复触发时忽略，避免用户连点产生多个下载任务。
  final Map<String, DateTime> _recentDownloads = {};

  /// 拦截 `a[download]`：
  ///  - 真实点击走 capture 阶段，抢在页面自身逻辑前拦下；
  ///  - 程序化 `a.click()`（凌烟阁就是这种）通过覆写 prototype 捕获。
  /// 命中后把 URL 交给原生下载器，WebView 不再尝试自己处理附件响应。
  static const String _downloadHookJs = r'''
(function () {
  if (window.__qingDlHook) return;
  window.__qingDlHook = 1;
  function send(a) {
    try {
      var u = (a && a.href) || '';
      if (!/^https?:/i.test(u)) return false;
      var n = a.getAttribute('download') || a.getAttribute('data-filename') || '';
      window.QingDownload.postMessage(JSON.stringify({ url: u, name: n }));
      return true;
    } catch (e) { return false; }
  }
  document.addEventListener('click', function (e) {
    var t = e.target;
    var a = t && t.closest ? t.closest('a[download]') : null;
    if (!a) return;
    if (send(a)) { e.preventDefault(); e.stopPropagation(); }
  }, true);
  var rawClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    if (this.hasAttribute && this.hasAttribute('download')) {
      if (send(this)) return;
    }
    return rawClick.apply(this, arguments);
  };
})();
''';

  Future<void> _onBridgeMessage(JavaScriptMessage message) async {
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map) return;
      data = decoded.cast<String, dynamic>();
    } catch (_) {
      return;
    }

    final url = (data['url'] ?? '').toString();
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return;

    // 与服务页导航同一条白名单：非收藏夹模式不允许被页面诱导下载站外地址
    if (!_allowed(url)) {
      _notify('已拦截站外下载链接');
      return;
    }

    final now = DateTime.now();
    final last = _recentDownloads[url];
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _recentDownloads[url] = now;
    _recentDownloads.removeWhere(
      (_, t) => now.difference(t) > const Duration(minutes: 1),
    );

    final name = (data['name'] ?? '').toString();
    final result = await WebDownloadBridge.enqueue(url: url, filename: name);
    if (!mounted) return;

    if (result['ok'] == true) {
      final filename = (result['filename'] ?? '').toString();
      _notify(
        filename.isEmpty ? '已开始下载' : '已开始下载：$filename',
        hint: '完成后在通知栏或「相册 / 下载」里查看',
      );
    } else {
      _notify('下载失败：${result['error'] ?? '未知错误'}');
    }
  }

  void _notify(String text, {String? hint}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text),
              if (hint != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    hint,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  bool _allowed(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return false;
    if (widget.allowExternal) {
      return uri.scheme == 'https' || uri.scheme == 'http';
    }
    if (uri.scheme != 'https') return false;
    return ServiceClient.isAllowedHost(uri.host);
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'QingDownload',
        onMessageReceived: (message) => unawaited(_onBridgeMessage(message)),
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_allowed(request.url)) return NavigationDecision.navigate;
            debugPrint('[service-webview] blocked: ${request.url}');
            return NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _progress = 0);
          },
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _progress = 100);
            unawaited(_controller.runJavaScript(_downloadHookJs));
          },
          onWebResourceError: (error) {
            // 只打日志：favicon / 子资源报错不该盖住页面
            debugPrint(
              '[service-webview] ${error.errorCode} ${error.description}',
            );
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: '后退',
            icon: const Icon(Icons.arrow_back_ios_new_outlined),
            onPressed: () async {
              if (await _controller.canGoBack()) await _controller.goBack();
            },
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 100)
            SizedBox(
              height: 2,
              child: LinearProgressIndicator(
                value: _progress / 100,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
