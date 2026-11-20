// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/utils/device_hub/service_client.dart';
import 'package:fluffychat/widgets/qing_bottom_nav.dart';
import 'package:fluffychat/widgets/qing_style.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'service_webview_page.dart';

/// 设置 →「服务」
///
/// 目录由服务端下发（以后新增服务 App 不用发版）；点卡片先向 hub 换一张
/// 60 秒一次性票据，再把票换成的入口 URL 交给内嵌 WebView 打开。
///
/// 分组由服务端 catalog 的 `group` 字段决定：
///  - local：本机服务，卡片列表，可拖动排序（顺序存服务端 settings）
///  - web + type=bookmarks：外网收藏，直接渲染原生列表，可拖动排序
///
/// 只有一组时隐藏标签栏，保持旧版观感。
class ServicesPage extends StatefulWidget {
  const ServicesPage({super.key, this.showBottomNav = false});

  /// 作为底部导航「服务」tab 的根页面时为 true：
  /// 显示底部导航、隐藏 AppBar 返回箭头。
  final bool showBottomNav;

  @override
  State<ServicesPage> createState() => _ServicesPageState();
}

class _ServicesPageState extends State<ServicesPage> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<ServiceItem> _items = const [];
  List<FavItem> _favs = const [];

  static const Map<String, String> _groupTitles = {
    'local': '本机服务',
    'web': '外网服务',
  };

  static const Map<String, String> _groupHints = {
    'local': '这些页面只在本机内网提供，公网入口由清助理用一次性票据临时打开，'
        '第三方直接访问会被拒绝。长按右侧手柄可调整顺序。',
    'web': '外部网站收藏，点一下在当前窗口打开。长按右侧手柄可调整顺序，'
        '删除后不可恢复。',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await ServiceClient.catalog();
      List<FavItem> favs = const <FavItem>[];
      if (items.any((i) => i.group == 'web' && i.type == 'bookmarks')) {
        favs = await ServiceClient.favList();
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _favs = favs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<ServiceItem> get _localItems =>
      _items.where((i) => i.group == 'local').toList();

  bool get _hasBookmarks =>
      _items.any((i) => i.group == 'web' && i.type == 'bookmarks');

  List<ServiceItem> get _webCards =>
      _items.where((i) => i.group == 'web' && i.type != 'bookmarks').toList();

  Future<void> _openService(ServiceItem item) async {
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

  Future<void> _openFav(FavItem fav) async {
    final uri = fav.uri;
    if (uri == null) {
      _toast('网址格式不对');
      return;
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      _toast('只支持 http / https 网址');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServiceWebViewPage(
          title: fav.name,
          hostname: uri.host,
          url: fav.url,
          allowExternal: true,
        ),
      ),
    );
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

  // ---------- 排序 ----------
  void _reorderLocal(int oldIndex, int newIndex) {
    final list = _localItems;
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    setState(() {
      _items = [
        ...list,
        ..._items.where((i) => i.group != 'local'),
      ];
    });
    unawaited(
      ServiceClient.saveLocalOrder(list.map((e) => e.id).toList()).catchError(
        (Object e) => _toast('排序保存失败：$e'),
      ),
    );
  }

  void _reorderFav(int oldIndex, int newIndex) {
    final list = [..._favs];
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    setState(() => _favs = list);
    unawaited(
      ServiceClient.favOrder(list.map((e) => e.id).toList()).catchError(
        (Object e) => _toast('排序保存失败：$e'),
      ),
    );
  }

  // ---------- 收藏增删 ----------
  Future<void> _addFav() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加网址'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: '名称（可留空）',
                hintText: '例如：GitHub',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(
                labelText: '网址',
                hintText: 'github.com',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    final name = nameCtrl.text;
    final url = urlCtrl.text;
    nameCtrl.dispose();
    urlCtrl.dispose();
    if (ok != true) return;
    if (url.trim().isEmpty) {
      _toast('网址不能为空');
      return;
    }
    setState(() => _busy = true);
    try {
      final item = await ServiceClient.favAdd(name: name, url: url);
      if (!mounted) return;
      setState(() => _favs = [..._favs, item]);
      _toast('已添加');
    } catch (e) {
      _toast('添加失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteFav(FavItem fav) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除收藏'),
        content: Text('确定删除「${fav.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ServiceClient.favDel(fav.id);
      if (!mounted) return;
      setState(() => _favs = _favs.where((f) => f.id != fav.id).toList());
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: qingPageBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: !widget.showBottomNav,
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
              onPressed: _load,
            ),
            IconButton(
              tooltip: '清除服务登录态',
              icon: const Icon(Icons.logout_outlined),
              onPressed: _clearSession,
            ),
          ],
        ],
      ),
      body: _buildBody(theme),
      bottomNavigationBar:
          widget.showBottomNav ? const QingBottomNav(currentIndex: 3) : null,
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: _errorState(theme, _error!));
    }

    final tabs = <({String title, Widget child})>[
      (title: _groupTitles['local']!, child: _buildLocalTab()),
      if (_hasBookmarks)
        (title: _groupTitles['web']!, child: _buildFavTab()),
    ];

    if (tabs.length == 1) return tabs.first.child;

    return DefaultTabController(
      length: tabs.length,
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
                for (final t in tabs) Tab(text: t.title, height: 40),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [for (final t in tabs) t.child],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalTab() {
    final items = _localItems;
    return RefreshIndicator(
      onRefresh: _load,
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        header: _sectionHeader('local', extraBottom: 16),
        itemCount: items.length,
        buildDefaultDragHandles: false,
        onReorder: _reorderLocal,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            key: ValueKey('svc-${item.id}'),
            padding: const EdgeInsets.only(bottom: 12),
            child: _serviceCard(item, index),
          );
        },
      ),
    );
  }

  Widget _serviceCard(ServiceItem item, int index, {bool showHandle = true}) {
    final theme = Theme.of(context);
    return QingCard(
      onTap: _busy ? null : () => _openService(item),
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
          Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          if (showHandle)
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.drag_handle,
                  size: 20,
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFavTab() {
    final favs = _favs;
    final cards = _webCards;
    return RefreshIndicator(
      onRefresh: _load,
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        header: Column(
          children: [
            _sectionHeader('web', extraBottom: 12),
            if (cards.isNotEmpty) ...[
              for (final item in cards)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _serviceCard(item, 0, showHandle: false),
                ),
            ],
            if (favs.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 28, bottom: 20),
                child: Column(
                  children: [
                    Icon(
                      Icons.bookmarks_outlined,
                      size: 40,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '还没有收藏，点上面「添加网址」存第一个',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        itemCount: favs.length,
        buildDefaultDragHandles: false,
        onReorder: _reorderFav,
        itemBuilder: (context, index) {
          final fav = favs[index];
          return Padding(
            key: ValueKey('fav-${fav.id}'),
            padding: const EdgeInsets.only(bottom: 10),
            child: _favCard(fav, index),
          );
        },
      ),
    );
  }

  Widget _favCard(FavItem fav, int index) {
    final theme = Theme.of(context);
    return QingCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      onTap: () => _openFav(fav),
      child: Row(
        children: [
          _FavIcon(fav: fav, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fav.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  fav.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '删除',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close,
              size: 18,
              color: theme.colorScheme.outline,
            ),
            onPressed: () => _deleteFav(fav),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.drag_handle,
                size: 20,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String group, {double extraBottom = 16}) {
    final theme = Theme.of(context);
    return Column(
      children: [
        QingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _groupTitles[group] ?? group,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                _groupHints[group] ?? '',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (group == 'web') ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _busy ? null : _addFav,
              icon: const Icon(Icons.add),
              label: const Text('添加网址'),
            ),
          ),
        ],
        SizedBox(height: extraBottom),
      ],
    );
  }

  Widget _errorState(ThemeData theme, String message) {
    return Padding(
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
          FilledButton.tonal(onPressed: _load, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// 收藏图标：emoji > https 站点 favicon > 首字母色块
class _FavIcon extends StatelessWidget {
  const _FavIcon({required this.fav, this.size = 38});

  final FavItem fav;
  final double size;

  static const List<Color> _palette = [
    Color(0xFF4C6EF5),
    Color(0xFF12B886),
    Color(0xFFF76707),
    Color(0xFFAE3EC9),
    Color(0xFF1098AD),
    Color(0xFFD6336C),
    Color(0xFF5F3DC4),
  ];

  Color get _color {
    var h = 0;
    for (final c in fav.host.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return _palette[h % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(11);
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: _color, borderRadius: radius),
      alignment: Alignment.center,
      child: Text(
        fav.initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.4,
        ),
      ),
    );

    if (fav.icon.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: radius,
        ),
        alignment: Alignment.center,
        child: Text(fav.icon, style: TextStyle(fontSize: size * 0.46)),
      );
    }

    final uri = fav.uri;
    if (uri == null || uri.scheme != 'https') return fallback;

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          color: theme.colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.all(7),
          child: Image.network(
            'https://${uri.host}/favicon.ico',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Center(
              child: Text(
                fav.initial,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: size * 0.36,
                ),
              ),
            ),
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
