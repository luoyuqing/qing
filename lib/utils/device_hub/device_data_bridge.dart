import 'package:flutter/services.dart';

/// 清助理 · 设备数据桥（Android 原生只读采集）
class DevicePermissionStatus {
  final bool notification;
  final bool calendar;
  final bool contacts;
  final bool usage;
  final bool location;
  final bool files;
  final String model;
  final String androidVersion;

  const DevicePermissionStatus({
    required this.notification,
    required this.calendar,
    required this.contacts,
    required this.usage,
    required this.location,
    required this.files,
    required this.model,
    required this.androidVersion,
  });

  factory DevicePermissionStatus.fromMap(Map<dynamic, dynamic> m) =>
      DevicePermissionStatus(
        notification: m['notification'] == true,
        calendar: m['calendar'] == true,
        contacts: m['contacts'] == true,
        usage: m['usage'] == true,
        location: m['location'] == true,
        files: m['files'] == true,
        model: (m['model'] ?? '') as String,
        androidVersion: (m['android'] ?? '') as String,
      );

  bool get allGranted =>
      notification && calendar && contacts && usage && location && files;

  int get grantedCount => [
        notification,
        calendar,
        contacts,
        usage,
        location,
        files,
      ].where((e) => e).length;
}

class DeviceNotification {
  final String package;
  final String appName;
  final String title;
  final String text;
  final int postedAt;

  const DeviceNotification(this.package, this.appName, this.title, this.text,
      this.postedAt);

  Map<String, dynamic> toJson() => {
        'package': package,
        'appName': appName,
        'title': title,
        'text': text,
        'postedAt': postedAt,
      };
}

class DeviceDataBridge {
  static const MethodChannel _channel =
      MethodChannel('chat.qingzhuli/device_data');

  static Future<DevicePermissionStatus> status() async {
    final map = await _channel.invokeMethod<Map>('status');
    return DevicePermissionStatus.fromMap(map ?? const {});
  }

  static Future<void> openNotificationSettings() =>
      _channel.invokeMethod('openNotificationSettings');

  static Future<void> openUsageSettings() =>
      _channel.invokeMethod('openUsageSettings');

  static Future<void> openAppSettings() =>
      _channel.invokeMethod('openAppSettings');

  static Future<DevicePermissionStatus> requestFiles() async {
    final map = await _channel.invokeMethod<Map>('requestFiles');
    return DevicePermissionStatus.fromMap(map ?? const {});
  }

  /// 跳「所有文件访问权限」（能列出文档/压缩包等非媒体文件）
  static Future<bool> openAllFilesAccess() async =>
      await _channel.invokeMethod<bool>('openAllFilesAccess') ?? false;

  static Future<DevicePermissionStatus> requestLocation() async {
    final map = await _channel.invokeMethod<Map>('requestLocation');
    return DevicePermissionStatus.fromMap(map ?? const {});
  }

  static Future<DevicePermissionStatus> requestCalendarContacts() async {
    final map = await _channel.invokeMethod<Map>('requestCalendarContacts');
    return DevicePermissionStatus.fromMap(map ?? const {});
  }

  static Future<List<DeviceNotification>> notifications({int limit = 100}) async {
    final list = await _channel
        .invokeMethod<List>('notifications', {'limit': limit});
    return (list ?? [])
        .whereType<Map>()
        .map((m) => DeviceNotification(
              (m['package'] ?? '') as String,
              (m['appName'] ?? '') as String,
              (m['title'] ?? '') as String,
              (m['text'] ?? '') as String,
              (m['postedAt'] ?? 0) as int,
            ))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> calendar({
    required int fromMs,
    required int toMs,
  }) async {
    final list = await _channel.invokeMethod<List>(
        'calendar', {'fromMs': fromMs, 'toMs': toMs});
    return (list ?? [])
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> contacts({int limit = 500}) async {
    final list = await _channel.invokeMethod<List>('contacts', {'limit': limit});
    return (list ?? [])
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> usage({
    required int fromMs,
    required int toMs,
  }) async {
    final list =
        await _channel.invokeMethod<List>('usage', {'fromMs': fromMs, 'toMs': toMs});
    return (list ?? [])
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  static Future<Map<String, dynamic>> location() async {
    final map = await _channel.invokeMethod<Map>('location') ?? const {};
    return map.map((k, v) => MapEntry(k.toString(), v));
  }

  static Future<List<Map<String, dynamic>>> files({
    int limit = 30,
    String query = '',
  }) async {
    final list = await _channel
        .invokeMethod<List>('files', {'limit': limit, 'query': query});
    return (list ?? [])
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }
}
