// 附件相关对话框（分类管理 / 分类分配 / 批量重命名）。

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import 'confirm_dialogs.dart';

/// 分类管理对话框的结果：保存后的附件、分类以及被删除的分类 id。
class AttachmentCategoryManagerResult {
  const AttachmentCategoryManagerResult({
    required this.attachments,
    required this.categories,
    required this.removedIds,
  });

  final List<AttachmentData> attachments;
  final List<AttachmentCategory> categories;
  final Set<String> removedIds;
}

class CategoryManagerDialog extends StatefulWidget {
  const CategoryManagerDialog({
    super.key,
    required this.categories,
    required this.attachments,
  });

  final List<AttachmentCategory> categories;
  final List<AttachmentData> attachments;

  @override
  State<CategoryManagerDialog> createState() => _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<CategoryManagerDialog> {
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
    final name = await showTextInputDialog(
      context,
      title: '重命名分类',
      initialValue: category.name,
      labelText: '分类名称',
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() {
      _categories = [
        for (final item in _categories)
          item.id == category.id ? item.copyWith(name: name) : item,
      ];
    });
  }

  Future<void> _deleteCategory(AttachmentCategory category) async {
    final count = _countFor(category.id);
    final confirmed = await showConfirmDialog(
      context,
      title: '删除分类',
      content: count == 0
          ? '确定删除分类“${category.name}”吗？'
          : '删除分类“${category.name}”将同时移除 $count 个附件的该分类标记，确定删除吗？',
      confirmLabel: '删除',
      confirmColor: CardoryColors.error,
    );
    if (!confirmed || !mounted) return;
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
                        style: TextStyle(color: CardoryColors.gray500),
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
                                    onPressed: () =>
                                        _renameCategory(category),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: '删除分类',
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
            AttachmentCategoryManagerResult(
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

class CategoryAssignDialog extends StatefulWidget {
  const CategoryAssignDialog({
    super.key,
    required this.categories,
    required this.initialIds,
  });

  final List<AttachmentCategory> categories;
  final Set<String> initialIds;

  @override
  State<CategoryAssignDialog> createState() => _CategoryAssignDialogState();
}

class _CategoryAssignDialogState extends State<CategoryAssignDialog> {
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

class BatchRenameDialog extends StatefulWidget {
  const BatchRenameDialog({
    super.key,
    required this.files,
    required this.keepExtension,
  });

  final List<AttachmentData> files;
  final bool keepExtension;

  @override
  State<BatchRenameDialog> createState() => _BatchRenameDialogState();
}

class _BatchRenameDialogState extends State<BatchRenameDialog> {
  late final List<TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = [
      for (final file in widget.files)
        TextEditingController(
          text: widget.keepExtension
              ? stripExtension(file.fileName)
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
                  ? applyRenameKeepingExtension(
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

