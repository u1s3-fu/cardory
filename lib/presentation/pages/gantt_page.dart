// 甘特时间线页面：项目/任务起止日期排期、里程碑、任务依赖与项目健康度。
//
// 子组件拆分在同目录：gantt_timeline / gantt_cards / gantt_dialogs。

import 'package:flutter/material.dart';

import '../../application/row_level_workspace_store.dart';
import '../../domain/cardory_models.dart';
import '../../domain/milestone_models.dart';
import '../../domain/schedule_queries.dart';
import '../widgets/confirm_dialogs.dart';
import 'gantt_cards.dart';
import 'gantt_dialogs.dart';
import 'gantt_timeline.dart';

export 'gantt_dialogs.dart' show DependencyDialog, MilestoneDialog;

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
  Widget build(BuildContext context) =>
      // stretch：所有卡片横向撑满内容区。时间线与健康度卡片内部没有
      // 能撑宽的 Row，用 start 会让它们收缩成文字自然宽度。
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GanttTimeline(
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
          MilestonesCard(
            projects: widget.projects,
            milestones: _milestones,
            now: _now,
            onAdd: _addMilestone,
            onEdit: _editMilestone,
            onToggle: _toggleMilestone,
            onDelete: _deleteMilestone,
          ),
          const SizedBox(height: 16),
          DependenciesCard(
            todos: widget.todos,
            todoTitles: _todoTitles,
            dependencies: _dependencies,
            onAdd: _addDependency,
            onDelete: _deleteDependency,
          ),
          const SizedBox(height: 16),
          HealthCard(
            projects: widget.projects,
            todos: widget.todos,
            milestones: _milestones,
            now: _now,
          ),
        ],
      );

  /// 存储操作统一兜底：失败提示 SnackBar，不让异常静默丢失。
  Future<void> _guard(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      debugPrint('Cardory gantt storage failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('操作未完成，请重试。')));
      }
    }
  }

  Future<void> _addMilestone() async {
    final result = await showDialog<MilestoneData>(
      context: context,
      builder: (_) => MilestoneDialog(projects: widget.projects, now: _now),
    );
    if (result == null) return;
    await _guard(() async {
      await widget.store.addMilestone(result);
      await _reload();
    });
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
    await _guard(() async {
      await widget.store.updateMilestone(result);
      await _reload();
    });
  }

  Future<void> _toggleMilestone(MilestoneData milestone) => _guard(() async {
    await widget.store.updateMilestone(
      milestone.copyWith(
        completed: !milestone.completed,
        completedAt: !milestone.completed ? _now : null,
        clearCompletedAt: milestone.completed,
      ),
    );
    await _reload();
  });

  Future<void> _deleteMilestone(MilestoneData milestone) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除里程碑',
      content: '确定删除里程碑“${milestone.title}”吗？',
      confirmLabel: '删除',
    );
    if (confirmed != true) return;
    await _guard(() async {
      await widget.store.deleteMilestone(milestone.id);
      await _reload();
    });
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

  Future<void> _deleteDependency(TaskDependencyData dependency) =>
      _guard(() async {
        await widget.store.deleteDependency(dependency.id);
        await _reload();
      });
}
