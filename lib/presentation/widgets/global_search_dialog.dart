// 全局搜索对话框：按标题关键词检索项目/待办/资产/里程碑并跳转。
//
// 检索范围即当前投影（_data）与一次性加载的里程碑；数据量以单用户
// 本地库为量级，直接内存过滤、按类型分组展示，每类最多返回 20 条。

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../../domain/milestone_models.dart';
import '../cardory_theme.dart';

/// 搜索结果类型（私有枚举仅在本文件内分发使用）。
enum SearchHitKind { project, todo, asset, milestone }

/// 一条搜索结果：[entity] 为 ProjectData / TodoData / AssetData /
/// MilestoneData 之一，由 [GlobalSearchDialog._open] 按类型分发。
class SearchHit {
  const SearchHit._({
    required this.kind,
    required this.label,
    required this.entity,
    this.detail,
  });

  final SearchHitKind kind;
  final String label;
  final Object entity;
  final String? detail;

  String get kindLabel => switch (kind) {
    SearchHitKind.project => '项目',
    SearchHitKind.todo => '待办',
    SearchHitKind.asset => '资产',
    SearchHitKind.milestone => '里程碑',
  };

  IconData get icon => switch (kind) {
    SearchHitKind.project => Icons.folder_outlined,
    SearchHitKind.todo => Icons.check_circle_outline,
    SearchHitKind.asset => Icons.inventory_2_outlined,
    SearchHitKind.milestone => Icons.flag_outlined,
  };
}

class GlobalSearchDialog extends StatefulWidget {
  const GlobalSearchDialog({
    super.key,
    required this.projects,
    required this.todos,
    required this.assets,
    required this.loadMilestones,
    required this.onOpenProject,
    required this.onOpenTodo,
    required this.onOpenAsset,
    required this.onOpenGantt,
  });

  final List<ProjectData> projects;
  final List<TodoData> todos;
  final List<AssetData> assets;
  final Future<List<MilestoneData>> Function() loadMilestones;
  final void Function(ProjectData project) onOpenProject;
  final Future<TodoData?> Function(TodoData todo) onOpenTodo;
  final Future<AssetData?> Function(AssetData asset) onOpenAsset;
  final VoidCallback onOpenGantt;

  static Future<void> show(BuildContext context, GlobalSearchDialog dialog) =>
      showDialog<void>(context: context, builder: (_) => dialog);

  @override
  State<GlobalSearchDialog> createState() => _GlobalSearchDialogState();
}

class _GlobalSearchDialogState extends State<GlobalSearchDialog> {
  String _query = '';
  List<MilestoneData>? _milestones;
  static const _limitPerKind = 20;

  @override
  void initState() {
    super.initState();
    widget.loadMilestones().then(
      (value) {
        if (mounted) setState(() => _milestones = value);
      },
      onError: (_) {
        if (mounted) setState(() => _milestones = const []);
      },
    );
  }

  List<SearchHit> get _hits {
    final needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    bool matches(String title) => title.toLowerCase().contains(needle);
    return [
      for (final project
          in widget.projects
              .where((project) => matches(project.title))
              .take(_limitPerKind))
        SearchHit._(
          kind: SearchHitKind.project,
          label: project.title,
          entity: project,
          detail: project.description.isEmpty ? null : project.description,
        ),
      for (final todo
          in widget.todos
              .where((todo) => matches(todo.title))
              .take(_limitPerKind))
        SearchHit._(
          kind: SearchHitKind.todo,
          label: todo.title,
          entity: todo,
          detail: '${todo.projectTitle} · ${todo.dateRangeText}',
        ),
      for (final asset
          in widget.assets
              .where((asset) => matches(asset.name))
              .take(_limitPerKind))
        SearchHit._(
          kind: SearchHitKind.asset,
          label: asset.name,
          entity: asset,
          detail: asset.note.isEmpty ? null : asset.note,
        ),
      for (final milestone
          in (_milestones ?? const <MilestoneData>[])
              .where((milestone) => matches(milestone.title))
              .take(_limitPerKind))
        SearchHit._(
          kind: SearchHitKind.milestone,
          label: milestone.title,
          entity: milestone,
          detail: '截止 ${formatDate(milestone.dueAt)}',
        ),
    ];
  }

  Future<void> _open(SearchHit hit) async {
    Navigator.of(context).pop();
    switch (hit.kind) {
      case SearchHitKind.project:
        widget.onOpenProject(hit.entity as ProjectData);
      case SearchHitKind.todo:
        await widget.onOpenTodo(hit.entity as TodoData);
      case SearchHitKind.asset:
        await widget.onOpenAsset(hit.entity as AssetData);
      case SearchHitKind.milestone:
        widget.onOpenGantt();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    return AlertDialog(
      title: const Text('搜索'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('global-search-field'),
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: '搜索项目、待办、资产、里程碑…',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            if (_query.trim().isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    '输入关键词开始检索',
                    style: TextStyle(
                      color: CardoryColors.gray500,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else if (hits.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    '没有匹配的结果',
                    style: TextStyle(
                      color: CardoryColors.gray500,
                      fontSize: 13,
                    ),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: hits.length,
                  itemBuilder: (context, index) {
                    final hit = hits[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(hit.icon, size: 20),
                      title: Text(
                        hit.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: hit.detail == null
                          ? null
                          : Text(
                              hit.detail!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: CardoryColors.gray500,
                                fontSize: 12,
                              ),
                            ),
                      trailing: Text(
                        hit.kindLabel,
                        style: TextStyle(
                          color: CardoryColors.gray500,
                          fontSize: 11.5,
                        ),
                      ),
                      onTap: () => _open(hit),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
