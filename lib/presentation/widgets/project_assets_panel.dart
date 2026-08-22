// 项目资产面板：资产列表、标签筛选、分组、批量操作与标签管理入口。

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import 'asset_tag_dialogs.dart';
import 'badges.dart';
import 'batch_action_bar.dart';
import 'grouped_expansion_list.dart';
import 'section_title.dart';

/// 资产面板：展示软件/硬件资产，支持按标签筛选与分组、批量分配标签。
class ProjectAssetsPanel extends StatefulWidget {
  const ProjectAssetsPanel({
    super.key,
    required this.assets,
    required this.assetTags,
    required this.onAdd,
    required this.onView,
    required this.onDelete,
    required this.onUpdateAssetsTags,
    required this.onAddTag,
    required this.onUpdateTag,
    required this.onDeleteTag,
  });

  final List<AssetData> assets;
  final List<AssetTag> assetTags;
  final Future<void> Function() onAdd;
  final Future<void> Function(AssetData asset) onView;
  final Future<void> Function(AssetData asset) onDelete;
  final Future<void> Function(Set<String> assetIds, Set<String> tagIds)
  onUpdateAssetsTags;
  final Future<AssetTag> Function(AssetTag tag) onAddTag;
  final Future<AssetTag> Function(AssetTag tag) onUpdateTag;
  final Future<void> Function(String tagId) onDeleteTag;

  @override
  State<ProjectAssetsPanel> createState() => _ProjectAssetsPanelState();
}

class _ProjectAssetsPanelState extends State<ProjectAssetsPanel> {
  bool _busy = false;
  final Set<String> _selectedIds = {};
  String? _filterTagId;
  bool _grouped = false;

  List<AssetData> get _filteredAssets {
    final filter = _filterTagId;
    if (filter == null) return List.of(widget.assets);
    return widget.assets
        .where((asset) => asset.tagIds.contains(filter))
        .toList();
  }

  Future<void> _manageTags() async {
    final result = await showDialog<AssetTagManagerResult>(
      context: context,
      builder: (_) => AssetTagManagerDialog(
        assetTags: widget.assetTags,
        assets: widget.assets,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (result.removedIds.contains(_filterTagId)) _filterTagId = null;
    });
    for (final tag in result.tags) {
      try {
        if (result.createdIds.contains(tag.id)) {
          await widget.onAddTag(tag);
        } else if (result.renamedIds.contains(tag.id)) {
          await widget.onUpdateTag(tag);
        }
      } catch (error) {
        debugPrint('Failed to save asset tag: $error');
      }
    }
    for (final tagId in result.removedIds) {
      try {
        await widget.onDeleteTag(tagId);
      } catch (error) {
        debugPrint('Failed to delete asset tag: $error');
      }
    }
  }

  Future<void> _assignTags(
    Set<String> assetIds,
    Set<String> initialIds,
  ) async {
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (_) => AssetTagAssignDialog(
        assetTags: widget.assetTags,
        initialIds: initialIds,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onUpdateAssetsTags(assetIds, selected);
      if (mounted) setState(() => _selectedIds.clear());
    } catch (error) {
      debugPrint('Failed to update asset tags: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('标签更新失败，请稍后重试。')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleSelect(String id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredAssets;
    final tagById = {for (final tag in widget.assetTags) tag.id: tag.name};
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
                  title: '项目资产',
                  subtitle: '软件与硬件资产均归属当前项目 · '
                      '${widget.assetTags.length} 个标签',
                ),
              ),
              IconButton(
                key: const Key('manage-asset-tags-button'),
                tooltip: '管理标签',
                onPressed: _busy ? null : _manageTags,
                icon: const Icon(Icons.sell_outlined),
              ),
              IconButton(
                key: const Key('toggle-asset-batch-button'),
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
                    tooltip: '按标签分组',
                  ),
                ],
                selected: {_grouped},
                onSelectionChanged: _busy
                    ? null
                    : (value) => setState(() => _grouped = value.first),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                key: const Key('add-project-asset-button'),
                onPressed: _busy ? null : () => widget.onAdd(),
                icon: const Icon(Icons.add),
                label: const Text('新增资产'),
              ),
            ],
          ),
          if (widget.assetTags.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('全部', null),
                  for (final tag in widget.assetTags)
                    _filterChip(tag.name, tag.id),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            EmptyCard(
              text: _filterTagId == null ? '暂无项目资产' : '暂无匹配标签的资产',
              actionLabel: _filterTagId == null ? '新增资产' : null,
              onAction: _filterTagId == null ? () => widget.onAdd() : null,
            )
          else if (_grouped)
            _buildGrouped(filtered, tagById)
          else
            _buildList(filtered, tagById),
          if (_selectedIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            BatchActionBar(
              count: _selectedIds.length,
              actions: [
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _assignTags(_selectedIds.toSet(), const {}),
                  icon: const Icon(Icons.sell_outlined, size: 18),
                  label: const Text('分配标签'),
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
    final selected = _filterTagId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: _busy
            ? null
            : (value) => setState(() => _filterTagId = value ? id : null),
      ),
    );
  }

  Widget _buildList(List<AssetData> filtered, Map<String, String> tagById) =>
      ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: filtered.length,
        itemBuilder: (context, index) => Column(
          key: ValueKey('asset-${filtered[index].id}'),
          children: [
            _buildRow(filtered[index], tagById),
            if (index < filtered.length - 1) const SizedBox(height: 10),
          ],
        ),
      );

  Widget _buildGrouped(
    List<AssetData> filtered,
    Map<String, String> tagById,
  ) =>
      GroupedExpansionList<AssetData>(
        items: filtered,
        groupKeysOf: (asset) => asset.tagIds,
        groupOrder: [for (final tag in widget.assetTags) tag.id],
        groupTitleOf: (key) => tagById[key] ?? key,
        rowBuilder: (context, asset) => _buildRow(asset, tagById),
        uncategorizedTitle: '未打标签',
        countLabel: '项',
        groupIcon: Icons.sell_rounded,
        uncategorizedIcon: Icons.sell_outlined,
        rowSeparator: const SizedBox(height: 10),
      );

  Widget _buildRow(AssetData asset, Map<String, String> tagById) {
    // 扁平化减重：附件图标统一灰色，不使用彩色图标块。
    final accent = CardoryColors.gray500;
    final tagNames = <String>[];
    for (final id in asset.tagIds) {
      final name = tagById[id];
      if (name != null) tagNames.add(name);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: cardoryCard(radius: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedIds.isNotEmpty) ...[
            Checkbox(
              value: _selectedIds.contains(asset.id),
              onChanged: _busy ? null : (_) => _toggleSelect(asset.id),
              visualDensity: VisualDensity.compact,
            ),
          ],
          Expanded(
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onTap: () => widget.onView(asset),
              leading: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cardoryTint(accent, 0.88),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  asset.type == AssetType.software
                      ? Icons.apps_outlined
                      : Icons.dns_outlined,
                  color: accent,
                  size: 19,
                ),
              ),
              title: Text(asset.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.type == AssetType.software
                        ? [
                            if (asset.version.isNotEmpty) '版本 ${asset.version}',
                            if (asset.port.isNotEmpty) '端口 ${asset.port}',
                            if (asset.path.isNotEmpty) asset.path,
                          ].join(' · ')
                        : [
                            if (asset.serverType.isNotEmpty) asset.serverType,
                            if (asset.serialNumber.isNotEmpty)
                              '序列号 ${asset.serialNumber}',
                            if (asset.network.isNotEmpty) asset.network,
                          ].join(' · '),
                  ),
                  if (tagNames.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '标签：${tagNames.join('、')}',
                      style: TextStyle(
                        color: CardoryColors.gray600,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
              isThreeLine: tagNames.isNotEmpty,
            ),
          ),
          if (_selectedIds.isEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<AssetRowAction>(
                  tooltip: '更多资产操作',
                  enabled: !_busy,
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (action) {
                    if (action == AssetRowAction.editTags) {
                      _assignTags({asset.id}, asset.tagIds.toSet());
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: AssetRowAction.editTags,
                      child: ListTile(
                        leading: Icon(Icons.sell_outlined),
                        title: Text('编辑标签'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: '删除资产',
                  onPressed: _busy ? null : () => widget.onDelete(asset),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

enum AssetRowAction { editTags }
