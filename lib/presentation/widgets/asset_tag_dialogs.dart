// 资产标签相关对话框：标签管理 / 标签分配。

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import 'confirm_dialogs.dart';

/// 标签管理对话框的结果：保存后的标签、新增/重命名/删除的标签 id。
class AssetTagManagerResult {
  const AssetTagManagerResult({
    required this.tags,
    required this.createdIds,
    required this.renamedIds,
    required this.removedIds,
  });

  final List<AssetTag> tags;
  final Set<String> createdIds;
  final Set<String> renamedIds;
  final Set<String> removedIds;
}

class AssetTagManagerDialog extends StatefulWidget {
  const AssetTagManagerDialog({
    super.key,
    required this.assetTags,
    required this.assets,
  });

  final List<AssetTag> assetTags;
  final List<AssetData> assets;

  @override
  State<AssetTagManagerDialog> createState() => _AssetTagManagerDialogState();
}

class _AssetTagManagerDialogState extends State<AssetTagManagerDialog> {
  late List<AssetTag> _tags = [...widget.assetTags];
  final TextEditingController _newTag = TextEditingController();
  final Set<String> _createdIds = {};
  final Set<String> _renamedIds = {};
  final Set<String> _removedIds = {};

  int _countFor(String tagId) =>
      widget.assets.where((asset) => asset.tagIds.contains(tagId)).length;

  void _addTag() {
    final name = _newTag.text.trim();
    if (name.isEmpty) return;
    final tag = AssetTag(id: newId(), name: name, createdAt: DateTime.now());
    setState(() {
      _tags.add(tag);
      _createdIds.add(tag.id);
      _newTag.clear();
    });
  }

  Future<void> _renameTag(AssetTag tag) async {
    final name = await showTextInputDialog(
      context,
      title: '重命名标签',
      initialValue: tag.name,
      labelText: '标签名称',
    );
    if (name == null || name.isEmpty || !mounted) return;
    setState(() {
      _tags = [
        for (final item in _tags)
          item.id == tag.id ? item.copyWith(name: name) : item,
      ];
      if (!_createdIds.contains(tag.id)) _renamedIds.add(tag.id);
    });
  }

  Future<void> _deleteTag(AssetTag tag) async {
    final count = _countFor(tag.id);
    final confirmed = await showConfirmDialog(
      context,
      title: '删除标签',
      content: count == 0
          ? '确定删除标签“${tag.name}”吗？'
          : '删除标签“${tag.name}”将同时从 $count 项资产上移除该标签，确定删除吗？',
      confirmLabel: '删除',
      confirmColor: CardoryColors.error,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _tags.removeWhere((item) => item.id == tag.id);
      _createdIds.remove(tag.id);
      _renamedIds.remove(tag.id);
      _removedIds.add(tag.id);
    });
  }

  @override
  void dispose() {
    _newTag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('管理标签'),
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
                    controller: _newTag,
                    onSubmitted: (_) => _addTag(),
                    decoration: const InputDecoration(
                      labelText: '新标签名称',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _addTag,
                  child: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _tags.isEmpty
                  ? Center(
                      child: Text(
                        '暂无标签，输入名称后点击“添加”创建。',
                        style: TextStyle(color: CardoryColors.gray500),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          for (final tag in _tags)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.sell_outlined),
                              title: Text(tag.name),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${_countFor(tag.id)} 项',
                                    style: TextStyle(
                                      color: CardoryColors.gray500,
                                      fontSize: 12,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '重命名标签',
                                    onPressed: () => _renameTag(tag),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: '删除标签',
                                    onPressed: () => _deleteTag(tag),
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
            AssetTagManagerResult(
              tags: _tags,
              createdIds: _createdIds,
              renamedIds: _renamedIds,
              removedIds: _removedIds,
            ),
          ),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

class AssetTagAssignDialog extends StatefulWidget {
  const AssetTagAssignDialog({
    super.key,
    required this.assetTags,
    required this.initialIds,
  });

  final List<AssetTag> assetTags;
  final Set<String> initialIds;

  @override
  State<AssetTagAssignDialog> createState() => _AssetTagAssignDialogState();
}

class _AssetTagAssignDialogState extends State<AssetTagAssignDialog> {
  late final Set<String> _selected = {...widget.initialIds};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('分配标签'),
      content: SizedBox(
        width: 360,
        child: widget.assetTags.isEmpty
            ? const Text('还没有标签，请先在“管理标签”中创建。')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '可选择一个或多个标签，保存后将覆盖所选资产的现有标签。',
                    style: TextStyle(color: CardoryColors.gray500, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  for (final tag in widget.assetTags)
                    CheckboxListTile(
                      value: _selected.contains(tag.id),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          _selected.add(tag.id);
                        } else {
                          _selected.remove(tag.id);
                        }
                      }),
                      title: Text(tag.name),
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
          onPressed: widget.assetTags.isEmpty
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
