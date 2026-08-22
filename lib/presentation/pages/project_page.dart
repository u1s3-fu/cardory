// 项目详情页：项目信息、附件、资产、进度与待办的综合管理。

import 'package:flutter/material.dart';

import '../../domain/attachment_repository.dart';
import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import '../dialogs/progress_dialog.dart';
import '../widgets/asset_detail_dialog.dart';
import '../widgets/badges.dart';
import '../widgets/confirm_dialogs.dart';
import '../widgets/progress_timeline.dart';
import '../widgets/project_assets_panel.dart';
import '../widgets/section_title.dart';
import 'project_attachments_panel.dart';

/// 项目详情页：数据与操作均由父级注入（受控组件），
/// 自身仅持有项目的本地副本以驱动附件与进度修改。
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
  late ProjectData _project = widget.project;

  @override
  void didUpdateWidget(ProjectDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.project, widget.project) &&
        oldWidget.project != widget.project) {
      _project = widget.project;
    }
  }

  /// 保存项目并同步本地副本；父级保存失败时抛出，由调用方处理。
  Future<void> _save(ProjectData updated) async {
    await widget.onUpdateProject(updated);
    if (mounted) setState(() => _project = updated);
  }

  Future<void> _updateAttachments(
    List<AttachmentData> attachments,
    List<AttachmentCategory> categories,
  ) async {
    await _save(
      _project.copyWith(attachments: attachments, categories: categories),
    );
  }

  Future<void> _addProgress() async {
    final entry = await showDialog<ProjectProgressEntry>(
      context: context,
      builder: (_) => ProgressDialog(currentProgress: _project.progress),
    );
    if (entry == null || !mounted) return;
    await _save(
      _project.copyWith(progressEntries: [..._project.progressEntries, entry]),
    );
  }

  Future<void> _editProgress(ProjectProgressEntry entry) async {
    final saved = await showDialog<ProjectProgressEntry>(
      context: context,
      builder: (_) =>
          ProgressDialog(currentProgress: _project.progress, entry: entry),
    );
    if (saved == null || !mounted) return;
    await _save(
      _project.copyWith(
        progressEntries: [
          for (final item in _project.progressEntries)
            item.id == saved.id ? saved : item,
        ],
      ),
    );
  }

  Future<void> _toggleTodo(TodoData todo) async {
    if (!todo.done) {
      await widget.onToggleTodo(todo);
      return;
    }
    final confirmed = await showConfirmDialog(
      context,
      title: '取消完成',
      content: '将待办“${todo.title}”标记为未完成，可继续编辑。',
      confirmLabel: '确定',
    );
    if (confirmed && mounted) {
      await widget.onToggleTodo(todo);
    }
  }

  Future<void> _toggleSubTodo(TodoData todo, SubTodoData sub) =>
      widget.onToggleSubTodo(todo, sub);

  Future<void> _addTodo() => widget.onAddTodo(_project);

  Future<void> _openTodo(TodoData todo) => widget.onOpenTodo(todo);

  Future<void> _viewAsset(AssetData asset) async {
    final editRequested = await showDialog<bool>(
      context: context,
      builder: (_) =>
          AssetDetailDialog(asset: asset, assetTags: widget.assetTags),
    );
    if (editRequested == true && mounted) {
      await widget.onEditAsset(asset);
    }
  }

  Future<void> _deleteTodo(TodoData todo) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除待办',
      content: '确定删除待办“${todo.title}”吗？',
      confirmLabel: '删除',
      confirmColor: CardoryColors.error,
    );
    if (!confirmed || !mounted) return;
    await widget.onDeleteTodo(todo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _project.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    PriorityBadge(priority: _project.priority),
                    const SizedBox(width: 8),
                    StageBadge(stage: _project.stage),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _project.description.isEmpty
                      ? '暂无项目描述'
                      : _project.description,
                  style: TextStyle(color: CardoryColors.gray700, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addProgress,
                  icon: const Icon(Icons.add),
                  label: const Text('新增进度'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addTodo,
                  icon: const Icon(Icons.add_task_outlined),
                  label: const Text('新建待办'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ProjectAttachmentsPanel(
            attachments: _project.attachments,
            categories: _project.categories,
            repository: widget.attachmentStore,
            renameOnUpload: widget.renameAttachmentsOnUpload,
            keepExtensionOnRename: widget.keepAttachmentExtensionOnRename,
            onChanged: _updateAttachments,
          ),
          const SizedBox(height: 16),
          ProjectAssetsPanel(
            assets: widget.assets,
            assetTags: widget.assetTags,
            onAdd: () async {
              await widget.onAddAsset();
            },
            onView: _viewAsset,
            onDelete: widget.onDeleteAsset,
            onUpdateAssetsTags: (assetIds, tagIds) async {
              await widget.onUpdateAssetsTags?.call(assetIds, tagIds);
            },
            onAddTag: (tag) async {
              return await widget.onAddAssetTag?.call(tag) ?? tag;
            },
            onUpdateTag: (tag) async {
              return await widget.onUpdateAssetTag?.call(tag) ?? tag;
            },
            onDeleteTag: (tagId) async {
              await widget.onDeleteAssetTag?.call(tagId);
            },
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1200;
              final progressPanel = Container(
                padding: const EdgeInsets.all(18),
                decoration: cardDecoration(),
                child: ProgressTimeline(
                  entries: _project.progressEntries,
                  onEdit: _editProgress,
                ),
              );
              final todoPanel = Container(
                padding: const EdgeInsets.all(18),
                decoration: cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(
                      title: '待办事项',
                      subtitle: '${widget.todos.length} 项',
                    ),
                    const SizedBox(height: 12),
                    for (
                      var index = 0;
                      index < widget.todos.length;
                      index++
                    ) ...[
                      _buildTodoTile(widget.todos[index]),
                      if (index < widget.todos.length - 1)
                        const Divider(height: 20),
                    ],
                  ],
                ),
              );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: progressPanel),
                    const SizedBox(width: 16),
                    Expanded(child: todoPanel),
                  ],
                );
              }
              return Column(
                children: [
                  progressPanel,
                  const SizedBox(height: 16),
                  todoPanel,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTodoTile(TodoData todo) {
    final tile = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(value: todo.done, onChanged: (_) => _toggleTodo(todo)),
      title: Text(
        todo.title,
        style: TextStyle(
          decoration: todo.done ? TextDecoration.lineThrough : null,
          color: todo.done ? CardoryColors.gray500 : null,
        ),
      ),
      subtitle: todo.subTodos.isNotEmpty
          ? Text('${todo.subTodos.length} 个子任务')
          : null,
      onTap: () => _openTodo(todo),
      trailing: PopupMenuButton<String>(
        tooltip: '待办操作',
        icon: const Icon(Icons.more_vert_rounded),
        onSelected: (value) {
          if (value == 'delete') _deleteTodo(todo);
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('删除待办'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tile,
        if (todo.subTodos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 42),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final sub in todo.subTodos)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: sub.done,
                    onChanged: (_) => _toggleSubTodo(todo, sub),
                    title: Text(
                      sub.content,
                      style: TextStyle(
                        fontSize: 13,
                        decoration: sub.done
                            ? TextDecoration.lineThrough
                            : null,
                        color: sub.done ? CardoryColors.gray500 : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
