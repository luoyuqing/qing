// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/device_hub/service_client.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'service_webview_page.dart';

/// 设置 →「服务」
///
/// 目录由服务端下发（以后新增服务 App 不用发版）；点卡片先向 hub 换一张
/// 60 秒一次性票据，再把票换成的入口 URL 交给内嵌 WebView 打开。
///
/// 分组（本机服务 / 外网服务）同样由服务端 catalog 的 `group` 字段决定，
/// 只有一组时不显示标签栏，保持旧版观感。
class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key});

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  late Future<List<ServiceItem>> _future;
  bool _busy = false;

  static const Map<String, String> _groupTitles = {
    'local': '本机服务',
    'web': '外网服务',
  };

  static const Map<String, String> _groupHints = {
    'local': '这些页面只在本机内网提供，公网入口由清助理用一次性票据临时打开，'
        '第三方直接访问会被拒绝。下拉可刷新目录。',
    'web': '外部网站收藏，点一下在当前窗口打开。内容保存在你自己的服务器上，'
        '同样只认得清助理的票据。下拉可刷新。',
  };

  @override
  void initState() {
    super.initState();
    _future = ServiceClient.catalog();
  }

  void _reload() {
    if (_busy) return;
    setState(() => _future = ServiceClient.catalog());
  }

  Future<void> _open(ServiceItem item) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final url = await ServiceClient.ticket(item.id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ServiceWebViewPage(
            title: item.name,
            hostname: item.hostname,
            url: url,
          ),
        ),
      );
    } on StateError catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('打开失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearSession() async {
    await WebViewCookieManager().clearCookies();
    _toast('服务登录态已清除，下次打开会重新换票');
  }

  String _titleOf(String group) => _groupTitles[group] ?? group;

  String _hintOf(String group) => _groupHints[group] ?? '下拉可刷新目录。';

  /// local 固定排第一，其余按服务端返回顺序，保证标签不会来回跳
  List<String> _groupOrder(Iterable<String> keys) {
    final list = keys.toList();
    return [
      ...list.where((k) => k == 'local'),
      ...list.where((k) => k != 'local'),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: qingPageBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: const Text('服务'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else ...[
            IconButton(
              tooltip: '刷新目录',
              icon: const Icon(Icons.refresh_outlined),
              onPressed: _reload,
            ),
            IconButton(
              tooltip: '清除服务登录态',
              icon: const Icon(Icons.logout_outlined),
              onPressed: _clearSession,
            ),
          ],
        ],
      ),
      body: FutureBuilder<List<ServiceItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _alwaysScrollable(_errorState(theme, '${snapshot.error}'));
          }

          final items = snapshot.data ?? const <ServiceItem>[];
          if (items.isEmpty) {
            return _alwaysScrollable(_emptyState(theme, '暂时没有可用服务'));
          }

          final groups = <String, List<ServiceItem>>{};
          for (final item in items) {
            groups.putIfAbsent(item.group, () => <ServiceItem>[]).add(item);
          }
          final keys = _groupOrder(groups.keys);

          // 只有一组：不显示标签栏，保持旧版观感
          if (keys.length == 1) {
            return _refreshable(keys.first, groups[keys.first]!);
          }

          return DefaultTabController(
            length: keys.length,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                  child: TabBar(
                    labelColor: theme.colorScheme.primary,
                    unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                    indicatorColor: theme.colorScheme.primary,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: Colors.transparent,
                    tabs: [
                      for (final key in keys)
                        Tab(text: _titleOf(key), height: 40),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final key in keys) _refreshable(key, groups[key]!),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _refreshable(String group, List<ServiceItem> items) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: _buildList(group, items),
    );
  }

  Widget _buildList(String group, List<ServiceItem> items) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        QingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _titleOf(group),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _hintOf(group),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Center(
              child: Text(
                group == 'web' ? '还没有收藏，点进「网页收藏夹」添加' : '这一组暂时没有服务',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: QingCard(
              onTap: _busy ? null : () => _open(item),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      item.iconData,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (item.desc.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            item.desc,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _errorState(ThemeData theme, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 42,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text('服务目录读取失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: _reload,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(ThemeData theme, String text) {
    return Center(
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _alwaysScrollable(Widget child) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [SizedBox(height: 180, child: child)],
      );
}
