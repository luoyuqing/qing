import 'package:flutter/material.dart';

import '../../utils/device_hub/device_hub_client.dart';

/// 会话详情里的消息列表：第一屏取最近 120 条并停在最新一条，
/// 往上滑到顶自动再取更早的一页，直到翻完。
///
/// 服务端用 (timestamp, rowid) 复合游标翻页——同一秒可能有多条消息，
/// 只用时间戳会在边界漏消息，所以每条消息带回来的 `cursor` 要原样回传。
class SessionMessagesPane extends StatefulWidget {
  const SessionMessagesPane({
    super.key,
    required this.sessionId,
    required this.persona,
    required this.scrollController,
    required this.bubbleBuilder,
  });

  final String sessionId;
  final String persona;
  final ScrollController scrollController;
  final Widget Function(Map<String, dynamic>) bubbleBuilder;

  @override
  State<SessionMessagesPane> createState() => _SessionMessagesPaneState();
}

class _SessionMessagesPaneState extends State<SessionMessagesPane> {
  static const _pageSize = 120;
  static const _estimateRow = 96.0;

  final List<Map<String, dynamic>> _items = [];
  var _loading = true;
  var _loadingOlder = false;
  var _hasMore = false;
  var _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingOlder || _loading || _items.isEmpty) return;
    if (widget.scrollController.position.pixels < 160) _loadOlder();
  }

  Future<void> _load() async {
    try {
      final page = await DeviceHubClient.sessionMessagesPage(
        widget.sessionId,
        persona: widget.persona,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _hasMore = page.hasMore;
        _total = page.total ?? page.items.length;
        _loading = false;
      });
      // 停在最新一条，往上滑才翻更早的
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _jumpToBottom() {
    if (!widget.scrollController.hasClients) return;
    final pos = widget.scrollController.position;
    if (pos.maxScrollExtent > 0) {
      widget.scrollController.jumpTo(pos.maxScrollExtent);
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore || _items.isEmpty) return;
    setState(() => _loadingOlder = true);
    try {
      final before = _items.first['cursor'] as String?;
      final page = await DeviceHubClient.sessionMessagesPage(
        widget.sessionId,
        persona: widget.persona,
        limit: _pageSize,
        before: before,
      );
      if (!mounted) return;
      final added = page.items.length;
      final offset = widget.scrollController.hasClients
          ? widget.scrollController.offset
          : 0.0;
      setState(() {
        _items.insertAll(0, page.items);
        _hasMore = page.hasMore && added > 0;
        if (page.total != null) _total = page.total!;
        _loadingOlder = false;
      });
      if (added > 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!widget.scrollController.hasClients) return;
          final pos = widget.scrollController.position;
          widget.scrollController.jumpTo(
            (offset + added * _estimateRow).clamp(0.0, pos.maxScrollExtent),
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingOlder = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('读取失败：$_error', style: theme.textTheme.bodySmall),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Expanded(
        child: Center(
          child: Text(
            '这段会话没有可展示的文字记录',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }
    return Expanded(
      child: ListView.builder(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _items.length + 1,
        itemBuilder: (context, i) {
          if (i == 0) return _header(theme);
          return widget.bubbleBuilder(_items[i - 1]);
        },
      ),
    );
  }

  Widget _header(ThemeData theme) {
    final shown = _items.length;
    final total = _total > shown ? _total : shown;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(Icons.forum_outlined,
              size: 13, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            '已显示 $shown / 共 $total 条',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          if (_loadingOlder)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            )
          else if (_hasMore)
            GestureDetector(
              onTap: _loadOlder,
              child: Text(
                '加载更早',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            Text(
              '已是最早一条',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
        ],
      ),
    );
  }
}
