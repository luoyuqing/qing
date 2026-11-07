// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/utils/custom_http_client.dart';
import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:flutter/material.dart' show Icons, IconData;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Qing ·「服务」网关客户端
///
/// 只跟公网 hub 通信：拉服务目录 + 换一次性票据。
/// Bearer 复用设备配对 token（FlutterSecureStorage 里的
/// `qingzhuli.device_hub.token`），不引入第二套凭据。
/// 底层复用项目现成的 HttpClient 工厂（带 ISRG 根证书），
/// 老 Android 连 Let's Encrypt 证书时才不会握手失败。
class ServiceClient {
  /// 公网唯一业务入口。注意别和 DeviceHubClient.baseUrl() 的内网地址混用。
  static const String baseUrl = 'https://hub.3585616.xyz';

  static const String allowedHostSuffix = '.3585616.xyz';

  static final http.Client _http = IOClient(
    CustomHttpClient.customHttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 60),
  );

  static Future<Map<String, String>> _headers() async {
    final token = await DeviceHubClient.token();
    if (token == null || token.isEmpty) {
      throw StateError('尚未配对设备，请先在「设备数据」里完成配对');
    }
    return {
      'Content-Type': 'application/json; charset=utf-8',
      'Authorization': 'Bearer $token',
    };
  }

  static bool isAllowedHost(String host) {
    final h = host.toLowerCase();
    return h == '3585616.xyz' || h.endsWith(allowedHostSuffix);
  }

  /// GET /svc/catalog —— 服务端下发，加服务不用发版。
  static Future<List<ServiceItem>> catalog() async {
    final resp = await _http
        .get(Uri.parse('$baseUrl/svc/catalog'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('服务目录读取失败（HTTP ${resp.statusCode}）');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final raw = (data['services'] as List? ?? [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
    return raw
        .map(ServiceItem.fromJson)
        .where((item) => isAllowedHost(item.hostname))
        .toList();
  }

  /// POST /svc/ticket —— 换 60s 一次性票据，返回 WebView 的入口 URL。
  static Future<String> ticket(String serviceId) async {
    final resp = await _http
        .post(
          Uri.parse('$baseUrl/svc/ticket'),
          headers: await _headers(),
          body: jsonEncode({'service_id': serviceId}),
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 429) {
      throw Exception('操作太频繁，稍后再试');
    }
    if (resp.statusCode != 200) {
      throw Exception('换票失败（HTTP ${resp.statusCode}）');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final url = data['url'] as String?;
    if (url == null) throw StateError('服务端未返回入口地址');
    final uri = Uri.tryParse(url);
    // 防服务端被篡改后把 App 引到外部站点
    if (uri == null || uri.scheme != 'https' || !isAllowedHost(uri.host)) {
      throw StateError('服务端返回的入口地址不在白名单内');
    }
    return url;
  }

  /// 退出登录 / 切换账号时由页面调用 WebViewCookieManager().clearCookies()，
  /// 这里不碰 WebView 依赖，保持 client 纯粹的 HTTP 职责。
}

class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.name,
    required this.hostname,
    required this.path,
    this.desc = '',
    this.icon = 'apps',
  });

  final String id;
  final String name;
  final String hostname;
  final String path;
  final String desc;
  final String icon;

  factory ServiceItem.fromJson(Map<String, dynamic> json) => ServiceItem(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? json['id'] ?? '服务').toString(),
        hostname: (json['hostname'] ?? '').toString(),
        path: (json['path'] ?? '/').toString(),
        desc: (json['desc'] ?? '').toString(),
        icon: (json['icon'] ?? 'apps').toString(),
      );

  IconData get iconData => switch (icon) {
        'tv' => Icons.live_tv_outlined,
        'subtitles' => Icons.subtitles_outlined,
        'monitor' => Icons.monitor_heart_outlined,
        'storage' => Icons.storage_outlined,
        _ => Icons.apps_outlined,
      };
}
