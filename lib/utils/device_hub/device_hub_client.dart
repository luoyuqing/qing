import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'device_data_bridge.dart';

/// 清助理 · device-hub 客户端
///
/// 只跟自己的服务器通信：内网直连 `http://192.168.1.10:8787`（可改）。
/// token 存 Android Keystore（flutter_secure_storage），不落日志。
class DeviceHubClient {
  static const _tokenKey = 'qingzhuli.device_hub.token';
  static const _urlKey = 'qingzhuli.device_hub.url';
  static const _lastSyncKey = 'qingzhuli.device_hub.last_sync';
  static const _lastSyncMsKey = 'qingzhuli.device_hub.last_sync_ms';
  static const _lastReportKey = 'qingzhuli.device_hub.last_report';
  static const defaultUrl = 'http://192.168.1.10:8787';

  static const _storage = FlutterSecureStorage();

  static Future<String> baseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_urlKey) ?? defaultUrl;
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, url.trim().replaceAll(RegExp(r'/+$'), ''));
  }

  static Future<String?> token() => _storage.read(key: _tokenKey);

  static Future<bool> isPaired() async => (await token()) != null;

  static Future<void> unpair() async {
    await _storage.delete(key: _tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastSyncKey);
    await prefs.remove(_lastSyncMsKey);
    await prefs.remove(_lastReportKey);
  }

  static Future<String?> lastSync() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastSyncKey);
  }

  static Future<DateTime?> lastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastSyncMsKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<String?> lastReport() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastReportKey);
  }

  static Map<String, String> _headers(String? token) => {
        'Content-Type': 'application/json; charset=utf-8',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  static Future<Map<String, dynamic>> health({String? url}) async {
    final base = url ?? await baseUrl();
    final resp = await http
        .get(Uri.parse('$base/health'))
        .timeout(const Duration(seconds: 6));
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// 用配对码换设备 token。成功后 token 存进 Keystore。
  static Future<String> pair({
    required String code,
    required String deviceName,
    String? url,
  }) async {
    final base = url ?? await baseUrl();
    final resp = await http
        .post(
          Uri.parse('$base/pair'),
          headers: _headers(null),
          body: jsonEncode({'code': code.trim(), 'device_name': deviceName}),
        )
        .timeout(const Duration(seconds: 10));
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    if (resp.statusCode != 200 || body['token'] == null) {
      throw Exception(body['error'] ?? '配对失败（HTTP ${resp.statusCode}）');
    }
    final token = body['token'] as String;
    await _storage.write(key: _tokenKey, value: token);
    if (url != null) await setBaseUrl(url);
    return token;
  }

  static Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
    {Duration timeout = const Duration(seconds: 90)}
  ) async {
    final authToken = await token();
    if (authToken == null) throw Exception('尚未配对');
    final base = await baseUrl();
    final resp = await http
        .post(Uri.parse('$base$path'),
            headers: _headers(authToken), body: jsonEncode(body))
        .timeout(timeout);
    if (resp.statusCode != 200) {
      throw Exception(_errText(resp));
    }
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> _patchJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final authToken = await token();
    if (authToken == null) throw Exception('尚未配对');
    final base = await baseUrl();
    final resp = await http
        .patch(Uri.parse('$base$path'),
            headers: _headers(authToken), body: jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) throw Exception(_errText(resp));
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  static String _errText(http.Response resp) {
    try {
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is Map && body['error'] != null) return '${body['error']}';
    } catch (_) {}
    return 'HTTP ${resp.statusCode}';
  }

  /// 只读 GET（简报 / 任务 / 记忆）
  static Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final authToken = await token();
    if (authToken == null) throw Exception('尚未配对');
    final base = await baseUrl();
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    final resp =
        await http.get(uri, headers: _headers(authToken)).timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  /// 某天的简报：晨报 + 晚报 + 待办 + 统计
  static Future<Map<String, dynamic>> briefingDay({String? date}) =>
      getJson('/briefing/day', query: date == null ? null : {'date': date});

  /// 人设内容（Hermes config.yaml 里的 agent.personalities）
  static Future<Map<String, dynamic>> personaEntries({
    String persona = 'default',
  }) async {
    final data = await getJson('/persona', query: {'persona': persona});
    return data;
  }

  /// 保存人设内容
  static Future<Map<String, dynamic>> savePersona({
    required String persona,
    required String key,
    required String content,
  }) =>
      _postJson('/persona', {
        'persona': persona,
        'key': key,
        'content': content,
      }, timeout: const Duration(seconds: 30));

  /// 让小爱立刻写一份（kind: morning / evening）
  static Future<Map<String, dynamic>> requestBriefing({String? kind}) =>
      _postJson('/briefing/request', {
        if (kind != null) 'kind': kind,
      }, timeout: const Duration(seconds: 45));

  /// 勾选/取消待办
  static Future<void> setTodoDone(int id, bool done) async {
    final authToken = await token();
    if (authToken == null) throw Exception('尚未配对');
    final base = await baseUrl();
    final resp = await http
        .patch(
          Uri.parse('$base/todos/$id'),
          headers: _headers(authToken),
          body: jsonEncode({'done': done}),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw Exception('更新待办失败：HTTP ${resp.statusCode}');
    }
  }

  static Future<Map<String, dynamic>> _ingest(
    String kind,
    List<Map<String, dynamic>> items,
  ) async {
    final authToken = await token();
    if (authToken == null) throw Exception('尚未配对');
    if (items.isEmpty) return {'stored': 0, 'kind': kind};
    final base = await baseUrl();
    final resp = await http
        .post(
          Uri.parse('$base/ingest'),
          headers: _headers(authToken),
          body: jsonEncode({'kind': kind, 'items': items}),
        )
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) {
      throw Exception('上报失败（${kind}）：HTTP ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// 采集一次并上传，返回人类可读的同步结果。
  static Future<String> syncAll({bool includeContacts = true}) async {
    final now = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final report = <String>[];

    final notifications = await DeviceDataBridge.notifications(limit: 100);
    final n1 = await _ingest(
        'notifications', notifications.map((e) => e.toJson()).toList());
    report.add('通知 ${n1['stored'] ?? 0} 条');

    // 清助理 v1.9.0：短信（只读）。未授权时原生侧返回空列表，这里自然跳过。
    final smsList = await DeviceDataBridge.sms(limit: 200);
    final nSms =
        await _ingest('sms', smsList.map((e) => e.toJson()).toList());
    report.add('短信 ${nSms['stored'] ?? 0} 条');

    final events = await DeviceDataBridge.calendar(
      fromMs: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      toMs: now.add(const Duration(days: 30)).millisecondsSinceEpoch,
    );
    final n2 = await _ingest('calendar', events);
    report.add('日程 ${n2['stored'] ?? 0} 条');

    if (includeContacts) {
      final contacts = await DeviceDataBridge.contacts(limit: 500);
      final n3 = await _ingest('contacts', contacts);
      report.add('联系人 ${n3['stored'] ?? 0} 个');
    }

    final usage = await DeviceDataBridge.usage(
      fromMs: dayStart.millisecondsSinceEpoch,
      toMs: now.millisecondsSinceEpoch,
    );
    final n4 = await _ingest('usage', usage);
    report.add('应用时长 ${n4['stored'] ?? 0} 项');

    final summary = report.join(' · ');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _lastSyncKey, '${now.year}-${_two(now.month)}-${_two(now.day)} '
            '${_two(now.hour)}:${_two(now.minute)}');
    await prefs.setInt(_lastSyncMsKey, now.millisecondsSinceEpoch);
    await prefs.setString(_lastReportKey, summary);
    return summary;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');


  // ---------- 连接应用（MCP，由 hub 代理） ----------
  /// X2 整机 + 按服务/容器的资源占用（服务端直读 /proc 与 cgroup）
  static Future<Map<String, dynamic>> serverStatus() => getJson('/server/status');

  /// 某个服务或容器的进程明细（点开时才请求）
  static Future<Map<String, dynamic>> serverServiceDetail(String key) =>
      getJson('/server/service', query: {'key': key});

  /// 整机历史曲线（1h / 6h / 24h，服务端每分钟采样）
  static Future<Map<String, dynamic>> serverHistory({String range = '24h'}) =>
      getJson('/server/history', query: {'range': range});

  static Future<List<Map<String, dynamic>>> mcpServers() async {
    final data = await getJson('/mcp/servers');
    return (data['items'] as List? ?? [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  static Future<Map<String, dynamic>> addMcpServer({
    required String name,
    required String url,
    String? token,
  }) =>
      _postJson('/mcp/servers', {
        'name': name,
        'url': url,
        if (token != null && token.trim().isNotEmpty) 'token': token.trim(),
      });

  static Future<Map<String, dynamic>> refreshMcpServer(int id) =>
      _postJson('/mcp/servers/$id/refresh', {});

  static Future<Map<String, dynamic>> callMcpTool({
    required int serverId,
    required String tool,
    required Map<String, dynamic> arguments,
  }) =>
      _postJson('/mcp/call', {
        'server_id': serverId,
        'tool': tool,
        'arguments': arguments,
      });

  static Future<void> deleteMcpServer(int id) async {
    final authToken = await token();
    if (authToken == null) throw Exception('尚未配对');
    final base = await baseUrl();
    final resp = await http
        .delete(Uri.parse('$base/mcp/servers/$id'), headers: _headers(authToken))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) throw Exception(_errText(resp));
  }

  // ---------- 数据保留策略 ----------
  static Future<Map<String, dynamic>> retention() => getJson('/admin/retention');

  static Future<Map<String, dynamic>> setRetention({
    required int notifyDays,
    required int locationDays,
  }) =>
      _patchJson('/admin/retention', {
        'notify_days': notifyDays,
        'location_days': locationDays,
      });

  // ---------- 按需取数（AI 拉，手机应答） ----------
  static Future<Map<String, dynamic>?> pollDevice({int waitSeconds = 20}) async {
    final authToken = await token();
    if (authToken == null) return null;
    final base = await baseUrl();
    final resp = await http
        .get(Uri.parse('$base/device/poll?wait=$waitSeconds'),
            headers: _headers(authToken))
        .timeout(Duration(seconds: waitSeconds + 10));
    if (resp.statusCode != 200) return null;
    final body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final cmd = body['command'];
    return cmd is Map ? cmd.map((k, v) => MapEntry(k.toString(), v)) : null;
  }

  static Future<void> respondDevice(
    String commandId, {
    required bool ok,
    Object? data,
    String? error,
  }) async {
    final authToken = await token();
    if (authToken == null) return;
    final base = await baseUrl();
    await http
        .post(Uri.parse('$base/device/respond'),
            headers: _headers(authToken),
            body: jsonEncode({
              'command_id': commandId,
              'ok': ok,
              if (ok) 'data': data,
              if (!ok) 'error': error ?? '读取失败',
            }))
        .timeout(const Duration(seconds: 20));
  }

  // ---------- 连接应用目录 ----------
  static Future<List<Map<String, dynamic>>> catalog() async {
    final data = await getJson('/catalog');
    return (data['items'] as List? ?? [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> nativeConnectors() async {
    final data = await getJson('/connectors');
    return (data['items'] as List? ?? [])
        .whereType<Map>()
        .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  static Future<void> saveConnector(
          String name, Map<String, dynamic> config) =>
      _postJson('/connectors', {'name': name, 'config': config});

  static Future<Map<String, dynamic>> callConnector(
          String name, Map<String, dynamic> params) =>
      _postJson('/connectors/$name/call', {'params': params});

  // ---------- 人设 / 会话 / 定时任务（多人设） ----------
  static Future<List<Map<String, dynamic>>> personas() async {
    final data = await getJson('/personas');
    return _asMaps(data['items']);
  }

  static Future<List<Map<String, dynamic>>> sessions({
    String persona = 'default',
    int limit = 30,
  }) async {
    final data =
        await getJson('/tasks/sessions', query: {'persona': persona, 'limit': '$limit'});
    return _asMaps(data['items']);
  }

  static Future<List<Map<String, dynamic>>> sessionMessages(
    String sessionId, {
    String persona = 'default',
    int limit = 80,
  }) async {
    final data = await getJson(
      '/tasks/sessions/$sessionId/messages',
      query: {'persona': persona, 'limit': '$limit'},
    );
    return _asMaps(data['items']);
  }

  /// 带翻页信息：has_more + 每条消息的 cursor（原样回传即取更早一页）。
  static Future<SessionMessagesPage> sessionMessagesPage(
    String sessionId, {
    String persona = 'default',
    int limit = 120,
    String? before,
  }) async {
    final query = {'persona': persona, 'limit': '$limit'};
    if (before != null && before.isNotEmpty) query['before'] = before;
    final data = await getJson(
      '/tasks/sessions/$sessionId/messages',
      query: query,
    );
    final total = data['total'];
    return SessionMessagesPage(
      items: _asMaps(data['items']),
      hasMore: data['has_more'] == true,
      total: total is num ? total.toInt() : null,
    );
  }

  static Future<List<Map<String, dynamic>>> routines({
    String persona = 'default',
  }) async {
    final data = await getJson('/routines', query: {'persona': persona});
    return _asMaps(data['items']);
  }

  static Future<Map<String, dynamic>> routine(
    String id, {
    String persona = 'default',
  }) async {
    final data = await getJson('/routines/$id', query: {'persona': persona});
    return Map<String, dynamic>.from((data['job'] as Map?) ?? {});
  }

  static Future<Map<String, dynamic>> updateRoutine(
    String id, {
    String persona = 'default',
    String? name,
    String? prompt,
    String? schedule,
    bool? enabled,
  }) =>
      _patchJson('/routines/$id?persona=$persona', {
        if (name != null) 'name': name,
        if (prompt != null) 'prompt': prompt,
        if (schedule != null) 'schedule': schedule,
        if (enabled != null) 'enabled': enabled,
      });

  // ---------- 记忆 / 画像 / 技能 ----------
  static Future<Map<String, dynamic>> memory({String persona = 'default'}) =>
      getJson('/memory', query: {'persona': persona});

  static Future<void> saveMemory({
    String persona = 'default',
    required String kind,
    required String content,
  }) async {
    await _postJson('/memory', {
      'persona': persona,
      'kind': kind,
      'content': content,
    });
  }

  static Future<List<Map<String, dynamic>>> skills({
    String persona = 'default',
  }) async {
    final data = await getJson('/skills', query: {'persona': persona});
    return _asMaps(data['items']);
  }

  static Future<Map<String, dynamic>> skill(
    String path, {
    String persona = 'default',
  }) =>
      getJson('/skills/${Uri.encodeComponent(path)}', query: {'persona': persona});

  static Future<void> saveSkill(
    String path, {
    String persona = 'default',
    required String content,
  }) async {
    await _postJson('/skills/${Uri.encodeComponent(path)}',
        {'persona': persona, 'content': content});
  }

  static Future<void> deleteSkill(
    String path, {
    String persona = 'default',
  }) async {
    final authToken = await token();
    if (authToken == null) throw Exception('尚未配对');
    final base = await baseUrl();
    final resp = await http
        .delete(
          Uri.parse('$base/skills/${Uri.encodeComponent(path)}')
              .replace(queryParameters: {'persona': persona}),
          headers: _headers(authToken),
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) throw Exception(_errText(resp));
  }

  // ==================== v1.20.0 新增 ====================

  static Future<Map<String, dynamic>> _deleteJson(String path) async {
    final authToken = await token();
    if (authToken == null) throw Exception('尚未配对');
    final base = await baseUrl();
    final resp = await http
        .delete(Uri.parse('$base$path'), headers: _headers(authToken))
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) throw Exception(_errText(resp));
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  /// 查询审计（谁、何时、查了什么）
  static Future<List<Map<String, dynamic>>> audit({
    int limit = 200,
    String? actor,
  }) async {
    final data = await getJson('/audit', query: {
      'limit': '$limit',
      if (actor != null && actor.isNotEmpty) 'actor': actor,
    });
    return _asMaps(data['items']);
  }

  /// 已配对设备
  static Future<List<Map<String, dynamic>>> devices() async {
    final data = await getJson('/query/devices');
    return _asMaps(data['items']);
  }

  /// 吊销设备
  static Future<void> revokeDevice(String id) => _deleteJson('/devices/$id');

  /// 今日会话摘要
  static Future<Map<String, dynamic>> sessionDigest({String? persona}) => getJson(
        '/tasks/sessions/digest',
        query: {if (persona != null) 'persona': persona},
      );

  /// 记忆库条目（zvec-memory/facts 下的 Markdown）
  static Future<List<Map<String, dynamic>>> vault({
    String persona = 'default',
    String q = '',
    int limit = 300,
  }) async {
    final data = await getJson('/memory/vault', query: {
      'persona': persona,
      'q': q,
      'limit': '$limit',
    });
    return _asMaps(data['items']);
  }

  /// 单条记忆全文
  static Future<String> vaultNote({
    required String persona,
    required String name,
  }) async {
    final data = await getJson('/memory/vault/note', query: {
      'persona': persona,
      'name': name,
    });
    return (data['content'] ?? '') as String;
  }

  /// 模型与候选池状态
  static Future<Map<String, dynamic>> agentModel({String persona = 'default'}) =>
      getJson('/agent/model', query: {'persona': persona});

  /// 切换到某个候选
  static Future<Map<String, dynamic>> switchModel({
    required String persona,
    required String candidate,
  }) =>
      _postJson('/agent/model/switch', {
        'persona': persona,
        'candidate': candidate,
      }, timeout: const Duration(seconds: 150));

  /// 只改主模型备注（同端点同模型，只重写 label）
  static Future<Map<String, dynamic>> setModelLabel({
    required String persona,
    required String baseUrl,
    required String model,
    required String label,
  }) =>
      _postJson('/agent/model/switch', {
        'persona': persona,
        'base_url': baseUrl,
        'model': model,
        'label': label,
        'provider': 'custom',
        'api_mode': 'chat_completions',
      }, timeout: const Duration(seconds: 150));

  /// 新增候选（scope=all 会同步三个人设）
  static Future<Map<String, dynamic>> addCandidate({
    required String persona,
    required String key,
    required String label,
    required String model,
    required String baseUrl,
    String provider = 'custom',
    String apiMode = 'chat_completions',
    String keyEnv = '',
    String newEnvValue = '',
    String scope = 'all',
  }) =>
      _postJson('/agent/candidates', {
        'persona': persona,
        'key': key,
        'label': label,
        'model': model,
        'base_url': baseUrl,
        'provider': provider,
        'api_mode': apiMode,
        if (keyEnv.isNotEmpty) 'key_env': keyEnv,
        if (newEnvValue.isNotEmpty) 'new_env_value': newEnvValue,
        'scope': scope,
      }, timeout: const Duration(seconds: 200));

  /// 局部更新候选
  static Future<Map<String, dynamic>> updateCandidate({
    required String persona,
    required String key,
    required Map<String, dynamic> fields,
  }) =>
      _patchJson('/agent/candidates/$key?persona=$persona', fields);

  /// 删除候选
  static Future<Map<String, dynamic>> deleteCandidate({
    required String persona,
    required String key,
  }) =>
      _deleteJson('/agent/candidates/$key?persona=$persona');

  /// 探活某个候选
  static Future<Map<String, dynamic>> testCandidate({
    required String persona,
    required String key,
  }) =>
      _postJson('/agent/candidates/$key/test', {'persona': persona},
          timeout: const Duration(seconds: 60));

  /// 探活当前主模型
  static Future<Map<String, dynamic>> testCurrentModel({String persona = 'default'}) =>
      _postJson('/agent/model/test', {'persona': persona},
          timeout: const Duration(seconds: 60));

  /// 保存备用链
  static Future<Map<String, dynamic>> saveFallback({
    required String persona,
    required List<Map<String, dynamic>> chain,
  }) =>
      _postJson('/agent/fallback', {'persona': persona, 'chain': chain},
          timeout: const Duration(seconds: 90));

  /// 凭据健康（只有变量名与来源，无值）
  static Future<List<Map<String, dynamic>>> credentials() async {
    final data = await getJson('/agent/credentials');
    return _asMaps(data['items']);
  }

  /// 插件清单
  static Future<List<Map<String, dynamic>>> plugins() async {
    final data = await getJson('/agent/plugins');
    return _asMaps(data['items']);
  }

  /// 用量统计
  static Future<Map<String, dynamic>> usage({String range = '7d'}) =>
      getJson('/usage/summary', query: {'range': range});

  /// 定时任务执行历史
  static Future<List<Map<String, dynamic>>> routineHistory({
    String persona = 'default',
    required String jobId,
    int limit = 20,
  }) async {
    final data = await getJson('/routines/$jobId/history', query: {
      'persona': persona,
      'limit': '$limit',
    });
    return _asMaps(data['items']);
  }

  /// 立即运行定时任务
  static Future<Map<String, dynamic>> runRoutine({
    required String persona,
    required String jobId,
  }) =>
      _postJson('/routines/$jobId/run', {'persona': persona},
          timeout: const Duration(seconds: 60));

  static List<Map<String, dynamic>> _asMaps(dynamic value) =>
      (value as List? ?? [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
}

/// 一页会话消息 + 是否还有更早的。
class SessionMessagesPage {
  const SessionMessagesPage({
    required this.items,
    required this.hasMore,
    this.total,
  });

  final List<Map<String, dynamic>> items;
  final bool hasMore;
  final int? total;
}
