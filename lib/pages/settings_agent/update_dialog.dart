// SPDX-FileCopyrightText: 2026 Qing
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/app_update_service.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// 检查更新对话框
///
/// 打开即自动检查；hub 与 GitHub 各 5 秒上限，失败给出明确原因并可重试，
/// 不会让界面长时间停在转圈上。
class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _loading = true;
  String? _error;
  AppUpdateInfo? _info;
  String _current = '';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    final current = await AppUpdateService.currentVersion();
    final result = await AppUpdateService.check(manual: true);
    if (!mounted) return;
    setState(() {
      _current = current;
      _loading = false;
      _info = result.info;
      _error = result.ok ? null : (result.error ?? '未知错误');
    });
  }

  Future<void> _download() async {
    final url = _info?.apkUrl ?? '';
    if (url.isEmpty) {
      final html = _info?.htmlUrl ?? '';
      if (html.isNotEmpty) await launchUrlString(html);
      return;
    }
    await launchUrlString(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update_alt_rounded,
              size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('检查更新'),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: _loading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '正在查询最新版本…',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              )
            : _buildResult(theme),
      ),
      actions: _loading
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ]
          : _buildActions(),
    );
  }

  Widget _buildResult(ThemeData theme) {
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('检查失败', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '当前版本 $_current。可稍后重试，或在浏览器打开项目主页手动下载。',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    final info = _info;
    if (info == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('已是最新版本', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            '当前版本 $_current',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    final notes = _trimNotes(info.notes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'v${info.version}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (info.sizeText.isNotEmpty)
              Text(
                info.sizeText,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '当前版本 $_current',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: SingleChildScrollView(
              child: Text(
                notes,
                style: theme.textTheme.bodySmall?.copyWith(height: 1.6),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildActions() {
    if (_error != null) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton.tonal(onPressed: _check, child: const Text('重试')),
      ];
    }
    if (_info == null) {
      return [
        TextButton(
          onPressed: _check,
          child: const Text('再检查一次'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('好'),
        ),
      ];
    }
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('稍后'),
      ),
      FilledButton(
        onPressed: _download,
        child: const Text('下载'),
      ),
    ];
  }

  /// 更新说明只留前若干行，避免弹窗被长文撑爆
  String _trimNotes(String raw) {
    if (raw.trim().isEmpty) return '';
    final lines = raw
        .split('\n')
        .where((l) => !l.trim().startsWith('<!--'))
        .where((l) => l.trim().isNotEmpty)
        .take(12)
        .toList();
    return lines.join('\n');
  }
}

/// 统一的调用入口
Future<void> showUpdateDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const UpdateDialog(),
    );
