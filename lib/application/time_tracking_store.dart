// 时间记录与番茄钟的行级存储契约（与 RowLevelWorkspaceStore 并列）。
//
// 运行中状态不得离开本机：番茄钟会话在 finish 前不产生 sync_changes
// 审计（见 PomodoroSessionRepository.start），计时中（endedAt 为 null）
// 的时间记录同样只存在于本地库。

import '../domain/time_models.dart';

/// 每次调用返回当前会话的时间存储；保险库未解锁时返回 null。
typedef TimeTrackingStoreBuilder = TimeTrackingStore? Function();

abstract interface class TimeTrackingStore {
  // 读取。

  /// 最近的时间记录（按开始时间倒序）。
  Future<List<TimeEntryData>> loadEntries({int limit});

  /// 未闭合（计时中）的时间记录。
  Future<List<TimeEntryData>> loadOpenEntries();

  /// 进行中的番茄钟会话（至多一个）。
  Future<PomodoroSessionData?> loadRunningSession();

  /// 最近的番茄钟会话（按开始时间倒序）。
  Future<List<PomodoroSessionData>> loadSessions({int limit});

  // 专注计时器与手动记录（time_entries）。

  /// 开始一段计时（source 默认 timer）。
  Future<TimeEntryData> startEntry({
    String? projectId,
    String? taskId,
    String note = '',
    String source = 'timer',
    DateTime? startedAt,
  });

  /// 结束一段计时，写入 endedAt 与实际时长。
  Future<TimeEntryData> stopEntry(String id, {required DateTime endedAt});

  /// 手动补记一段完整区间（source 默认 manual，番茄钟收尾传 pomodoro）。
  Future<TimeEntryData> createEntry({
    required DateTime startedAt,
    required DateTime endedAt,
    String? projectId,
    String? taskId,
    String note = '',
    String source = 'manual',
  });

  Future<void> updateEntry(TimeEntryData entry);
  Future<void> deleteEntry(String id);

  // 番茄钟（pomodoro_sessions）。

  /// 开始会话（进行中的会话只写本地行，不产生同步审计）。
  Future<PomodoroSessionData> startSession({
    required String mode,
    required int plannedSeconds,
    String? projectId,
    String? taskId,
    DateTime? startedAt,
  });

  /// 结束会话；完成时由调用方另行写入对应的 time_entry。
  Future<PomodoroSessionData> finishSession(
    String id, {
    required bool completed,
    required int actualSeconds,
    required DateTime endedAt,
  });

  Future<void> deleteSession(String id);
}
