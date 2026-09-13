// 时间记录与番茄钟的领域模型（投影给界面使用）。

/// 一段时间记录；[endedAt] 为 null 表示正在计时的未闭合区间。
class TimeEntryData {
  const TimeEntryData({
    required this.id,
    required this.startedAt,
    required this.durationSeconds,
    this.endedAt,
    this.projectId,
    this.taskId,
    this.source = 'manual',
    this.note = '',
  });

  final String id;

  /// 开始时刻（本地时间）。
  final DateTime startedAt;

  /// 结束时刻；null 表示计时中。
  final DateTime? endedAt;

  /// 已记录秒数（计时中为已完成区间的秒数，通常为 0）。
  final int durationSeconds;
  final String? projectId;
  final String? taskId;

  /// 来源：manual（手动）/ timer（专注计时器）/ pomodoro（番茄钟）。
  final String source;
  final String note;

  bool get isRunning => endedAt == null;

  /// 展示用时长：计时中按当前时刻推算。
  int elapsedSeconds(DateTime now) =>
      isRunning ? now.difference(startedAt).inSeconds : durationSeconds;

  TimeEntryData copyWith({
    DateTime? startedAt,
    DateTime? endedAt,
    int? durationSeconds,
    String? projectId,
    String? taskId,
    String? source,
    String? note,
  }) => TimeEntryData(
    id: id,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    projectId: projectId ?? this.projectId,
    taskId: taskId ?? this.taskId,
    source: source ?? this.source,
    note: note ?? this.note,
  );
}

/// 一次番茄钟会话；[endedAt] 为 null 表示会话进行中。
class PomodoroSessionData {
  const PomodoroSessionData({
    required this.id,
    required this.mode,
    required this.plannedSeconds,
    required this.startedAt,
    this.endedAt,
    this.actualSeconds,
    this.completed = false,
    this.projectId,
    this.taskId,
  });

  final String id;

  /// focus / shortBreak / longBreak。
  final String mode;
  final int plannedSeconds;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? actualSeconds;
  final bool completed;
  final String? projectId;
  final String? taskId;

  bool get isRunning => endedAt == null;

  PomodoroSessionData copyWith({
    DateTime? startedAt,
    DateTime? endedAt,
    int? actualSeconds,
    bool? completed,
    String? projectId,
    String? taskId,
  }) => PomodoroSessionData(
    id: id,
    mode: mode,
    plannedSeconds: plannedSeconds,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    actualSeconds: actualSeconds ?? this.actualSeconds,
    completed: completed ?? this.completed,
    projectId: projectId ?? this.projectId,
    taskId: taskId ?? this.taskId,
  );
}
