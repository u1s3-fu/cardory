// 附件列表行组件。

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';

/// 附件行：展示文件名、类型、大小、日期、分类与备注，
/// 并在非批量模式下提供操作菜单。
class AttachmentRow extends StatelessWidget {
  const AttachmentRow({
    super.key,
    required this.attachment,
    required this.categoryNamesById,
    required this.selected,
    required this.batchMode,
    required this.enabled,
    required this.onToggleSelect,
    required this.onEditNote,
    required this.onRename,
    required this.onEditCategories,
    required this.onExport,
    required this.onRemove,
    this.onLinkAssetRequest,
    this.onUnlinkAsset,
  });

  final AttachmentData attachment;
  final Map<String, String> categoryNamesById;
  final bool selected;
  final bool batchMode;
  final bool enabled;
  final VoidCallback onToggleSelect;
  final Future<void> Function(AttachmentData attachment) onEditNote;
  final Future<void> Function(AttachmentData attachment) onRename;
  final Future<void> Function(AttachmentData attachment) onEditCategories;
  final Future<void> Function(AttachmentData attachment)? onExport;
  final Future<void> Function(AttachmentData attachment) onRemove;

  /// 关联/解除关联同项目资产；未传时菜单不出现对应入口。
  /// [onLinkAssetRequest] 只表示用户发起关联，资产选择器由面板负责弹出。
  final void Function(AttachmentData attachment)? onLinkAssetRequest;
  final void Function(AttachmentData attachment)? onUnlinkAsset;

  void _handleAction(AttachmentRowAction action) {
    switch (action) {
      case AttachmentRowAction.editNote:
        onEditNote(attachment);
        break;
      case AttachmentRowAction.rename:
        onRename(attachment);
        break;
      case AttachmentRowAction.editCategories:
        onEditCategories(attachment);
        break;
      case AttachmentRowAction.export:
        onExport?.call(attachment);
        break;
      case AttachmentRowAction.linkAsset:
        onLinkAssetRequest?.call(attachment);
        break;
      case AttachmentRowAction.unlinkAsset:
        onUnlinkAsset?.call(attachment);
        break;
      case AttachmentRowAction.remove:
        onRemove(attachment);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryNames = <String>[
      for (final id in attachment.categoryIds)
        if (categoryNamesById[id] case final name?) name,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (batchMode) ...[
          Checkbox(
            value: selected,
            onChanged: enabled ? (_) => onToggleSelect() : null,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
        ],
        Icon(_iconFor(attachment.kind), color: CardoryColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                attachment.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    label: Text(attachment.kind.label),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  if (attachment.fileExtension.isNotEmpty)
                    Text(attachment.fileExtension.toUpperCase()),
                  Text(formatFileSize(attachment.size)),
                  Text(formatDate(attachment.createdAt)),
                ],
              ),
              if (categoryNames.isNotEmpty) ...[
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final name in categoryNames)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: CardoryColors.primarySoft,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          name,
                          style: TextStyle(
                            color: CardoryColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (attachment.note.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  attachment.note,
                  style: TextStyle(color: CardoryColors.gray500, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        if (!batchMode)
          PopupMenuButton<AttachmentRowAction>(
            tooltip: '更多附件操作',
            enabled: enabled,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: _handleAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: AttachmentRowAction.editNote,
                child: ListTile(
                  leading: Icon(Icons.edit_note_outlined),
                  title: Text('编辑备注'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: AttachmentRowAction.rename,
                child: ListTile(
                  leading: Icon(Icons.drive_file_rename_outline),
                  title: Text('重命名'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: AttachmentRowAction.editCategories,
                child: ListTile(
                  leading: Icon(Icons.label_outline_rounded),
                  title: Text('编辑分类'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (onExport != null)
                const PopupMenuItem(
                  value: AttachmentRowAction.export,
                  child: ListTile(
                    leading: Icon(Icons.download_outlined),
                    title: Text('导出附件'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (onLinkAssetRequest != null)
                const PopupMenuItem(
                  value: AttachmentRowAction.linkAsset,
                  child: ListTile(
                    leading: Icon(Icons.add_link),
                    title: Text('关联资产…'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              if (onUnlinkAsset != null && attachment.assetId != null)
                const PopupMenuItem(
                  value: AttachmentRowAction.unlinkAsset,
                  child: ListTile(
                    leading: Icon(Icons.link_off),
                    title: Text('解除关联'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: AttachmentRowAction.remove,
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('删除附件'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

enum AttachmentRowAction {
  editNote,
  rename,
  editCategories,
  export,
  linkAsset,
  unlinkAsset,
  remove,
}

IconData _iconFor(AttachmentKind kind) => switch (kind) {
  AttachmentKind.image => Icons.image_outlined,
  AttachmentKind.document => Icons.description_outlined,
  AttachmentKind.archive => Icons.folder_zip_outlined,
  AttachmentKind.other => Icons.insert_drive_file_outlined,
};
