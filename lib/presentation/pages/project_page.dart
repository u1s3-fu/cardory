import 'package:flutter/material.dart';

import '../../application/attachment_repository.dart';
import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import '../dialogs/progress_dialog.dart';
import '../widgets/badges.dart';
import '../widgets/section_title.dart';
import 'dashboard.dart';
import 'project_attachments_panel.dart';

class ProjectDetailPage extends StatefulWidget {
  const ProjectDetailPage({
    super.key,
    required this.project,
    required this.todos,
    required this.assets,
    required this.onUpdateProject,
    required this.onAddAsset,
    required this.onEditAsset,
    required this.onDeleteAsset,
    required this.onToggleTodo,
    required this.onToggleSubTodo,
    required this.onOpenTodo,
    required this.onAddTodo,
    required this.onDeleteTodo,
    this.assetTags = const [],
    this.onUpdateAssetsTags,
    this.onAddAssetTag,
    this.onUpdateAssetTag,
    this.onDeleteAssetTag,
    this.attachmentStore,
    this.renameAttachmentsOnUpload = true,
    this.keepAttachmentExtensionOnRename = false,
  });

  final ProjectData project;
  final List<TodoData> todos;
  final List<AssetData> assets;
  final List<AssetTag> assetTags;
  final Future<void> Function(ProjectData project) onUpdateProject;
  final Future<AssetData?> Function() onAddAsset;
  final Future<AssetData?> Function(AssetData asset) onEditAsset;
  final Future<void> Function(AssetData asset) onDeleteAsset;
  final Future<TodoData> Function(TodoData todo) onToggleTodo;
  final Future<TodoData> Function(TodoData todo, SubTodoData subTodo)
  onToggleSubTodo;
  final Future<TodoData?> Function(TodoData todo) onOpenTodo;
  final Future<TodoData?> Function(ProjectData project) onAddTodo;
  final Future<bool> Function(TodoData todo) onDeleteTodo;
  final Future<void> Function(Set<String> assetIds, Set<String> tagIds)?
  onUpdateAssetsTags;
  final Future<AssetTag> Function(AssetTag tag)? onAddAssetTag;
  final Future<AssetTag> Function(AssetTag tag)? onUpdateAssetTag;
  final Future<void> Function(String tagId)? onDeleteAssetTag;
  final AttachmentRepository? attachmentStore;
  final bool renameAttachmentsOnUpload;
  final bool keepAttachmentExtensionOnRename;

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  late ProjectData _project;
  late List<TodoData> _todos;
  late List<AssetData> _assets;
  late List<AssetTag> _assetTags;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _todos = widget.todos;
    _assets = widget.assets;
    _assetTags = widget.assetTags;
  }

  Future<void> _updateAssetsTags(
    Set<String> assetIds,
    Set<String> tagIds,
  ) async {
    final previous = _assets;
    setState(() {
      _assets = _assets.map((asset) {
        if (!assetIds.contains(asset.id)) return asset;
        return asset.copyWith(
          tagIds: tagIds.toList(),
          clearTagIds: tagIds.isEmpty,
        );
      }).toList();
    });
    try {
      await widget.onUpdateAssetsTags?.call(assetIds, tagIds);
    } catch (_) {
      if (mounted) setState(() => _assets = previous);
      rethrow;
    }
  }

  Future<AssetTag> _addAssetTag(AssetTag tag) async {
    final added = await widget.onAddAssetTag?.call(tag) ?? tag;
    if (mounted) setState(() => _assetTags = [..._assetTags, added]);
    return added;
  }

  Future<AssetTag> _updateAssetTag(AssetTag tag) async {
    final updated = await widget.onUpdateAssetTag?.call(tag) ?? tag;
    if (mounted) {
      setState(() {
        _assetTags = [
          for (final item in _assetTags)
            if (item.id == updated.id) updated else item,
        ];
      });
    }
    return updated;
  }

  Future<void> _deleteAssetTag(String tagId) async {
    await widget.onDeleteAssetTag?.call(tagId);
    if (!mounted) return;
    setState(() {
      _assetTags = _assetTags
          .where((item) => item.id != tagId)
          .toList();
      _assets = _assets.map((asset) {
        if (!asset.tagIds.contains(tagId)) return asset;
        final remaining = asset.tagIds
            .where((id) => id != tagId)
            .toList();
        return asset.copyWith(
          tagIds: remaining,
          clearTagIds: remaining.isEmpty,
        );
      }).toList();
    });
  }

  Future<void> _save(ProjectData project) async {
    final previous = _project;
    setState(() => _project = project);
    try {
      await widget.onUpdateProject(project);
    } catch (_) {
      if (mounted) setState(() => _project = previous);
      rethrow;
    }
  }

  Future<void> _addProgress() async {
    final entry = await showDialog<ProjectProgressEntry>(
      context: context,
      builder: (_) => ProgressDialog(currentProgress: _project.progress),
    );
    if (entry == null) return;
    await _save(
      _project.copyWith(progressEntries: [..._project.progressEntries, entry]),
    );
  }

  Future<void> _editProgress(ProjectProgressEntry current) async {
    final entry = await showDialog<ProjectProgressEntry>(
      context: context,
      builder: (_) => ProgressDialog(entry: current),
    );
    if (entry == null) return;
    await _save(
      _project.copyWith(
        progressEntries: _project.progressEntries
            .map((item) => item.id == entry.id ? entry : item)
            .toList(),
      ),
    );
  }

  Future<void> _toggleTodo(TodoData todo) async {
    final updated = await widget.onToggleTodo(todo);
    setState(
      () => _todos = _todos
          .map((item) => item.id == updated.id ? updated : item)
          .toList(),
    );
  }

  Future<void> _toggleSubTodo(TodoData todo, SubTodoData subTodo) async {
    final updated = await widget.onToggleSubTodo(todo, subTodo);
    setState(
      () => _todos = _todos
          .map((item) => item.id == updated.id ? updated : item)
          .toList(),
    );
  }

  Future<void> _addTodo() async {
    final todo = await widget.onAddTodo(_project);
    if (todo != null && mounted) setState(() => _todos = [..._todos, todo]);
  }

  Future<void> _openTodo(TodoData todo) async {
    final updated = await widget.onOpenTodo(todo);
    if (updated == null || !mounted) return;
    setState(() {
      _todos = updated.projectId == _project.id
          ? _todos
                .map((item) => item.id == updated.id ? updated : item)
                .toList()
          : _todos.where((item) => item.id != updated.id).toList();
    });
  }

  Future<void> _viewAsset(AssetData asset) async {
    final shouldEdit = await showDialog<bool>(
      context: context,
      builder: (_) => AssetDetailDialog(
        asset: asset,
        assetTags: _assetTags,
      ),
    );
    if (shouldEdit != true || !mounted) return;

    final updated = await widget.onEditAsset(asset);
    if (mounted && updated != null) {
      setState(() {
        _assets = _assets
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
      });
    }
  }

  Future<bool> _deleteTodo(TodoData todo) async {
    final deleted = await widget.onDeleteTodo(todo);
    if (deleted && mounted) {
      setState(
        () => _todos = _todos.where((item) => item.id != todo.id).toList(),
      );
    }
    return deleted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_project.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: darkCardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        children: [
                          PriorityBadge(priority: _project.priority),
                          StageBadge(stage: _project.stage),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _project.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          letterSpacing: -0.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _project.description.isEmpty
                            ? '暂无项目说明'
                            : _project.description,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 13.5,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<ProjectStage>(
                        initialValue: _project.stage,
                        decoration: const InputDecoration(
                          labelText: '项目阶段',
                          filled: true,
                        ),
                        items: ProjectStage.values
                            .map(
                              (stage) => DropdownMenuItem(
                                value: stage,
                                child: Text(stage.label),
                              ),
                            )
                            .toList(),
                        onChanged: (stage) {
                          if (stage != null) {
                            _save(_project.copyWith(stage: stage));
                          }
                        },
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _addProgress,
                      icon: const Icon(Icons.add_chart_rounded),
                      label: const Text('记录进度'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _addTodo,
                      icon: const Icon(Icons.add_task_rounded),
                      label: const Text('新建待办'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ProjectAttachmentsPanel(
                  attachments: _project.attachments,
                  categories: _project.categories,
                  repository: widget.attachmentStore,
                  renameOnUpload: widget.renameAttachmentsOnUpload,
                  keepExtensionOnRename:
                      widget.keepAttachmentExtensionOnRename,
                  onChanged: (attachments, categories) async {
                    try {
                      await _save(
                        _project.copyWith(
                          attachments: attachments,
                          categories: categories,
                        ),
                      );
                    } catch (_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('附件更新失败，请稍后重试。'),
                          ),
                        );
                      }
                      rethrow;
                    }
                  },
                ),
                const SizedBox(height: 20),
                _ProjectAssetsPanel(
                  assets: _assets,
                  assetTags: _assetTags,
                  onAdd: () async {
                    final asset = await widget.onAddAsset();
                    if (mounted && asset != null) {
                      setState(() => _assets = [..._assets, asset]);
                    }
                  },
                  onView: _viewAsset,
                  onDelete: (asset) async {
                    await widget.onDeleteAsset(asset);
                    if (mounted) {
                      setState(
                        () => _assets = _assets
                            .where((item) => item.id != asset.id)
                            .toList(),
                      );
                    }
                  },
                  onUpdateAssetsTags: _updateAssetsTags,
                  onAddTag: _addAssetTag,
                  onUpdateTag: _updateAssetTag,
                  onDeleteTag: _deleteAssetTag,
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final timeline = ProgressTimeline(
                      entries: _project.progressEntries,
                      onEdit: _editProgress,
                    );
                    final todos = TodoPanel(
                      todos: _todos,
                      onAddTodo: _addTodo,
                      onToggle: _toggleTodo,
                      onToggleSubTodo: _toggleSubTodo,
                      onOpenTodo: _openTodo,
                      onDeleteTodo: _deleteTodo,
                    );
                    if (constraints.maxWidth < 860) {
                      return Column(
                        children: [timeline, const SizedBox(height: 20), todos],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: timeline),
                        const SizedBox(width: 20),
                        Expanded(child: todos),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectAssetsPanel extends StatefulWidget {
  const _ProjectAssetsPanel({
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
  State<_ProjectAssetsPanel> createState() => _ProjectAssetsPanelState();
}

class _ProjectAssetsPanelState extends State<_ProjectAssetsPanel> {
  bool _busy = false;
  final Set<String> _selectedIds = {};
  String? _filterTagId;
  bool _grouped = false;
  final Set<String> _collapsedGroups = {};

  List<AssetData> get _filteredAssets {
    final filter = _filterTagId;
    if (filter == null) return List.of(widget.assets);
    return widget.assets
        .where((asset) => asset.tagIds.contains(filter))
        .toList();
  }

  Future<void> _manageTags() async {
    final result = await showDialog<_AssetTagManagerResult>(
      context: context,
      builder: (_) => _AssetTagManagerDialog(
        assetTags: widget.assetTags,
        assets: widget.assets,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _collapsedGroups.removeAll(result.removedIds);
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
      builder: (_) => _AssetTagAssignDialog(
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
              FilledButton.icon(
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

  Widget _buildList(List<AssetData> filtered) => Column(
    children: [
      for (var index = 0; index < filtered.length; index++) ...[
        _buildRow(filtered[index]),
        if (index < filtered.length - 1) const SizedBox(height: 10),
      ],
    ],
  );

  Widget _buildGrouped(List<AssetData> filtered) {
    final grouped = <String, List<AssetData>>{};
    for (final tag in widget.assetTags) {
      final items = filtered
          .where((asset) => asset.tagIds.contains(tag.id))
          .toList();
      if (items.isNotEmpty) grouped[tag.id] = items;
    }
    final untagged = filtered
        .where((asset) => asset.tagIds.isEmpty)
        .toList();

    return Column(
      children: [
        for (final tag in widget.assetTags)
          if (grouped.containsKey(tag.id))
            _buildGroupTile(tag: tag, items: grouped[tag.id]!),
        if (untagged.isNotEmpty)
          _buildGroupTile(tag: null, items: untagged),
      ],
    );
  }

  Widget _buildGroupTile({
    required AssetTag? tag,
    required List<AssetData> items,
  }) {
    final groupKey = tag?.id ?? '__untagged__';
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
          tag == null ? Icons.sell_outlined : Icons.sell_rounded,
          color: CardoryColors.primary,
        ),
        title: Text(
          tag?.name ?? '未打标签',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('${items.length} 项'),
        children: [
          for (var index = 0; index < items.length; index++) ...[
            _buildRow(items[index]),
            if (index < items.length - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildRow(AssetData asset) {
    final accent = asset.type == AssetType.software
        ? CardoryColors.primary
        : CardoryColors.success;
    final tagNames = <String>[
      for (final id in asset.tagIds)
        for (final tag in widget.assetTags)
          if (tag.id == id) tag.name,
    ];
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
                PopupMenuButton<_AssetRowAction>(
                  tooltip: '更多资产操作',
                  enabled: !_busy,
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (action) {
                    if (action == _AssetRowAction.editTags) {
                      _assignTags({asset.id}, asset.tagIds.toSet());
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _AssetRowAction.editTags,
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
    );
  }
}

enum _AssetRowAction { editTags }

class _AssetTagManagerResult {
  const _AssetTagManagerResult({
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

class _AssetTagManagerDialog extends StatefulWidget {
  const _AssetTagManagerDialog({
    required this.assetTags,
    required this.assets,
  });

  final List<AssetTag> assetTags;
  final List<AssetData> assets;

  @override
  State<_AssetTagManagerDialog> createState() => _AssetTagManagerDialogState();
}

class _AssetTagManagerDialogState extends State<_AssetTagManagerDialog> {
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
    final controller = TextEditingController(text: tag.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '标签名称'),
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
      _tags = [
        for (final item in _tags)
          item.id == tag.id ? item.copyWith(name: name) : item,
      ];
      if (!_createdIds.contains(tag.id)) _renamedIds.add(tag.id);
    });
  }

  Future<void> _deleteTag(AssetTag tag) async {
    final count = _countFor(tag.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除标签'),
        content: Text(
          count == 0
              ? '确定删除标签“${tag.name}”吗？'
              : '删除标签“${tag.name}”将同时从 $count 项资产上移除该标签，确定删除吗？',
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
                        style: TextStyle(color: CardoryColors.gray400),
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
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _renameTag(tag),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: '删除标签',
                                    visualDensity: VisualDensity.compact,
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
            _AssetTagManagerResult(
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

class _AssetTagAssignDialog extends StatefulWidget {
  const _AssetTagAssignDialog({
    required this.assetTags,
    required this.initialIds,
  });

  final List<AssetTag> assetTags;
  final Set<String> initialIds;

  @override
  State<_AssetTagAssignDialog> createState() => _AssetTagAssignDialogState();
}

class _AssetTagAssignDialogState extends State<_AssetTagAssignDialog> {
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
