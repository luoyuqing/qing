import 'package:flutter/services.dart';

/// 清助理 · 设备数据桥（Android 原生只读采集）
class DevicePermissionStatus {
  final bool notification;
  final bool calendar;
  final bool contacts;
  final bool usage;
  final bool location;
  final bool files;
  final bool allFiles;

  /// 清助理 v1.9.0：短信读取（READ_SMS，只读）
  final bool sms;
  final String model;
  final String androidVersion;

  const DevicePermissionStatus({
    required this.notification,
    required this.calendar,
    required this.contacts,
    required this.usage,
    required this.location,
    required this.files,
    required this.allFiles,
    this.sms = false,
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
        allFiles: m['all_files'] == true,
        sms: m['sms'] == true,
        model: (m['model'] ?? '') as String,
        androidVersion: (m['android'] ?? '') as String,
      );

  bool get allGranted =>
      notification && calendar && contacts && usage && location && files && sms;

  int get grantedCount => [
        notification,
        calendar,
        contacts,
        usage,
        location,
        files,
        sms,
      ].where((e) => e).length;

  /// 授权项总数（用于「已授权 x/n」展示）
  static const int totalCount = 7;
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

/// 一条短信（只读）
class DeviceSms {
  /// 系统短信库主键
  final String id;

  /// 对方号码（发送方/接收方）
  final String address;

  /// 通讯录里匹配到的人名，未匹配时为空串
  final String person;

  /// 时间戳（毫秒）
  final int dateMs;

  final String body;
  final bool read;

  /// 'in' = 收到，'out' = 已发送
  final String direction;

  const DeviceSms({
    required this.id,
    required this.address,
    required this.person,
    required this.dateMs,
    required this.body,
    required this.read,
    required this.direction,
  });

  bool get isIncoming => direction == 'in';

  Map<String, dynamic> toJson() => {
        'id': id,
        'address': address,
        'person': person,
        'date': dateMs,
        'body': body,
        'read': read,
        'direction': direction,
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

  /// 申请「读取短信」权限（READ_SMS，只读）
  static Future<DevicePermissionStatus> requestSms() async {
    final map = await _channel.invokeMethod<Map>('requestSms');
    return DevicePermissionStatus.fromMap(map ?? const {});
  }

  /// 读取短信（收件箱 + 已发送，按时间倒序）
  ///
  /// 返回字段：id / address / person / date(毫秒) / body / read / type / direction
  static Future<List<DeviceSms>> sms({
    int limit = 50,
    String query = '',
  }) async {
    final list = await _channel.invokeMethod<List>('sms', {
      'limit': limit,
      'query': query,
    });
    return (list ?? [])
        .whereType<Map>()
        .map(
          (m) => DeviceSms(
            id: (m['id'] ?? '') as String,
            address: (m['address'] ?? '') as String,
            person: (m['person'] ?? '') as String,
            dateMs: (m['date'] ?? 0) as int,
            body: (m['body'] ?? '') as String,
            read: m['read'] == true,
            direction: (m['direction'] ?? 'in') as String,
          ),
        )
        .toList();
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

  /// 手机里已安装、且有启动入口的应用（已排除本应用），按名称排序。
  /// 返回 [{package, label}]
  static Future<List<Map<String, dynamic>>> installedApps() async {
    final list = await _channel.invokeMethod<List>('installedApps') ?? const [];
    return list
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry('$k', v)))
        .toList();
  }

  /// 当前通知黑名单（包名）。命中的应用在通知监听服务里就被丢掉，
  /// 既不入本地缓存也不上报，属于源头过滤。
  static Future<List<String>> notifyBlacklist() async {
    final list = await _channel.invokeMethod<List>('notifyBlacklist') ?? const [];
    return list.map((e) => '$e').toList();
  }

  static Future<void> setNotifyBlacklist(List<String> packages) =>
      _channel.invokeMethod('setNotifyBlacklist', {'packages': packages});

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
