// 甘特时间线页面：项目/任务起止日期排期、里程碑、任务依赖与项目健康度。

import 'package:flutter/material.dart';

import '../../application/row_level_workspace_store.dart';
import '../../domain/cardory_models.dart';
import '../../domain/milestone_models.dart';
import '../../domain/schedule_queries.dart';
import '../cardory_theme.dart';
import '../model_colors.dart';
import '../widgets/confirm_dialogs.dart';
import '../widgets/section_title.dart';

class GanttPage extends StatefulWidget {
  const GanttPage({
    super.key,
    required this.store,
    required this.projects,
    required this.todos,
    required this.onEditTodo,
    this.now,
  });

  final RowLevelWorkspaceStore store;
  final List<ProjectData> projects;
  final List<TodoData> todos;

  /// 打开待办编辑对话框（排期调整入口：开始/截止日期）。
  final Future<TodoData?> Function(TodoData todo) onEditTodo;

  /// 当前时间（测试可注入固定值）。
  final DateTime? now;

  @override
  State<GanttPage> createState() => _GanttPageState();
}

class _GanttPageState extends State<GanttPage> {
  List<MilestoneData> _milestones = [];
  List<TaskDependencyData> _dependencies = [];

  DateTime get _now => localDayKey(widget.now ?? DateTime.now());

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final milestones = await widget.store.loadMilestones();
    final dependencies = await widget.store.loadDependencies();
    if (!mounted) return;
    setState(() {
      _milestones = milestones;
      _dependencies = dependencies;
    });
  }

  Map<String, String> get _todoTitles => {
    for (final todo in widget.todos) todo.id: todo.title,
  };

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _GanttTimeline(
        projects: widget.projects,
        todos: widget.todos,
        milestones: _milestones,
        now: _now,
        onSelectTodo: (todo) async {
          await widget.onEditTodo(todo);
          await _reload();
        },
      ),
      const SizedBox(height: 16),
      _MilestonesCard(
        projects: widget.projects,
        milestones: _milestones,
        now: _now,
        onAdd: _addMilestone,
        onEdit: _editMilestone,
        onToggle: _toggleMilestone,
        onDelete: _deleteMilestone,
      ),
      const SizedBox(height: 16),
      _DependenciesCard(
        todos: widget.todos,
        todoTitles: _todoTitles,
        dependencies: _dependencies,
        onAdd: _addDependency,
        onDelete: _deleteDependency,
      ),
      const SizedBox(height: 16),
      _HealthCard(
        projects: widget.projects,
        todos: widget.todos,
        milestones: _milestones,
        now: _now,
      ),
    ],
  );

  Future<void> _addMilestone() async {
    final result = await showDialog<MilestoneData>(
      context: context,
      builder: (_) => MilestoneDialog(projects: widget.projects, now: _now),
    );
    if (result == null) return;
    await widget.store.addMilestone(result);
    await _reload();
  }

  Future<void> _editMilestone(MilestoneData milestone) async {
    final result = await showDialog<MilestoneData>(
      context: context,
      builder: (_) => MilestoneDialog(
        projects: widget.projects,
        milestone: milestone,
        now: _now,
      ),
    );
    if (result == null) return;
    await widget.store.updateMilestone(result);
    await _reload();
  }

  Future<void> _toggleMilestone(MilestoneData milestone) async {
    await widget.store.updateMilestone(
      milestone.copyWith(
        completed: !milestone.completed,
        completedAt: !milestone.completed ? _now : null,
        clearCompletedAt: milestone.completed,
      ),
    );
    await _reload();
  }

  Future<void> _deleteMilestone(MilestoneData milestone) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除里程碑',
      content: '确定删除里程碑“${milestone.title}”吗？',
      confirmLabel: '删除',
    );
    if (confirmed != true) return;
    await widget.store.deleteMilestone(milestone.id);
    await _reload();
  }

  Future<void> _addDependency() async {
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => DependencyDialog(todos: widget.todos),
    );
    if (result == null) return;
    try {
      await widget.store.addDependency(
        predecessorTaskId: result.$1,
        successorTaskId: result.$2,
      );
    } on StateError catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }
    await _reload();
  }

  Future<void> _deleteDependency(TaskDependencyData dependency) async {
    await widget.store.deleteDependency(dependency.id);
    await _reload();
  }
}

// ---- 甘特时间线 ----

class _GanttTimeline extends StatelessWidget {
  const _GanttTimeline({
    required this.projects,
    required this.todos,
    required this.milestones,
    required this.now,
    required this.onSelectTodo,
  });

  final List<ProjectData> projects;
  final List<TodoData> todos;
  final List<MilestoneData> milestones;
  final DateTime now;
  final Future<void> Function(TodoData todo) onSelectTodo;

  static const _dayWidth = 22.0;
  static const _rowHeight = 34.0;
  static const _labelWidth = 170.0;

  @override
  Widget build(BuildContext context) {
    // 时间窗口：最早/最晚日期与今天的并集，两侧各留 3 天。
    final dated = <DateTime>[now];
    for (final project in projects) {
      if (project.startDate != null) dated.add(localDayKey(project.startDate!));
      if (project.endDate != null) dated.add(localDayKey(project.endDate!));
    }
    for (final todo in todos) {
      if (todo.startDate != null) dated.add(localDayKey(todo.startDate!));
      if (todo.endDate != null) dated.add(localDayKey(todo.endDate!));
    }
    for (final milestone in milestones) {
      dated.add(localDayKey(milestone.dueAt));
    }
    var start = dated
        .reduce((a, b) => a.isBefore(b) ? a : b)
        .subtract(const Duration(days: 3));
    var end = dated
        .reduce((a, b) => a.isAfter(b) ? a : b)
        .add(const Duration(days: 3));
    final totalDays = end.difference(start).inDays + 1;
    if (totalDays > 240) {
      // 防御极端日期：窗口过宽时向今天收拢。
      start = now.subtract(const Duration(days: 90));
      end = now.add(const Duration(days: 149));
    }

    final milestonesByProject = {
      for (final milestone in milestones)
        milestone.projectId: <MilestoneData>[],
    };
    for (final milestone in milestones) {
      milestonesByProject
          .putIfAbsent(milestone.projectId, () => [])
          .add(milestone);
    }

    final rows = <Widget>[];
    for (final project in projects) {
      rows.add(
        _GanttBar(
          label: project.title,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          start: project.startDate,
          end: project.endDate,
          color: project.stage.color,
          windowStart: start,
          dayWidth: _dayWidth,
          height: _rowHeight,
          markers: [
            for (final milestone
                in milestonesByProject[project.id] ?? const <MilestoneData>[])
              _BarMarker(
                day: localDayKey(milestone.dueAt),
                label: milestone.title,
                color: milestone.completed
                    ? CardoryColors.gray400
                    : CardoryColors.gray800,
              ),
          ],
        ),
      );
      final projectTodos =
          todos.where((todo) => todo.projectId == project.id).toList()..sort(
            (a, b) => (a.endDate ?? a.startDate ?? now).compareTo(
              b.endDate ?? b.startDate ?? now,
            ),
          );
      for (final todo in projectTodos) {
        rows.add(
          _GanttBar(
            label: todo.title,
            indent: true,
            start: todo.startDate ?? todo.endDate,
            end: todo.endDate ?? todo.startDate,
            color: todo.done ? CardoryColors.gray300 : const Color(0xFF6B9EDF),
            windowStart: start,
            dayWidth: _dayWidth,
            height: _rowHeight,
            onTap: () => onSelectTodo(todo),
          ),
        );
      }
    }

    final timelineWidth = totalDays * _dayWidth;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            title: '甘特时间线',
            subtitle: '项目与任务起止排期，◆ 为里程碑，点击任务条调整日期',
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '还没有项目，先在看板新建项目。',
                style: TextStyle(fontSize: 13, color: CardoryColors.gray500),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: _labelWidth + timelineWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TimelineHeader(
                        windowStart: start,
                        totalDays: totalDays,
                        dayWidth: _dayWidth,
                        labelWidth: _labelWidth,
                      ),
                      for (final row in rows) row,
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({
    required this.windowStart,
    required this.totalDays,
    required this.dayWidth,
    required this.labelWidth,
  });

  final DateTime windowStart;
  final int totalDays;
  final double dayWidth;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final monthMarks = <(int, String)>[];
    for (var day = 0; day < totalDays; day++) {
      final date = windowStart.add(Duration(days: day));
      if (date.day == 1) {
        monthMarks.add((day, '${date.year}/${date.month}'));
      }
    }
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          SizedBox(width: labelWidth),
          Expanded(
            child: Stack(
              children: [
                for (final (day, label) in monthMarks)
                  Positioned(
                    left: day * dayWidth,
                    top: 0,
                    bottom: 0,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: CardoryColors.gray500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarMarker {
  const _BarMarker({
    required this.day,
    required this.label,
    required this.color,
  });

  final DateTime day;
  final String label;
  final Color color;
}

class _GanttBar extends StatelessWidget {
  const _GanttBar({
    required this.label,
    required this.start,
    required this.end,
    required this.color,
    required this.windowStart,
    required this.dayWidth,
    required this.height,
    this.labelStyle,
    this.indent = false,
    this.markers = const [],
    this.onTap,
  });

  final String label;
  final DateTime? start;
  final DateTime? end;
  final Color color;
  final DateTime windowStart;
  final double dayWidth;
  final double height;
  final TextStyle? labelStyle;
  final bool indent;
  final List<_BarMarker> markers;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final barStart = start == null ? null : localDayKey(start!);
    final barEnd = end == null ? null : localDayKey(end!);
    final left = barStart == null
        ? null
        : barStart.difference(windowStart).inDays * dayWidth;
    final width = barStart == null || barEnd == null
        ? null
        : ((barEnd.difference(barStart).inDays + 1) * dayWidth - 2).clamp(
            4.0,
            double.infinity,
          );

    return SizedBox(
      height: height,
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: Padding(
              padding: EdgeInsets.only(left: indent ? 18 : 2),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (labelStyle ?? const TextStyle()).copyWith(
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: height - 6,
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: CardoryColors.gray100,
                        width: 0.5,
                      ),
                    ),
                  ),
                ),
                if (left != null && width != null)
                  Positioned(
                    left: left,
                    top: (height - 16) / 2,
                    child: GestureDetector(
                      onTap: onTap,
                      child: Tooltip(
                        message:
                            '$label（${formatDate(start!)} ~ ${formatDate(end!)}）',
                        child: Container(
                          width: width,
                          height: 16,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  )
                else if (left != null)
                  Positioned(
                    left: left,
                    top: (height - 10) / 2,
                    child: Tooltip(
                      message: '$label（仅截止 ${formatDate(start!)}）',
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                for (final marker in markers)
                  Positioned(
                    left:
                        marker.day.difference(windowStart).inDays * dayWidth +
                        dayWidth / 2 -
                        5,
                    top: 2,
                    child: Tooltip(
                      message: '◆ ${marker.label}',
                      child: Text(
                        '◆',
                        style: TextStyle(
                          fontSize: 10,
                          color: marker.color,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- 里程碑管理 ----

class _MilestonesCard extends StatelessWidget {
  const _MilestonesCard({
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

// ---- 任务依赖 ----

class _DependenciesCard extends StatelessWidget {
  const _DependenciesCard({
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

// ---- 项目健康度 ----

enum _Health { good, atRisk, lagging, none }

class _HealthCard extends StatelessWidget {
  const _HealthCard({
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
          for (final project in projects)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      project.title,
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
                      '进度 ${(project.progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: CardoryColors.gray600,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _taskSummary(project),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: CardoryColors.gray600,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      _milestoneSummary(project),
                      style: TextStyle(
                        fontSize: 12.5,
                        color: CardoryColors.gray600,
                      ),
                    ),
                  ),
                  Expanded(flex: 2, child: _healthBadge(project)),
                ],
              ),
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

// ---- 对话框 ----

/// 新增 / 编辑里程碑。
class MilestoneDialog extends StatefulWidget {
  const MilestoneDialog({
    super.key,
    required this.projects,
    required this.now,
    this.milestone,
  });

  final List<ProjectData> projects;
  final MilestoneData? milestone;
  final DateTime now;

  @override
  State<MilestoneDialog> createState() => _MilestoneDialogState();
}

class _MilestoneDialogState extends State<MilestoneDialog> {
  late String? _projectId = widget.milestone?.projectId;
  late final TextEditingController _titleController = TextEditingController(
    text: widget.milestone?.title ?? '',
  );
  late final TextEditingController _noteController = TextEditingController(
    text: widget.milestone?.note ?? '',
  );
  late DateTime _dueAt = widget.milestone?.dueAt ?? widget.now;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt,
      firstDate: minPickerDate,
      lastDate: maxPickerDate,
    );
    if (picked != null) setState(() => _dueAt = picked);
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty || _projectId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择项目并填写里程碑名称。')));
      return;
    }
    Navigator.of(context).pop(
      (widget.milestone ??
              MilestoneData(
                id: '',
                projectId: _projectId!,
                title: title,
                dueAt: _dueAt,
              ))
          .copyWith(
            title: title,
            dueAt: _dueAt,
            note: _noteController.text.trim(),
          ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.milestone == null ? '新增里程碑' : '编辑里程碑'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _projectId,
            decoration: const InputDecoration(labelText: '所属项目'),
            items: [
              for (final project in widget.projects)
                DropdownMenuItem(value: project.id, child: Text(project.title)),
            ],
            onChanged: (value) => setState(() => _projectId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: '里程碑名称'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '目标日期 ${formatDate(_dueAt)}',
                style: TextStyle(fontSize: 13, color: CardoryColors.gray700),
              ),
              const Spacer(),
              TextButton(onPressed: _pickDate, child: const Text('选择日期')),
            ],
          ),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(labelText: '备注（可选）'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('保存')),
    ],
  );
}

/// 新增任务依赖：选择前置与后继任务。
class DependencyDialog extends StatefulWidget {
  const DependencyDialog({super.key, required this.todos});

  final List<TodoData> todos;

  @override
  State<DependencyDialog> createState() => _DependencyDialogState();
}

class _DependencyDialogState extends State<DependencyDialog> {
  String? _predecessorId;
  String? _successorId;

  void _submit() {
    if (_predecessorId == null || _successorId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择前置与后继任务。')));
      return;
    }
    Navigator.of(context).pop((_predecessorId!, _successorId!));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新增任务依赖'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _predecessorId,
            decoration: const InputDecoration(labelText: '前置任务（先完成）'),
            items: [
              for (final todo in widget.todos)
                DropdownMenuItem(value: todo.id, child: Text(todo.title)),
            ],
            onChanged: (value) => setState(() => _predecessorId = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _successorId,
            decoration: const InputDecoration(labelText: '后继任务（后开始）'),
            items: [
              for (final todo in widget.todos)
                DropdownMenuItem(value: todo.id, child: Text(todo.title)),
            ],
            onChanged: (value) => setState(() => _successorId = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('保存')),
    ],
  );
}
