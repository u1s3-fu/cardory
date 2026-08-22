import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';

/// 资产详情对话框：展示资产字段、标签与变动记录。
class AssetDetailDialog extends StatelessWidget {
  const AssetDetailDialog({
    super.key,
    required this.asset,
    this.assetTags = const [],
  });

  final AssetData asset;
  final List<AssetTag> assetTags;

  @override
  Widget build(BuildContext context) {
    final isSoftware = asset.type == AssetType.software;
    final tagById = {for (final tag in assetTags) tag.id: tag.name};
    final tagNames = [
      for (final id in asset.tagIds)
        if (tagById[id] case final name?) name,
    ];
    return AlertDialog(
      title: Row(
        children: [
          Icon(isSoftware ? Icons.apps_outlined : Icons.dns_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text(asset.name)),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Chip(label: Text(isSoftware ? '软件资产' : '硬件资产')),
              if (tagNames.isNotEmpty) _AssetDetailRow(
                label: '标签',
                value: tagNames.join('、'),
              ),
              const SizedBox(height: 12),
              if (isSoftware) ...[
                _AssetDetailRow(label: '版本', value: asset.version),
                _AssetDetailRow(label: '端口', value: asset.port),
                _AssetDetailRow(label: '路径', value: asset.path),
              ] else ...[
                _AssetDetailRow(label: '服务器类型', value: asset.serverType),
                _AssetDetailRow(label: '服务器序列号', value: asset.serialNumber),
                _AssetDetailRow(label: '网络', value: asset.network),
              ],
              _AssetDetailRow(label: '登录用户名', value: asset.username),
              _AssetDetailRow(
                label: '登录密码',
                value: asset.password.isEmpty
                    ? ''
                    : '•' * asset.password.length,
              ),
              _AssetDetailRow(label: '备注 / 用途', value: asset.note),
              const SizedBox(height: 8),
              Text('变动记录', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              if (asset.activities.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '暂无变动记录',
                    style: TextStyle(color: CardoryColors.gray500),
                  ),
                )
              else
                for (final activity in asset.activities)
                  _AssetActivityRow(activity: activity),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          key: const Key('edit-asset-button'),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('编辑资产'),
        ),
      ],
    );
  }
}

class _AssetActivityRow extends StatelessWidget {
  const _AssetActivityRow({required this.activity});

  final AssetActivity activity;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (activity.kind) {
      AssetActivityKind.created => (
        Icons.add_circle_outline_rounded,
        cardoryEnsureWhiteContrast(CardoryColors.success, minRatio: 3),
      ),
      AssetActivityKind.updated => (Icons.edit_outlined, CardoryColors.primary),
      AssetActivityKind.deleted => (
        Icons.delete_outline_rounded,
        cardoryEnsureWhiteContrast(CardoryColors.error, minRatio: 3),
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.message,
                  style: TextStyle(
                    color: CardoryColors.gray700,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDateTime(activity.timestamp),
                  style: TextStyle(
                    color: CardoryColors.gray500,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetDetailRow extends StatelessWidget {
  const _AssetDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        Text(value.isEmpty ? '未填写' : value),
      ],
    ),
  );
}
