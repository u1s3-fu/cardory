// 里程碑与任务依赖的领域模型（甘特/排期模块）。

/// 项目里程碑。
class MilestoneData {
  const MilestoneData({
    required this.id,
    required this.projectId,
    required this.title,
    required this.dueAt,
    this.note = '',
    this.completed = false,
    this.completedAt,
  });

  final String id;
  final String projectId;
  final String title;
  final String note;

  /// 截止日期（本地时间）。
  final DateTime dueAt;
  final bool completed;
  final DateTime? completedAt;

  MilestoneData copyWith({
    String? title,
    String? note,
    DateTime? dueAt,
    bool? completed,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) => MilestoneData(
    id: id,
    projectId: projectId,
    title: title ?? this.title,
    note: note ?? this.note,
    dueAt: dueAt ?? this.dueAt,
    completed: completed ?? this.completed,
    completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
  );
}

/// 任务依赖（finish_to_start）：后继任务需在前置任务完成后开始。
class TaskDependencyData {
  const TaskDependencyData({
    required this.id,
    required this.predecessorTaskId,
    required this.successorTaskId,
  });

  final String id;
  final String predecessorTaskId;
  final String successorTaskId;
}
