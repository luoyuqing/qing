import 'package:fluffychat/utils/device_hub/device_hub_client.dart';
import 'package:flutter/material.dart';

/// 从端点拉模型列表并让用户选一个。
///
/// 失败时抛异常，由调用方 toast；用户取消返回 null。
Future<String?> pickEndpointModel(
  BuildContext context, {
  required String baseUrl,
  String keyEnv = '',
  String? current,
}) async {
  final data = await DeviceHubClient.endpointModels(
    baseUrl: baseUrl,
    keyEnv: keyEnv,
  );
  final models =
      ((data['models'] as List?) ?? const []).map((e) => '$e').toList();
  if (models.isEmpty) {
    throw Exception('该端点没有返回模型列表');
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                child: Row(
                  children: [
                    Text('选择模型（${models.length}）',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        baseUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 0.5),
              Expanded(
                child: ListView.builder(
                  itemCount: models.length,
                  itemBuilder: (context, i) => ListTile(
                    dense: true,
                    title: Text(models[i], style: theme.textTheme.bodySmall),
                    trailing: models[i] == current
                        ? Icon(Icons.check,
                            size: 16, color: theme.colorScheme.primary)
                        : null,
                    onTap: () => Navigator.pop(sheetContext, models[i]),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
