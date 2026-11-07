// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../utils/device_hub/service_client.dart';

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
  });

  final String title;
  final String hostname;
  final String url;

  @override
  State<ServiceWebViewPage> createState() => _ServiceWebViewPageState();
}

class _ServiceWebViewPageState extends State<ServiceWebViewPage> {
  late final WebViewController _controller;
  int _progress = 0;

  bool _allowed(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != 'https') return false;
    return ServiceClient.isAllowedHost(uri.host);
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
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
