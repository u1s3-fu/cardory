// TimeTrackingStore 的内存实现（仅测试用）：直接维护内存清单。

import 'package:cardory/application/time_tracking_store.dart';
import 'package:cardory/domain/time_models.dart';

class InMemoryTimeTrackingStore implements TimeTrackingStore {
  final List<TimeEntryData> entries = [];
  final List<PomodoroSessionData> sessions = [];
  int _seq = 0;

  String get _nextId => 'time-${++_seq}';

  @override
  Future<List<TimeEntryData>> loadEntries({int limit = 200}) async =>
      List.of(entries)..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  @override
  Future<List<TimeEntryData>> loadOpenEntries() async =>
      entries.where((entry) => entry.isRunning).toList();

  @override
  Future<PomodoroSessionData?> loadRunningSession() async {
    for (final session in sessions) {
      if (session.isRunning) return session;
    }
    return null;
  }

  @override
  Future<List<PomodoroSessionData>> loadSessions({int limit = 100}) async =>
      List.of(sessions)..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  @override
  Future<TimeEntryData> startEntry({
    String? projectId,
    String? taskId,
    String note = '',
    String source = 'timer',
    DateTime? startedAt,
  }) async {
    final entry = TimeEntryData(
      id: _nextId,
      startedAt: startedAt ?? DateTime.now(),
      durationSeconds: 0,
      projectId: projectId,
      taskId: taskId,
      source: source,
      note: note,
    );
    entries.add(entry);
    return entry;
  }

  @override
  Future<TimeEntryData> stopEntry(
    String id, {
    required DateTime endedAt,
  }) async {
    final index = entries.indexWhere((entry) => entry.id == id);
    final stopped = entries[index].copyWith(
      endedAt: endedAt,
      durationSeconds: endedAt.difference(entries[index].startedAt).inSeconds,
    );
    entries[index] = stopped;
    return stopped;
  }

  @override
  Future<TimeEntryData> createEntry({
    required DateTime startedAt,
    required DateTime endedAt,
    String? projectId,
    String? taskId,
    String note = '',
    String source = 'manual',
  }) async {
    final entry = TimeEntryData(
      id: _nextId,
      startedAt: startedAt,
      endedAt: endedAt,
      durationSeconds: endedAt.difference(startedAt).inSeconds,
      projectId: projectId,
      taskId: taskId,
      source: source,
      note: note,
    );
    entries.add(entry);
    return entry;
  }

  @override
  Future<void> updateEntry(TimeEntryData entry) async {
    final index = entries.indexWhere((item) => item.id == entry.id);
    entries[index] = entry;
  }

  @override
  Future<void> deleteEntry(String id) async =>
      entries.removeWhere((entry) => entry.id == id);

  @override
  Future<PomodoroSessionData> startSession({
    required String mode,
    required int plannedSeconds,
    String? projectId,
    String? taskId,
    DateTime? startedAt,
  }) async {
    final session = PomodoroSessionData(
      id: _nextId,
      mode: mode,
      plannedSeconds: plannedSeconds,
      startedAt: startedAt ?? DateTime.now(),
      projectId: projectId,
      taskId: taskId,
    );
    sessions.add(session);
    return session;
  }

  @override
  Future<PomodoroSessionData> finishSession(
    String id, {
    required bool completed,
    required int actualSeconds,
    required DateTime endedAt,
  }) async {
    final index = sessions.indexWhere((session) => session.id == id);
    final finished = sessions[index].copyWith(
      endedAt: endedAt,
      actualSeconds: actualSeconds,
      completed: completed,
    );
    sessions[index] = finished;
    return finished;
  }

  @override
  Future<void> deleteSession(String id) async =>
      sessions.removeWhere((session) => session.id == id);
}
