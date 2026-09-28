// 甘特页三张管理卡片：里程碑、任务依赖与项目健康度（含共享卡片壳）。

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../../domain/milestone_models.dart';
import '../../domain/schedule_queries.dart';
import '../cardory_theme.dart';
import '../widgets/section_title.dart';

/// 里程碑管理卡片。
class MilestonesCard extends StatelessWidget {
  const MilestonesCard({
    super.key,
    required this.projects,
    required this.milestones,
    required this.now,
    required this.onAdd,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final List<ProjectData> projects;
  final List<MilestoneData> milestones;
  final DateTime now;
  final VoidCallback onAdd;
  final Future<void> Function(MilestoneData milestone) onEdit;
  final Future<void> Function(MilestoneData milestone) onToggle;
  final Future<void> Function(MilestoneData milestone) onDelete;

  String _projectTitle(String projectId) {
    for (final project in projects) {
      if (project.id == projectId) return project.title;
    }
    return '未知项目';
  }

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: SectionTitle(title: '里程碑', subtitle: '项目关键节点'),
            ),
            IconButton(
              tooltip: '新增里程碑',
              onPressed: onAdd,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (milestones.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '还没有里程碑，点击右上角新增。',
              style: TextStyle(fontSize: 13, color: CardoryColors.gray500),
            ),
          )
        else
          for (final milestone in milestones)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: Checkbox(
                      value: milestone.completed,
                      onChanged: (_) => onToggle(milestone),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onEdit(milestone),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              milestone.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: milestone.completed
                                    ? CardoryColors.gray400
                                    : CardoryColors.gray900,
                                decoration: milestone.completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            Text(
                              '${_projectTitle(milestone.projectId)} · ${formatDate(milestone.dueAt)}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: CardoryColors.gray500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!milestone.completed &&
                      localDayKey(milestone.dueAt).isBefore(now))
                    Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Text(
                        '已逾期',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: CardoryColors.error,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: '删除里程碑',
                    icon: Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: CardoryColors.gray400,
                    ),
                    onPressed: () => onDelete(milestone),
                  ),
                ],
              ),
            ),
      ],
    ),
  );
}

/// 任务依赖管理卡片。
class DependenciesCard extends StatelessWidget {
  const DependenciesCard({
    super.key,
    required this.todos,
    required this.todoTitles,
    required this.dependencies,
    required this.onAdd,
    required this.onDelete,
  });

  final List<TodoData> todos;
  final Map<String, String> todoTitles;
  final List<TaskDependencyData> dependencies;
  final Future<void> Function() onAdd;
  final Future<void> Function(TaskDependencyData dependency) onDelete;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: SectionTitle(title: '任务依赖', subtitle: '后继任务需在前置完成后开始'),
            ),
            IconButton(
              tooltip: '新增依赖',
              onPressed: onAdd,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (dependencies.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '还没有任务依赖关系，点击右上角新增。',
              style: TextStyle(fontSize: 13, color: CardoryColors.gray500),
            ),
          )
        else
          for (final dependency in dependencies)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${todoTitles[dependency.predecessorTaskId] ?? '未知任务'} → ${todoTitles[dependency.successorTaskId] ?? '未知任务'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: CardoryColors.gray800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '删除依赖',
                    icon: Icon(
                      Icons.link_off,
                      size: 16,
                      color: CardoryColors.gray400,
                    ),
                    onPressed: () => onDelete(dependency),
                  ),
                ],
              ),
            ),
      ],
    ),
  );
}

/// 项目健康度卡片：按逾期与临近截止任务评估，窄屏降级两行布局。
class HealthCard extends StatelessWidget {
  const HealthCard({
    super.key,
    required this.projects,
    required this.todos,
    required this.milestones,
    required this.now,
  });

  final List<ProjectData> projects;
  final List<TodoData> todos;
  final List<MilestoneData> milestones;
  final DateTime now;

  static final _healthLabels = {
    _Health.good: ('良好', Color(0xFF44B88A)),
    _Health.atRisk: ('风险', Color(0xFFF2A354)),
    _Health.lagging: ('滞后', CardoryColors.error),
    _Health.none: ('无任务', CardoryColors.gray400),
  };

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: '项目健康度', subtitle: '按逾期与临近截止任务评估'),
        const SizedBox(height: 12),
        if (projects.isEmpty)
          Text(
            '还没有项目。',
            style: TextStyle(fontSize: 13, color: CardoryColors.gray500),
          )
        else
          // 窄屏（<640px）五列横排会互相挤压截断，改为两行布局：
          // 第一行项目名 + 健康度徽标，第二行进度 / 待办 / 里程碑明细。
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 640;
              return Column(
                children: [
                  for (final project in projects)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: compact
                          ? _NarrowHealthRow(
                              title: project.title,
                              progressText:
                                  '进度 ${(project.progress * 100).toStringAsFixed(0)}%',
                              taskText: _taskSummary(project),
                              milestoneText: _milestoneSummary(project),
                              badge: _healthBadge(project),
                            )
                          : _WideHealthRow(
                              title: project.title,
                              progressText:
                                  '进度 ${(project.progress * 100).toStringAsFixed(0)}%',
                              taskText: _taskSummary(project),
                              milestoneText: _milestoneSummary(project),
                              badge: _healthBadge(project),
                            ),
                    ),
                ],
              );
            },
          ),
      ],
    ),
  );

  String _taskSummary(ProjectData project) {
    final projectTodos = todos
        .where((todo) => todo.projectId == project.id)
        .toList();
    final done = projectTodos.where((todo) => todo.done).length;
    return '待办 $done/${projectTodos.length}';
  }

  String _milestoneSummary(ProjectData project) {
    final projectMilestones = milestones
        .where((milestone) => milestone.projectId == project.id)
        .toList();
    final done = projectMilestones
        .where((milestone) => milestone.completed)
        .length;
    return '里程碑 $done/${projectMilestones.length}';
  }

  Widget _healthBadge(ProjectData project) {
    final projectTodos = todos.where((todo) => todo.projectId == project.id);
    final overdue = projectTodos.where((todo) => isOverdue(todo, now)).length;
    final soon = projectTodos.where((todo) {
      if (todo.done || todo.endDate == null) return false;
      final due = localDayKey(todo.endDate!);
      final diff = due.difference(now).inDays;
      return diff >= 0 && diff <= 7;
    }).length;
    final health = projectTodos.isEmpty
        ? _Health.none
        : overdue > 0
        ? _Health.lagging
        : soon > 0
        ? _Health.atRisk
        : _Health.good;
    final (label, color) = _healthLabels[health]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

enum _Health { good, atRisk, lagging, none }

/// 甘特页卡片统一壳：内边距 + cardDecoration。
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: cardDecoration(),
    child: child,
  );
}

/// 宽屏健康度行：项目名 / 进度 / 待办 / 里程碑 / 健康度 五列横排。
class _WideHealthRow extends StatelessWidget {
  const _WideHealthRow({
    required this.title,
    required this.progressText,
    required this.taskText,
    required this.milestoneText,
    required this.badge,
  });

  final String title;
  final String progressText;
  final String taskText;
  final String milestoneText;
  final Widget badge;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        flex: 3,
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: CardoryColors.gray900,
          ),
        ),
      ),
      Expanded(
        flex: 2,
        child: Text(
          progressText,
          style: TextStyle(fontSize: 12.5, color: CardoryColors.gray600),
        ),
      ),
      Expanded(
        flex: 2,
        child: Text(
          taskText,
          style: TextStyle(fontSize: 12.5, color: CardoryColors.gray600),
        ),
      ),
      Expanded(
        flex: 2,
        child: Text(
          milestoneText,
          style: TextStyle(fontSize: 12.5, color: CardoryColors.gray600),
        ),
      ),
      Expanded(flex: 2, child: badge),
    ],
  );
}

/// 窄屏健康度行：两行布局避免五列互相挤压截断。
class _NarrowHealthRow extends StatelessWidget {
  const _NarrowHealthRow({
    required this.title,
    required this.progressText,
    required this.taskText,
    required this.milestoneText,
    required this.badge,
  });

  final String title;
  final String progressText;
  final String taskText;
  final String milestoneText;
  final Widget badge;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: CardoryColors.gray900,
              ),
            ),
          ),
          const SizedBox(width: 8),
          badge,
        ],
      ),
      const SizedBox(height: 4),
      Text(
        '$progressText · $taskText · $milestoneText',
        style: TextStyle(fontSize: 12, color: CardoryColors.gray600),
      ),
    ],
  );
}
