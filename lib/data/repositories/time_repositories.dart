// 计时（TimeEntries）与番茄钟（PomodoroSessions）仓库。
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'repository_support.dart';

class TimeEntryRepository {
  TimeEntryRepository(this._db, {Clock? clock, String? deviceId})
    : _clock = clock ?? nowUtcMillis,
      _deviceId = deviceId ?? repositoryUuid.v4();

  final AppDatabase _db;
  final Clock _clock;
  final String _deviceId;

  Stream<List<TimeEntry>> watch({String? projectId, String? taskId}) {
    final query = _db.select(_db.timeEntries);
    query.where((row) {
      var condition = row.deletedAt.isNull();
      if (projectId != null) {
        condition = condition & row.projectId.equals(projectId);
      }
      if (taskId != null) {
        condition = condition & row.taskId.equals(taskId);
      }
      return condition;
    });
    query.orderBy([(row) => OrderingTerm.desc(row.startedAt)]);
    return query.watch();
  }

  Future<TimeEntry> start({
    required int startedAt,
    int durationSeconds = 0,
    String source = 'manual',
    String note = '',
    String? projectId,
    String? taskId,
    String? id,
  }) async {
    final now = _clock();
    final entryId = id ?? repositoryUuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.timeEntries)
          .insert(
            TimeEntriesCompanion.insert(
              id: entryId,
              projectId: Value(projectId),
              taskId: Value(taskId),
              startedAt: startedAt,
              durationSeconds: durationSeconds,
              source: source,
              note: Value(note),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final created = await (_db.select(
        _db.timeEntries,
      )..where((row) => row.id.equals(entryId))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'time_entry',
        entityId: entryId,
        operation: 'create',
        payload: rowPayload(created),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
    return await (_db.select(
      _db.timeEntries,
    )..where((row) => row.id.equals(entryId))).getSingle();
  }

  /// 结束一段计时：写 endedAt 与最终 durationSeconds（elapsed = endedAt-startedAt）。
  Future<void> stop(String id, {required int endedAt}) async {
    final now = _clock();
    await _db.transaction(() async {
      final entry = await (_db.select(
        _db.timeEntries,
      )..where((row) => row.id.equals(id))).getSingle();
      if (endedAt < entry.startedAt) {
        throw ArgumentError('endedAt 不能早于 startedAt。');
      }
      final durationSeconds = (endedAt - entry.startedAt) ~/ 1000;
      await (_db.update(
        _db.timeEntries,
      )..where((row) => row.id.equals(id))).write(
        TimeEntriesCompanion(
          endedAt: Value(endedAt),
          durationSeconds: Value(durationSeconds),
          updatedAt: Value(now),
        ),
      );
      final updated = await (_db.select(
        _db.timeEntries,
      )..where((row) => row.id.equals(id))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'time_entry',
        entityId: id,
        operation: 'update',
        payload: rowPayload(updated),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }

  /// 手动补记一段完整区间。
  Future<TimeEntry> create({
    required int startedAt,
    required int endedAt,
    String source = 'manual',
    String note = '',
    String? projectId,
    String? taskId,
    String? id,
  }) async {
    final now = _clock();
    final entryId = id ?? repositoryUuid.v4();
    final durationSeconds = (endedAt - startedAt) ~/ 1000;
    if (durationSeconds < 0) {
      throw ArgumentError('endedAt 不能早于 startedAt。');
    }
    await _db.transaction(() async {
      await _db
          .into(_db.timeEntries)
          .insert(
            TimeEntriesCompanion.insert(
              id: entryId,
              projectId: Value(projectId),
              taskId: Value(taskId),
              startedAt: startedAt,
              endedAt: Value(endedAt),
              durationSeconds: durationSeconds,
              source: source,
              note: Value(note),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final created = await (_db.select(
        _db.timeEntries,
      )..where((row) => row.id.equals(entryId))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'time_entry',
        entityId: entryId,
        operation: 'create',
        payload: rowPayload(created),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
    return await (_db.select(
      _db.timeEntries,
    )..where((row) => row.id.equals(entryId))).getSingle();
  }

  Future<void> update(TimeEntry entry) async {
    final now = _clock();
    await _db.transaction(() async {
      await (_db.update(
        _db.timeEntries,
      )..where((row) => row.id.equals(entry.id))).write(
        TimeEntriesCompanion(
          projectId: Value(entry.projectId),
          taskId: Value(entry.taskId),
          startedAt: Value(entry.startedAt),
          endedAt: Value(entry.endedAt),
          durationSeconds: Value(entry.durationSeconds),
          source: Value(entry.source),
          note: Value(entry.note),
          updatedAt: Value(now),
        ),
      );
      await recordSyncChange(
        _db,
        entityType: 'time_entry',
        entityId: entry.id,
        operation: 'update',
        payload: rowPayload(entry, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }

  Future<void> softDelete(String id) async {
    final now = _clock();
    await _db.transaction(() async {
      final row =
          await (_db.select(_db.timeEntries)
                ..where((r) => r.id.equals(id) & r.deletedAt.isNull()))
              .getSingleOrNull();
      if (row == null) return;
      await (_db.update(_db.timeEntries)..where((r) => r.id.equals(id))).write(
        TimeEntriesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await recordSyncChange(
        _db,
        entityType: 'time_entry',
        entityId: id,
        operation: 'delete',
        payload: rowPayload(row, deletedAt: now, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }
}

class PomodoroSessionRepository {
  PomodoroSessionRepository(this._db, {Clock? clock, String? deviceId})
    : _clock = clock ?? nowUtcMillis,
      _deviceId = deviceId ?? repositoryUuid.v4();

  final AppDatabase _db;
  final Clock _clock;
  final String _deviceId;

  Stream<List<PomodoroSession>> watch({String? projectId, String? taskId}) {
    final query = _db.select(_db.pomodoroSessions);
    query.where((row) {
      var condition = row.deletedAt.isNull();
      if (projectId != null) {
        condition = condition & row.projectId.equals(projectId);
      }
      if (taskId != null) {
        condition = condition & row.taskId.equals(taskId);
      }
      return condition;
    });
    query.orderBy([(row) => OrderingTerm.desc(row.startedAt)]);
    return query.watch();
  }

  Future<PomodoroSession> start({
    required String mode,
    required int plannedSeconds,
    required int startedAt,
    String? projectId,
    String? taskId,
    String? id,
  }) async {
    final now = _clock();
    final sessionId = id ?? repositoryUuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.pomodoroSessions)
          .insert(
            PomodoroSessionsCompanion.insert(
              id: sessionId,
              projectId: Value(projectId),
              taskId: Value(taskId),
              mode: mode,
              plannedSeconds: plannedSeconds,
              startedAt: startedAt,
              createdAt: now,
              updatedAt: now,
            ),
          );
      final created = await (_db.select(
        _db.pomodoroSessions,
      )..where((row) => row.id.equals(sessionId))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'pomodoro_session',
        entityId: sessionId,
        operation: 'create',
        payload: rowPayload(created),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
    return await (_db.select(
      _db.pomodoroSessions,
    )..where((row) => row.id.equals(sessionId))).getSingle();
  }

  /// 结束会话：[completed] 区分完成/中断，[actualSeconds] 与 [endedAt] 随写。
  Future<void> finish(
    String id, {
    required bool completed,
    required int actualSeconds,
    required int endedAt,
  }) async {
    final now = _clock();
    await _db.transaction(() async {
      await (_db.update(
        _db.pomodoroSessions,
      )..where((row) => row.id.equals(id))).write(
        PomodoroSessionsCompanion(
          actualSeconds: Value(actualSeconds),
          endedAt: Value(endedAt),
          completed: Value(completed),
          updatedAt: Value(now),
        ),
      );
      final updated = await (_db.select(
        _db.pomodoroSessions,
      )..where((row) => row.id.equals(id))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'pomodoro_session',
        entityId: id,
        operation: 'update',
        payload: rowPayload(updated),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }

  Future<void> update(PomodoroSession session) async {
    final now = _clock();
    await _db.transaction(() async {
      await (_db.update(
        _db.pomodoroSessions,
      )..where((row) => row.id.equals(session.id))).write(
        PomodoroSessionsCompanion(
          projectId: Value(session.projectId),
          taskId: Value(session.taskId),
          mode: Value(session.mode),
          plannedSeconds: Value(session.plannedSeconds),
          actualSeconds: Value(session.actualSeconds),
          startedAt: Value(session.startedAt),
          endedAt: Value(session.endedAt),
          completed: Value(session.completed),
          updatedAt: Value(now),
        ),
      );
      await recordSyncChange(
        _db,
        entityType: 'pomodoro_session',
        entityId: session.id,
        operation: 'update',
        payload: rowPayload(session, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }

  Future<void> softDelete(String id) async {
    final now = _clock();
    await _db.transaction(() async {
      final row =
          await (_db.select(_db.pomodoroSessions)
                ..where((r) => r.id.equals(id) & r.deletedAt.isNull()))
              .getSingleOrNull();
      if (row == null) return;
      await (_db.update(
        _db.pomodoroSessions,
      )..where((r) => r.id.equals(id))).write(
        PomodoroSessionsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await recordSyncChange(
        _db,
        entityType: 'pomodoro_session',
        entityId: id,
        operation: 'delete',
        payload: rowPayload(row, deletedAt: now, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }
}
