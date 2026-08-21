import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../application/attachment_repository.dart';
import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import '../widgets/section_title.dart';

class ProjectAttachmentsPanel extends StatefulWidget {
  const ProjectAttachmentsPanel({
    super.key,
    required this.attachments,
    required this.categories,
    required this.onChanged,
    this.repository,
    this.renameOnUpload = true,
    this.keepExtensionOnRename = false,
  });

  final List<AttachmentData> attachments;
  final List<AttachmentCategory> categories;
  final Future<void> Function(
    List<AttachmentData> attachments,
    List<AttachmentCategory> categories,
  ) onChanged;
  final AttachmentRepository? repository;
  final bool renameOnUpload;
  final bool keepExtensionOnRename;

  @override
  State<ProjectAttachmentsPanel> createState() =>
      _ProjectAttachmentsPanelState();
}

class _ProjectAttachmentsPanelState extends State<ProjectAttachmentsPanel> {
  bool _busy = false;
  final Set<String> _selectedIds = {};
  String? _filterCategoryId;
  bool _grouped = false;
  final Set<String> _collapsedGroups = {};

  List<AttachmentData> get _filteredAttachments {
    final filter = _filterCategoryId;
    if (filter == null) return List.of(widget.attachments);
    return widget.attachments
        .where((attachment) => attachment.categoryIds.contains(filter))
        .toList();
  }

  List<AttachmentData> get _selectedAttachments =>
      widget.attachments.where((item) => _selectedIds.contains(item.id)).toList();

  Future<void> _pickFiles() async {
    final repository = widget.repository;
    if (repository == null) {
      _showError('附件存储尚未初始化，请重新打开应用后再试。');
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
      withData: false,
    );
    if (result == null || !mounted) return;

    setState(() => _busy = true);
    final imported = <AttachmentData>[];
    var handedToWorkspace = false;
    try {
      for (final file in result.files) {
        final sourcePath = file.path;
        if (sourcePath == null || sourcePath.isEmpty) {
          throw StateError('当前平台无法访问所选文件路径。');
        }
        imported.add(
          await repository.importFile(
            sourcePath: sourcePath,
            id: newId(),
            fileName: file.name,
          ),
        );
      }
      handedToWorkspace = true;
      if (widget.renameOnUpload) {
        final renames = await _promptBatchRename(imported);
        if (renames != null && renames.isNotEmpty) {
          for (var index = 0; index < imported.length; index++) {
            final newName = renames[imported[index].id];
            if (newName != null && newName != imported[index].fileName) {
              imported[index] = imported[index].copyWith(fileName: newName);
            }
          }
        }
      }
      await _change(
        attachments: [...widget.attachments, ...imported],
      );
    } catch (error) {
      debugPrint('Failed to import project attachments: $error');
      if (!handedToWorkspace) {
        for (final attachment in imported) {
          await repository.delete(attachment).onError((_, _) {});
        }
      }
      if (mounted) {
        _showError('无法添加附件，请检查文件是否仍可访问后重试。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, String>?> _promptBatchRename(
    List<AttachmentData> files,
  ) => showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _BatchRenameDialog(
      files: files,
      keepExtension: widget.keepExtensionOnRename,
    ),
  );

  Future<void> _export(AttachmentData attachment) async {
    final repository = widget.repository;
    if (repository == null) return;
    try {
      final target = await FilePicker.platform.saveFile(
        dialogTitle: '导出附件',
        fileName: attachment.fileName,
      );
      if (target == null) return;
      await repository.exportFile(attachment, target);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('附件已解密导出。')));
      }
    } catch (error) {
      debugPrint('Failed to export project attachment: $error');
      if (mounted) {
        _showError('无法导出附件，请检查目标路径和可用空间后重试。');
      }
    }
  }

  Future<void> _batchExport() async {
    final repository = widget.repository;
    if (repository == null) return;
    final selected = _selectedAttachments;
    if (selected.isEmpty) return;
    String? directory;
    try {
      directory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择导出目录',
      );
    } catch (_) {
      directory = null;
    }
    if (directory == null) {
      if (mounted) {
        _showError('当前平台不支持选择导出目录，请使用单个附件导出。');
      }
      return;
    }
    setState(() => _busy = true);
    var exported = 0;
    try {
      for (final attachment in selected) {
        await repository.exportFile(
          attachment,
          path.join(directory, attachment.fileName),
        );
        exported++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出 $exported 个附件。')),
        );
      }
    } catch (error) {
      debugPrint('Failed to batch export project attachments: $error');
      if (mounted) {
        _showError('批量导出失败，请检查目标目录和可用空间后重试。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editNote(AttachmentData attachment) async {
    final controller = TextEditingController(text: attachment.note);
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('附件备注'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null || note == attachment.note) return;
    await _change(
      attachments: widget.attachments
          .map(
            (item) => item.id == attachment.id ? item.copyWith(note: note) : item,
          )
          .toList(),
    );
  }

  Future<void> _renameOne(AttachmentData attachment) async {
    final keepExtension = widget.keepExtensionOnRename;
    final controller = TextEditingController(
      text: keepExtension
          ? _stripExtension(attachment.fileName)
          : attachment.fileName,
    );
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名附件'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: keepExtension ? '文件名（扩展名保留）' : '文件名',
            helperText: keepExtension
                ? '仅修改文件名主体，原扩展名保持不变'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final newName = keepExtension
        ? _applyRenameKeepingExtension(name, attachment.fileName)
        : name;
    if (newName == attachment.fileName) return;
    await _change(
      attachments: widget.attachments
          .map(
            (item) => item.id == attachment.id ? item.copyWith(fileName: newName) : item,
          )
          .toList(),
    );
  }

  Future<void> _editCategoriesOne(AttachmentData attachment) async {
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _CategoryAssignDialog(
        categories: widget.categories,
        initialIds: attachment.categoryIds.toSet(),
      ),
    );
    if (selected == null || !mounted) return;
    await _change(
      attachments: widget.attachments
          .map(
            (item) => item.id == attachment.id
                ? item.copyWith(
                    categoryIds: selected.toList(),
                    clearCategoryIds: selected.isEmpty,
                  )
                : item,
          )
          .toList(),
    );
  }

  Future<void> _batchAssignCategories() async {
    final selectedAttachments = _selectedAttachments;
    if (selectedAttachments.isEmpty) return;
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _CategoryAssignDialog(
        categories: widget.categories,
        initialIds: const {},
      ),
    );
    if (selected == null || !mounted) return;
    final ids = _selectedIds.toSet();
    await _change(
      attachments: widget.attachments
          .map(
            (item) => ids.contains(item.id)
                ? item.copyWith(
                    categoryIds: selected.toList(),
                    clearCategoryIds: selected.isEmpty,
                  )
                : item,
          )
          .toList(),
    );
    if (mounted) setState(() => _selectedIds.clear());
  }

  Future<void> _remove(AttachmentData attachment) async {
    final repository = widget.repository;
    try {
      await repository?.delete(attachment);
    } catch (error) {
      debugPrint('Failed to delete attachment file: $error');
    }
    await _change(
      attachments: widget.attachments
          .where((item) => item.id != attachment.id)
          .toList(),
    );
    if (mounted) setState(() => _selectedIds.remove(attachment.id));
  }

  Future<void> _batchRemove() async {
    final selected = _selectedAttachments;
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除附件'),
        content: Text(
          '确定删除选中的 ${selected.length} 个附件吗？附件文件将从本地存储中移除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: CardoryColors.error,
              foregroundColor: CardoryColors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repository = widget.repository;
    final ids = _selectedIds.toSet();
    setState(() => _busy = true);
    try {
      for (final attachment in widget.attachments.where(
        (item) => ids.contains(item.id),
      )) {
        await repository?.delete(attachment);
      }
      await _change(
        attachments: widget.attachments
            .where((item) => !ids.contains(item.id))
            .toList(),
      );
      if (mounted) setState(() => _selectedIds.clear());
    } catch (error) {
      debugPrint('Failed to batch delete project attachments: $error');
      if (mounted) _showError('删除附件失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manageCategories() async {
    final result = await showDialog<_CategoryManagerResult>(
      context: context,
      builder: (_) => _CategoryManagerDialog(
        categories: widget.categories,
        attachments: widget.attachments,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _collapsedGroups.removeAll(result.removedIds);
      if (result.removedIds.contains(_filterCategoryId)) {
        _filterCategoryId = null;
      }
    });
    await _change(
      attachments: result.attachments,
      categories: result.categories,
    );
  }

  Future<void> _change({
    required List<AttachmentData> attachments,
    List<AttachmentCategory>? categories,
  }) async {
    setState(() => _busy = true);
    try {
      await widget.onChanged(attachments, categories ?? widget.categories);
    } catch (error) {
      debugPrint('Failed to update project attachments: $error');
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('附件更新失败'),
            content: const Text('附件更新失败，请稍后重试。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
      }
      if (mounted) _showError('附件更新失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleSelect(String id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAttachments;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SectionTitle(
                  title: '项目附件',
                  subtitle: '${widget.attachments.length} 个文件 · '
                      '${widget.categories.length} 个分类',
                ),
              ),
              IconButton(
                key: const Key('manage-attachment-categories-button'),
                tooltip: '管理分类',
                onPressed: _busy ? null : _manageCategories,
                icon: const Icon(Icons.label_outline_rounded),
              ),
              IconButton(
                key: const Key('toggle-attachment-batch-button'),
                tooltip: _selectedIds.isEmpty ? '批量操作' : '取消选择',
                onPressed: _busy
                    ? null
                    : () => setState(() => _selectedIds.clear()),
                icon: Icon(
                  _selectedIds.isEmpty
                      ? Icons.checklist_rounded
                      : Icons.close_rounded,
                  color: _selectedIds.isEmpty
                      ? null
                      : CardoryColors.primary,
                ),
              ),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.view_list_outlined),
                    tooltip: '列表视图',
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.folder_copy_outlined),
                    tooltip: '按分类分组',
                  ),
                ],
                selected: {_grouped},
                onSelectionChanged: _busy
                    ? null
                    : (value) => setState(() => _grouped = value.first),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: const Key('add-project-attachment-button'),
                onPressed: _busy ? null : _pickFiles,
                icon: const Icon(Icons.attach_file_outlined),
                label: Text(_busy ? '处理中' : '添加文件'),
              ),
            ],
          ),
          if (widget.categories.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('全部', null),
                  for (final category in widget.categories)
                    _filterChip(category.name, category.id),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('暂无匹配的附件'),
            )
          else if (_grouped)
            _buildGrouped(filtered)
          else
            _buildList(filtered),
          if (_selectedIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildBatchBar(),
          ],
        ],
      ),
    );
  }

  Widget _filterChip(String label, String? id) {
    final selected = _filterCategoryId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: _busy
            ? null
            : (value) => setState(() => _filterCategoryId = value ? id : null),
      ),
    );
  }

  Widget _buildList(List<AttachmentData> filtered) => Column(
    children: [
      for (var index = 0; index < filtered.length; index++) ...[
        _buildRow(filtered[index]),
        if (index < filtered.length - 1) const Divider(height: 20),
      ],
    ],
  );

  Widget _buildGrouped(List<AttachmentData> filtered) {
    final grouped = <String, List<AttachmentData>>{};
    for (final category in widget.categories) {
      final items = filtered
          .where((attachment) => attachment.categoryIds.contains(category.id))
          .toList();
      if (items.isNotEmpty) grouped[category.id] = items;
    }
    final uncategorized = filtered
        .where((attachment) => attachment.categoryIds.isEmpty)
        .toList();

    return Column(
      children: [
        for (final category in widget.categories)
          if (grouped.containsKey(category.id))
            _buildGroupTile(category: category, items: grouped[category.id]!),
        if (uncategorized.isNotEmpty)
          _buildGroupTile(category: null, items: uncategorized),
      ],
    );
  }

  Widget _buildGroupTile({
    required AttachmentCategory? category,
    required List<AttachmentData> items,
  }) {
    final groupKey = category?.id ?? '__uncategorized__';
    final expanded = !_collapsedGroups.contains(groupKey);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        onExpansionChanged: (value) => setState(() {
          if (value) {
            _collapsedGroups.remove(groupKey);
          } else {
            _collapsedGroups.add(groupKey);
          }
        }),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          category == null
              ? Icons.folder_off_outlined
              : Icons.label_outline_rounded,
          color: CardoryColors.primary,
        ),
        title: Text(
          category?.name ?? '未分类',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('${items.length} 个文件'),
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _buildRow(items[index]),
            if (index < items.length - 1) const Divider(height: 20),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildRow(AttachmentData attachment) => _AttachmentRow(
    attachment: attachment,
    categories: widget.categories,
    selected: _selectedIds.contains(attachment.id),
    batchMode: _selectedIds.isNotEmpty,
    enabled: !_busy,
    onToggleSelect: () => _toggleSelect(attachment.id),
    onEditNote: _editNote,
    onRename: _renameOne,
    onEditCategories: _editCategoriesOne,
    onExport: widget.repository == null ? null : _export,
    onRemove: _remove,
  );

  Widget _buildBatchBar() {
    final count = _selectedIds.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: CardoryColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '已选 $count 项',
            style: TextStyle(
              color: CardoryColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _batchExport,
            icon: const Icon(Icons.download_outlined, size: 18),
            label: const Text('批量导出'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _batchAssignCategories,
            icon: const Icon(Icons.label_outline_rounded, size: 18),
            label: const Text('分配分类'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _batchRemove,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('删除'),
          ),
          TextButton(
            onPressed: () => setState(() => _selectedIds.clear()),
            child: const Text('取消选择'),
          ),
        ],
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({
    required this.attachment,
    required this.categories,
    required this.selected,
    required this.batchMode,
    required this.enabled,
    required this.onToggleSelect,
    required this.onEditNote,
    required this.onRename,
    required this.onEditCategories,
    required this.onExport,
    required this.onRemove,
  });

  final AttachmentData attachment;
  final List<AttachmentCategory> categories;
  final bool selected;
  final bool batchMode;
  final bool enabled;
  final VoidCallback onToggleSelect;
  final Future<void> Function(AttachmentData attachment) onEditNote;
  final Future<void> Function(AttachmentData attachment) onRename;
  final Future<void> Function(AttachmentData attachment) onEditCategories;
  final Future<void> Function(AttachmentData attachment)? onExport;
  final Future<void> Function(AttachmentData attachment) onRemove;

  void _handleAction(_AttachmentAction action) {
    switch (action) {
      case _AttachmentAction.editNote:
        onEditNote(attachment);
        break;
      case _AttachmentAction.rename:
        onRename(attachment);
        break;
      case _AttachmentAction.editCategories:
        onEditCategories(attachment);
        break;
      case _AttachmentAction.export:
        onExport?.call(attachment);
        break;
      case _AttachmentAction.remove:
        onRemove(attachment);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryNames = <String>[
      for (final id in attachment.categoryIds)
        for (final category in categories)
          if (category.id == id) category.name,
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
                  Text(_formatFileSize(attachment.size)),
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
                  style: TextStyle(
                    color: CardoryColors.gray500,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!batchMode)
          PopupMenuButton<_AttachmentAction>(
            tooltip: '更多附件操作',
            enabled: enabled,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: _handleAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _AttachmentAction.editNote,
                child: ListTile(
                  leading: Icon(Icons.edit_note_outlined),
                  title: Text('编辑备注'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: _AttachmentAction.rename,
                child: ListTile(
                  leading: Icon(Icons.drive_file_rename_outline),
                  title: Text('重命名'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: _AttachmentAction.editCategories,
                child: ListTile(
                  leading: Icon(Icons.label_outline_rounded),
                  title: Text('编辑分类'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (onExport != null)
                const PopupMenuItem(
                  value: _AttachmentAction.export,
                  child: ListTile(
                    leading: Icon(Icons.download_outlined),
                    title: Text('导出附件'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: _AttachmentAction.remove,
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

enum _AttachmentAction { editNote, rename, editCategories, export, remove }

IconData _iconFor(AttachmentKind kind) => switch (kind) {
  AttachmentKind.image => Icons.image_outlined,
  AttachmentKind.document => Icons.description_outlined,
  AttachmentKind.archive => Icons.folder_zip_outlined,
  AttachmentKind.other => Icons.insert_drive_file_outlined,
};

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

class _CategoryManagerResult {
  const _CategoryManagerResult({
    required this.attachments,
    required this.categories,
    required this.removedIds,
  });

  final List<AttachmentData> attachments;
  final List<AttachmentCategory> categories;
  final Set<String> removedIds;
}

class _CategoryManagerDialog extends StatefulWidget {
  const _CategoryManagerDialog({
    required this.categories,
    required this.attachments,
  });

  final List<AttachmentCategory> categories;
  final List<AttachmentData> attachments;

  @override
  State<_CategoryManagerDialog> createState() => _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<_CategoryManagerDialog> {
  late List<AttachmentCategory> _categories = [...widget.categories];
  late List<AttachmentData> _attachments = [...widget.attachments];
  final TextEditingController _newCategory = TextEditingController();
  final Set<String> _removedIds = {};

  int _countFor(String categoryId) =>
      _attachments.where((item) => item.categoryIds.contains(categoryId)).length;

  void _addCategory() {
    final name = _newCategory.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _categories.add(
        AttachmentCategory(id: newId(), name: name, createdAt: DateTime.now()),
      );
      _newCategory.clear();
    });
  }

  Future<void> _renameCategory(AttachmentCategory category) async {
    final controller = TextEditingController(text: category.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名分类'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '分类名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    setState(() {
      _categories = [
        for (final item in _categories)
          item.id == category.id ? item.copyWith(name: name) : item,
      ];
    });
  }

  Future<void> _deleteCategory(AttachmentCategory category) async {
    final count = _countFor(category.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分类'),
        content: Text(
          count == 0
              ? '确定删除分类“${category.name}”吗？'
              : '删除分类“${category.name}”将同时移除 $count 个附件的该分类标记，确定删除吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: CardoryColors.error,
              foregroundColor: CardoryColors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _categories.removeWhere((item) => item.id == category.id);
      _attachments = [
        for (final attachment in _attachments)
          if (attachment.categoryIds.contains(category.id))
            _withoutCategory(attachment, category.id)
          else
            attachment,
      ];
      _removedIds.add(category.id);
    });
  }

  AttachmentData _withoutCategory(AttachmentData attachment, String categoryId) {
    final remaining = attachment.categoryIds
        .where((id) => id != categoryId)
        .toList();
    return attachment.copyWith(
      categoryIds: remaining,
      clearCategoryIds: remaining.isEmpty,
    );
  }

  @override
  void dispose() {
    _newCategory.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('管理分类'),
      content: SizedBox(
        width: 440,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newCategory,
                    onSubmitted: (_) => _addCategory(),
                    decoration: const InputDecoration(
                      labelText: '新分类名称',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _addCategory,
                  child: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _categories.isEmpty
                  ? Center(
                      child: Text(
                        '暂无分类，输入名称后点击“添加”创建。',
                        style: TextStyle(color: CardoryColors.gray400),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final category in _categories)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.label_outline_rounded),
                              title: Text(category.name),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${_countFor(category.id)} 个附件',
                                    style: TextStyle(
                                      color: CardoryColors.gray500,
                                      fontSize: 12,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '重命名分类',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        _renameCategory(category),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: '删除分类',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        _deleteCategory(category),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _CategoryManagerResult(
              attachments: _attachments,
              categories: _categories,
              removedIds: _removedIds,
            ),
          ),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

class _CategoryAssignDialog extends StatefulWidget {
  const _CategoryAssignDialog({
    required this.categories,
    required this.initialIds,
  });

  final List<AttachmentCategory> categories;
  final Set<String> initialIds;

  @override
  State<_CategoryAssignDialog> createState() => _CategoryAssignDialogState();
}

class _CategoryAssignDialogState extends State<_CategoryAssignDialog> {
  late final Set<String> _selected = {...widget.initialIds};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('分配分类'),
      content: SizedBox(
        width: 360,
        child: widget.categories.isEmpty
            ? const Text('还没有分类，请先在“管理分类”中创建。')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '可选择一个或多个分类，保存后将覆盖所选附件的现有分类。',
                    style: TextStyle(color: CardoryColors.gray500, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  for (final category in widget.categories)
                    CheckboxListTile(
                      value: _selected.contains(category.id),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _selected.add(category.id);
                        } else {
                          _selected.remove(category.id);
                        }
                      }),
                      title: Text(category.name),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: widget.categories.isEmpty
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _BatchRenameDialog extends StatefulWidget {
  const _BatchRenameDialog({
    required this.files,
    required this.keepExtension,
  });

  final List<AttachmentData> files;
  final bool keepExtension;

  @override
  State<_BatchRenameDialog> createState() => _BatchRenameDialogState();
}

class _BatchRenameDialogState extends State<_BatchRenameDialog> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (final file in widget.files)
        TextEditingController(
          text: widget.keepExtension
              ? _stripExtension(file.fileName)
              : file.fileName,
        ),
    ];
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('重命名上传文件（${widget.files.length} 个）'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.keepExtension) ...[
                Text(
                  '仅修改文件名主体，原扩展名保持不变。',
                  style: TextStyle(color: CardoryColors.gray500, fontSize: 12),
                ),
                const SizedBox(height: 10),
              ],
              for (var index = 0; index < widget.files.length; index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: _controllers[index],
                    decoration: InputDecoration(
                      labelText: widget.keepExtension
                          ? '文件 ${index + 1}（扩展名保留）'
                          : '文件 ${index + 1}',
                      isDense: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('跳过'),
        ),
        FilledButton(
          onPressed: () {
            final result = <String, String>{};
            for (var index = 0; index < widget.files.length; index++) {
              final input = _controllers[index].text.trim();
              if (input.isEmpty) continue;
              final newName = widget.keepExtension
                  ? _applyRenameKeepingExtension(
                      input,
                      widget.files[index].fileName,
                    )
                  : input;
              if (newName != widget.files[index].fileName) {
                result[widget.files[index].id] = newName;
              }
            }
            Navigator.pop(context, result);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

String _stripExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0 || dot == fileName.length - 1) return fileName;
  return fileName.substring(0, dot);
}

String _applyRenameKeepingExtension(String input, String originalFileName) {
  final originalBody = _stripExtension(originalFileName);
  final extension = originalBody == originalFileName
      ? ''
      : originalFileName.substring(originalBody.length + 1);
  var body = input.trim();
  if (extension.isNotEmpty &&
      body.toLowerCase().endsWith('.$extension'.toLowerCase())) {
    body = body.substring(0, body.length - extension.length - 1).trimRight();
  }
  if (body.isEmpty) return originalFileName;
  return extension.isEmpty ? body : '$body.$extension';
}
