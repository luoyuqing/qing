// SPDX-FileCopyrightText: 2026 Qing
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 一次更新查询的结果
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    this.notes = '',
    this.apkUrl = '',
    this.htmlUrl = '',
    this.apkSize = 0,
    this.source = '',
  });

  final String version;
  final String notes;
  final String apkUrl;
  final String htmlUrl;
  final int apkSize;

  /// hub / github，仅用于日志排查
  final String source;

  bool get hasApk => apkUrl.isNotEmpty;

  String get sizeText => apkSize <= 0
      ? ''
      : '${(apkSize / 1048576).toStringAsFixed(1)} MB';
}

/// 检查结果：网络是否成功 + 是否有新版
class AppUpdateResult {
  const AppUpdateResult({required this.ok, this.info, this.error});

  final bool ok;
  final AppUpdateInfo? info;
  final String? error;

  bool get hasUpdate => info != null;
}

/// App 内更新检查
///
/// 设计约束（国内网络环境）：
/// - 优先问自建 hub，由服务端代查 GitHub；hub 不通才直连 api.github.com。
/// - 每个请求 5 秒硬超时，失败静默降级，绝不把启动流程或设置页卡住。
/// - 静默检查每天最多一次，结果写进 AppSettings，供设置页画红点。
abstract class AppUpdateService {
  static const Duration requestTimeout = Duration(seconds: 5);

  static String? _cachedCurrent;

  /// AppSettings 里记录的新版本号（空 = 无更新）
  static String get availableVersion => AppSettings.appUpdateVersion.value;

  static bool get hasUpdate => availableVersion.isNotEmpty;

  static Future<String> currentVersion() async {
    if (_cachedCurrent != null) return _cachedCurrent!;
    try {
      _cachedCurrent = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      _cachedCurrent = '0.0.0';
    }
    return _cachedCurrent!;
  }

  /// 启动后调用：一天最多一次，任何异常都吞掉
  static Future<void> checkSilently() async {
    try {
      final today = DateTime.now().toIso8601String().split('T').first;
      if (AppSettings.appUpdateCheckedAt.value == today) return;
      await AppSettings.appUpdateCheckedAt.setItem(today);
      final result = await check();
      Logs().i(
        '[update] 静默检查 ok=${result.ok} '
        'latest=${result.info?.version ?? '-'} via=${result.info?.source ?? '-'}',
      );
    } catch (e) {
      Logs().d('[update] 静默检查异常（忽略）：$e');
    }
  }

  /// 主动检查。manual 只影响日志级别，不改变超时行为。
  static Future<AppUpdateResult> check({bool manual = false}) async {
    final current = await currentVersion();
    Map<String, dynamic>? data;
    String source = 'hub';

    try {
      final hub = await DeviceHubClient.appRelease().timeout(requestTimeout);
      if (hub['ok'] == false) {
        Logs().d('[update] hub 查询失败：${hub['error']}');
      } else {
        data = hub;
      }
    } catch (e) {
      Logs().d('[update] hub 不可用：$e');
    }

    if (data == null) {
      source = 'github';
      data = await _fetchFromGitHub();
    }

    if (data == null) {
      return const AppUpdateResult(ok: false, error: '网络不可用或查询超时');
    }

    final latest = '${data['version'] ?? ''}'.trim();
    if (latest.isEmpty) {
      return const AppUpdateResult(ok: false, error: '发布信息格式异常');
    }

    final info = AppUpdateInfo(
      version: latest,
      notes: '${data['notes'] ?? ''}',
      apkUrl: '${data['apk_url'] ?? ''}',
      htmlUrl: '${data['html_url'] ?? ''}',
      apkSize: (data['apk_size'] as num?)?.toInt() ?? 0,
      source: source,
    );

    if (compareVersion(latest, current) > 0) {
      await AppSettings.appUpdateVersion.setItem(latest);
      Logs().i('[update] 发现新版本 $latest（当前 $current，via $source）');
      return AppUpdateResult(ok: true, info: info);
    }

    // 已经是最新（或本地比线上还新，例如刚发版前的手工包）
    await AppSettings.appUpdateVersion.setItem('');
    Logs().i('[update] 已是最新（当前 $current，线上 $latest）');
    return const AppUpdateResult(ok: true);
  }

  /// 直连 GitHub（hub 不可用时的兜底），同样 5 秒上限
  static Future<Map<String, dynamic>?> _fetchFromGitHub() async {
    try {
      final resp = await http.get(
        Uri.parse(AppConfig.latestReleaseApiUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(requestTimeout);
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      if (data is! Map) return null;
      final tag = '${data['tag_name'] ?? ''}';
      Map? apk;
      for (final a in (data['assets'] as List?) ?? const []) {
        if (a is Map && '${a['name']}'.endsWith('.apk')) {
          apk = a;
          break;
        }
      }
      return <String, dynamic>{
        'version': tag.replaceFirst(RegExp(r'^[vV]'), ''),
        'notes': '${data['body'] ?? ''}',
        'apk_url': '${apk?['browser_download_url'] ?? ''}',
        'apk_size': apk?['size'] ?? 0,
        'html_url': '${data['html_url'] ?? ''}',
      };
    } catch (e) {
      Logs().d('[update] GitHub 直连失败：$e');
      return null;
    }
  }

  /// 语义化比较：1.20.5 vs 1.21.0；忽略 +build 与后缀
  static int compareVersion(String a, String b) {
    List<int> parts(String v) => v
        .split('+')
        .first
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final pa = parts(a);
    final pb = parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
