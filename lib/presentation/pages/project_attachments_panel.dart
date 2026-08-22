// 项目附件面板：附件导入、筛选、分组、批量操作与分类管理入口。

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../domain/attachment_repository.dart';
import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import '../widgets/attachment_dialogs.dart';
import '../widgets/attachment_row.dart';
import '../widgets/batch_action_bar.dart';
import '../widgets/confirm_dialogs.dart';
import '../widgets/grouped_expansion_list.dart';
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
    builder: (_) => BatchRenameDialog(
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
    final note = await showTextInputDialog(
      context,
      title: '附件备注',
      initialValue: attachment.note,
      labelText: '备注',
      minLines: 2,
      maxLines: 5,
    );
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
    final name = await showTextInputDialog(
      context,
      title: '重命名附件',
      initialValue: keepExtension
          ? stripExtension(attachment.fileName)
          : attachment.fileName,
      labelText: keepExtension ? '文件名（扩展名保留）' : '文件名',
      helperText: keepExtension ? '仅修改文件名主体，原扩展名保持不变' : null,
    );
    if (name == null || name.isEmpty) return;
    final newName = keepExtension
        ? applyRenameKeepingExtension(name, attachment.fileName)
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
      builder: (_) => CategoryAssignDialog(
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
      builder: (_) => CategoryAssignDialog(
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
    final confirmed = await showConfirmDialog(
      context,
      title: '删除附件',
      content: '确定删除选中的 ${selected.length} 个附件吗？附件文件将从本地存储中移除。',
      confirmLabel: '删除',
      confirmColor: CardoryColors.error,
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
    final result = await showDialog<AttachmentCategoryManagerResult>(
      context: context,
      builder: (_) => CategoryManagerDialog(
        categories: widget.categories,
        attachments: widget.attachments,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
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
      // 与文件内其他错误处理一致：仅提示一次 SnackBar，避免对话框 + SnackBar 双重打扰。
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
    // 先清除排队中的提示（如父级先弹出的通用错误），避免具体错误被延迟展示。
    ScaffoldMessenger.of(
      context,
    )
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAttachments;
    final categoryById = {
      for (final category in widget.categories) category.id: category.name,
    };
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
            _buildGrouped(filtered, categoryById)
          else
            _buildList(filtered, categoryById),
          if (_selectedIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            BatchActionBar(
              count: _selectedIds.length,
              actions: [
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

  Widget _buildList(
    List<AttachmentData> filtered,
    Map<String, String> categoryById,
  ) =>
      ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: filtered.length,
        itemBuilder: (context, index) => Column(
          key: ValueKey('attachment-${filtered[index].id}'),
          children: [
            _buildRow(filtered[index], categoryById),
            if (index < filtered.length - 1) const Divider(height: 20),
          ],
        ),
      );

  Widget _buildGrouped(
    List<AttachmentData> filtered,
    Map<String, String> categoryById,
  ) =>
      GroupedExpansionList<AttachmentData>(
        items: filtered,
        groupKeysOf: (attachment) => attachment.categoryIds,
        groupOrder: [for (final category in widget.categories) category.id],
        groupTitleOf: (key) => categoryById[key] ?? key,
        rowBuilder: (context, attachment) =>
            _buildRow(attachment, categoryById),
        uncategorizedTitle: '未分类',
        countLabel: '个文件',
        groupIcon: Icons.label_outline_rounded,
        uncategorizedIcon: Icons.folder_off_outlined,
        rowSeparator: const Divider(height: 20),
      );

  Widget _buildRow(
    AttachmentData attachment,
    Map<String, String> categoryById,
  ) =>
      AttachmentRow(
    attachment: attachment,
    categoryNamesById: categoryById,
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
}
