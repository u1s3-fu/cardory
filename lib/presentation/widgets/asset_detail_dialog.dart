import 'package:flutter/material.dart';

import '../../domain/asset_template.dart';
import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import 'credential_row.dart';

/// 资产详情对话框：展示资产字段、标签、关联附件与变动记录。
///
/// 传入 [template] 时按模板字段渲染自定义字段；为 null 时回退旧的
/// software/hardware 分支渲染（保底兼容旧调用点）。
class AssetDetailDialog extends StatelessWidget {
  const AssetDetailDialog({
    super.key,
    required this.asset,
    this.assetTags = const [],
    this.template,
    this.attachments = const [],
    this.onLinkAttachment,
    this.onUnlinkAttachment,
  });

  final AssetData asset;
  final List<AssetTag> assetTags;

  /// 资产所属模板；null 时回退旧类型分支渲染。
  final AssetTemplate? template;

  /// 当前项目全部附件；仅展示 assetId 匹配本资产的行。
  final List<AttachmentData> attachments;

  /// 关联/解除关联回调；未传时附件区只读展示。
  final void Function(AttachmentData attachment)? onLinkAttachment;
  final void Function(AttachmentData attachment)? onUnlinkAttachment;

  @override
  Widget build(BuildContext context) {
    final isSoftware = asset.type == AssetType.software;
    final template = this.template;
    // 读时归一化：补齐 templateId 并从旧顶层键回填 customFields。
    final normalized = normalizeAssetTemplate(asset, [
      if (template != null) template,
      ...builtInAssetTemplates(),
    ]);
    final tagById = {for (final tag in assetTags) tag.id: tag.name};
    final tagNames = [
      for (final id in asset.tagIds)
        if (tagById[id] case final name?) name,
    ];
    final linkedAttachments = attachments
        .where((a) => a.assetId == asset.id)
        .toList(growable: false);
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
              if (tagNames.isNotEmpty)
                _AssetDetailRow(label: '标签', value: tagNames.join('、')),
              const SizedBox(height: 12),
              if (template case final AssetTemplate assetTemplate?)
                for (final field in assetTemplate.fields)
                  _AssetDetailRow(
                    label: field.label,
                    value: normalized.customFields[field.key] ?? '',
                  )
              else if (isSoftware) ...[
                _AssetDetailRow(label: '版本', value: asset.version),
                _AssetDetailRow(label: '端口', value: asset.port),
                _AssetDetailRow(label: '路径', value: asset.path),
              ] else ...[
                _AssetDetailRow(label: '服务器类型', value: asset.serverType),
                _AssetDetailRow(label: '服务器序列号', value: asset.serialNumber),
                _AssetDetailRow(label: '网络', value: asset.network),
              ],
              CredentialRow(
                label: '登录用户名',
                value: asset.username,
                onCopied: (_) => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板'))),
              ),
              CredentialRow(
                label: '登录密码',
                value: asset.password,
                secret: true,
                onCopied: (_) => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已复制到剪贴板'))),
              ),
              _AssetDetailRow(label: '备注 / 用途', value: asset.note),
              const SizedBox(height: 8),
              Text('关联附件', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              if (linkedAttachments.isEmpty)
                Text('暂无关联附件', style: TextStyle(color: CardoryColors.gray500))
              else
                for (final att in linkedAttachments)
                  Row(
                    children: [
                      const Icon(Icons.insert_drive_file_outlined, size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: Text(att.fileName)),
                      if (onUnlinkAttachment != null)
                        IconButton(
                          key: Key('unlink-attachment-${att.id}'),
                          icon: const Icon(Icons.link_off, size: 18),
                          tooltip: '解除关联',
                          onPressed: () => onUnlinkAttachment!(att),
                        ),
                    ],
                  ),
              if (onLinkAttachment != null)
                TextButton.icon(
                  key: const Key('link-attachment-button'),
                  onPressed: () async {
                    final candidates = attachments
                        .where((a) => a.assetId == null)
                        .toList(growable: false);
                    if (candidates.isEmpty) return;
                    final selected = await showDialog<AttachmentData>(
                      context: context,
                      builder: (context) => SimpleDialog(
                        title: const Text('选择要关联的附件'),
                        children: [
                          for (final candidate in candidates)
                            SimpleDialogOption(
                              key: Key('link-option-${candidate.id}'),
                              onPressed: () =>
                                  Navigator.pop(context, candidate),
                              child: Text(candidate.fileName),
                            ),
                        ],
                      ),
                    );
                    if (selected != null) onLinkAttachment!(selected);
                  },
                  icon: const Icon(Icons.add_link, size: 16),
                  label: const Text('关联附件'),
                ),
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
