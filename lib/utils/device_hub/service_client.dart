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

  /// 会话 Cookie 由服务端 `/__gate` 在换票时写入，有效期 8 小时；
  /// 每次打开服务都会重新换票并刷新，因此不需要（也不提供）手动清理入口。
  /// 这里不碰 WebView 依赖，保持 client 纯粹的 HTTP 职责。

  static Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final resp = await _http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: await _headers(),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    Map<String, dynamic> data = const {};
    try {
      if (resp.bodyBytes.isNotEmpty) {
        data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      }
    } catch (_) {
      // 非 JSON 响应按 HTTP 状态报错即可
    }
    if (resp.statusCode != 200) {
      final msg = data['error']?.toString();
      throw Exception(msg?.isNotEmpty == true ? msg : 'HTTP ${resp.statusCode}');
    }
    return data;
  }

  /// GET /svc/fav/list —— 收藏夹条目（顺序由服务端 sort 决定）
  static Future<List<FavItem>> favList() async {
    final resp = await _http
        .get(Uri.parse('$baseUrl/svc/fav/list'), headers: await _headers())
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('收藏列表读取失败（HTTP ${resp.statusCode}）');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return (data['items'] as List? ?? [])
        .whereType<Map>()
        .map((e) => FavItem.fromJson(e.map((k, v) => MapEntry(k.toString(), v))))
        .where((f) => f.url.isNotEmpty)
        .toList();
  }

  static Future<FavItem> favAdd({
    required String name,
    required String url,
    String icon = '',
  }) async {
    final data = await _postJson('/svc/fav/add', {
      'name': name,
      'url': url,
      'icon': icon,
    });
    final item = data['item'];
    if (item is! Map) throw Exception('服务端未返回收藏条目');
    return FavItem.fromJson(item.map((k, v) => MapEntry(k.toString(), v)));
  }

  static Future<void> favDel(int id) => _postJson('/svc/fav/del', {'id': id});

  static Future<void> favOrder(List<int> ids) =>
      _postJson('/svc/fav/order', {'ids': ids});

  /// 本机服务的自定义顺序（服务端存 settings.svc_order_local）
  static Future<void> saveLocalOrder(List<String> ids) =>
      _postJson('/svc/order', {'ids': ids});
}

/// 一个网页收藏条目
class FavItem {
  const FavItem({
    required this.id,
    required this.name,
    required this.url,
    this.icon = '',
  });

  final int id;
  final String name;
  final String url;
  final String icon;

  factory FavItem.fromJson(Map<String, dynamic> json) => FavItem(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: (json['name'] ?? '').toString(),
        url: (json['url'] ?? '').toString(),
        icon: (json['icon'] ?? '').toString(),
      );

  Uri? get uri => Uri.tryParse(url);

  String get host {
    final u = uri;
    if (u == null) return url;
    final h = u.host;
    return h.startsWith('www.') ? h.substring(4) : h;
  }

  String get initial {
    final s = name.trim().isNotEmpty ? name.trim() : host;
    if (s.isEmpty) return '?';
    return String.fromCharCode(s.runes.first).toUpperCase();
  }
}

class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.name,
    required this.hostname,
    required this.path,
    this.desc = '',
    this.icon = 'apps',
    this.group = 'local',
    this.type = 'page',
  });

  final String id;
  final String name;
  final String hostname;
  final String path;
  final String desc;
  final String icon;

  /// 服务页分组标识：local = 本机服务，web = 外网服务。
  /// 由服务端 catalog 下发，App 不认识的值按原字符串单独成组。
  final String group;

  /// page = 普通页面卡片；bookmarks = 原生收藏列表
  final String type;

  factory ServiceItem.fromJson(Map<String, dynamic> json) => ServiceItem(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? json['id'] ?? '服务').toString(),
        hostname: (json['hostname'] ?? '').toString(),
        path: (json['path'] ?? '/').toString(),
        desc: (json['desc'] ?? '').toString(),
        icon: (json['icon'] ?? 'apps').toString(),
        group: (json['group'] ?? 'local').toString(),
        type: (json['type'] ?? 'page').toString(),
      );

  IconData get iconData => switch (icon) {
        'tv' => Icons.live_tv_outlined,
        'subtitles' => Icons.subtitles_outlined,
        'monitor' => Icons.monitor_heart_outlined,
        'storage' => Icons.storage_outlined,
        'cloud' => Icons.cloud_outlined,
        'book' => Icons.auto_stories_outlined,
        'bookmark' => Icons.bookmarks_outlined,
        _ => Icons.apps_outlined,
      };
}
