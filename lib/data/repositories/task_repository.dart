// 任务（Tasks）仓库。
//
// 约束：任务层级最多两层（父任务 + 直接子任务）；子任务必须与父任务属于
// 同一项目；父任务不可被删除后再建子任务。所有写操作在同一事务内完成
// 实体行 + updatedAt/tombstone + sync_changes（完整 payload）。
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'repository_support.dart';

class TaskRepository {
  TaskRepository(this._db, {Clock? clock, String? deviceId})
    : _clock = clock ?? nowUtcMillis,
      _deviceId = deviceId ?? repositoryUuid.v4();

  final AppDatabase _db;
  final Clock _clock;
  final String _deviceId;

  Stream<List<Task>> watchProjectTasks(String projectId) =>
      (_db.select(_db.tasks)
            ..where(
              (row) => row.projectId.equals(projectId) & row.deletedAt.isNull(),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
          .watch();

  Stream<List<Task>> watchTodayTasks(int startUtcMillis, int endUtcMillis) =>
      (_db.select(_db.tasks)
            ..where(
              (row) =>
                  row.deletedAt.isNull() &
                  row.dueAt.isBiggerOrEqualValue(startUtcMillis) &
                  row.dueAt.isSmallerThanValue(endUtcMillis),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.dueAt)]))
          .watch();

  Future<Task?> getById(String id) async =>
      await (_db.select(_db.tasks)
            ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
          .getSingleOrNull();

  Future<Task> create({
    required String title,
    required String projectId,
    String? parentTaskId,
    String notes = '',
    String status = 'todo',
    String priority = 'p2',
    String? id,
    int sortOrder = 0,
    int? startAt,
    int? dueAt,
    int? estimateMinutes,
  }) async {
    if (parentTaskId != null) {
      await _assertValidParent(parentTaskId, projectId);
    }
    final now = _clock();
    final taskId = id ?? repositoryUuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.tasks)
          .insert(
            TasksCompanion.insert(
              id: taskId,
              projectId: Value(projectId),
              parentTaskId: Value(parentTaskId),
              title: title,
              notes: Value(notes),
              status: status,
              priority: priority,
              startAt: Value(startAt),
              dueAt: Value(dueAt),
              estimateMinutes: Value(estimateMinutes),
              sortOrder: Value(sortOrder),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final created = await (_db.select(
        _db.tasks,
      )..where((row) => row.id.equals(taskId))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'task',
        entityId: taskId,
        operation: 'create',
        payload: rowPayload(created),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
    return await (_db.select(
      _db.tasks,
    )..where((row) => row.id.equals(taskId))).getSingle();
  }

  /// 用行快照更新任务的全部业务字段（不修改 deletedAt/createdAt）。
  Future<void> update(Task task) async {
    final now = _clock();
    await _db.transaction(() async {
      await (_db.update(
        _db.tasks,
      )..where((row) => row.id.equals(task.id))).write(
        TasksCompanion(
          projectId: Value(task.projectId),
          parentTaskId: Value(task.parentTaskId),
          title: Value(task.title),
          notes: Value(task.notes),
          status: Value(task.status),
          priority: Value(task.priority),
          startAt: Value(task.startAt),
          dueAt: Value(task.dueAt),
          estimateMinutes: Value(task.estimateMinutes),
          completedAt: Value(task.completedAt),
          sortOrder: Value(task.sortOrder),
          updatedAt: Value(now),
        ),
      );
      await recordSyncChange(
        _db,
        entityType: 'task',
        entityId: task.id,
        operation: 'update',
        payload: rowPayload(task, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }

  Future<void> complete(String id) async {
    final now = _clock();
    await _db.transaction(() async {
      await (_db.update(_db.tasks)..where((row) => row.id.equals(id))).write(
        TasksCompanion(
          status: const Value('done'),
          completedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      final updated = await (_db.select(
        _db.tasks,
      )..where((row) => row.id.equals(id))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'task',
        entityId: id,
        operation: 'update',
        payload: rowPayload(updated),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }

  /// 软删除任务及其全部可见直接子任务，并收口依附数据避免孤儿可见。
  Future<void> softDelete(String id) async {
    final now = _clock();
    await _db.transaction(() async {
      final tasks = await (_db.select(
        _db.tasks,
      )..where((row) => row.deletedAt.isNull() & row.id.equals(id))).get();
      if (tasks.isEmpty) return; // 幂等。
      final main = tasks.single;

      final children =
          await (_db.select(_db.tasks)..where(
                (row) => row.parentTaskId.equals(id) & row.deletedAt.isNull(),
              ))
              .get();
      final ids = [main.id, ...children.map((row) => row.id)];
      for (final row in [main, ...children]) {
        await _markDeletedTask(row, now);
      }

      await _softDeleteOwnedAssets(ids, now);
      await _softDeleteOwnedAttachments(ids, now);
      await _softDeleteTimeEntries(ids, now);
      await _softDeletePomodoros(ids, now);
      await _softDeleteDependencies(ids, now);
    });
  }

  Future<void> _markDeletedTask(Task row, int now) async {
    await (_db.update(_db.tasks)..where((r) => r.id.equals(row.id))).write(
      TasksCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await recordSyncChange(
      _db,
      entityType: 'task',
      entityId: row.id,
      operation: 'delete',
      payload: rowPayload(row, deletedAt: now, updatedAt: now),
      deviceId: _deviceId,
      createdAt: now,
    );
  }

  Future<void> _softDeleteOwnedAssets(List<String> taskIds, int now) async {
    final rows = await (_db.select(
      _db.assets,
    )..where((row) => row.taskId.isIn(taskIds) & row.deletedAt.isNull())).get();
    for (final row in rows) {
      await (_db.update(_db.assets)..where((r) => r.id.equals(row.id))).write(
        AssetsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await recordSyncChange(
        _db,
        entityType: 'asset',
        entityId: row.id,
        operation: 'delete',
        payload: rowPayload(
          row,
          deletedAt: now,
          updatedAt: now,
          exclude: const {'sensitiveJson'},
        ),
        deviceId: _deviceId,
        createdAt: now,
      );
    }
  }

  Future<void> _softDeleteOwnedAttachments(
    List<String> taskIds,
    int now,
  ) async {
    final rows = await (_db.select(
      _db.attachments,
    )..where((row) => row.taskId.isIn(taskIds) & row.deletedAt.isNull())).get();
    for (final row in rows) {
      await (_db.update(
        _db.attachments,
      )..where((r) => r.id.equals(row.id))).write(
        AttachmentsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await recordSyncChange(
        _db,
        entityType: 'attachment',
        entityId: row.id,
        operation: 'delete',
        payload: rowPayload(row, deletedAt: now, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    }
  }

  Future<void> _softDeleteTimeEntries(List<String> taskIds, int now) async {
    final rows = await (_db.select(
      _db.timeEntries,
    )..where((row) => row.taskId.isIn(taskIds) & row.deletedAt.isNull())).get();
    for (final row in rows) {
      await (_db.update(
        _db.timeEntries,
      )..where((r) => r.id.equals(row.id))).write(
        TimeEntriesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await recordSyncChange(
        _db,
        entityType: 'time_entry',
        entityId: row.id,
        operation: 'delete',
        payload: rowPayload(row, deletedAt: now, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    }
  }

  Future<void> _softDeletePomodoros(List<String> taskIds, int now) async {
    final rows = await (_db.select(
      _db.pomodoroSessions,
    )..where((row) => row.taskId.isIn(taskIds) & row.deletedAt.isNull())).get();
    for (final row in rows) {
      await (_db.update(
        _db.pomodoroSessions,
      )..where((r) => r.id.equals(row.id))).write(
        PomodoroSessionsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await recordSyncChange(
        _db,
        entityType: 'pomodoro_session',
        entityId: row.id,
        operation: 'delete',
        payload: rowPayload(row, deletedAt: now, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    }
  }

  Future<void> _softDeleteDependencies(List<String> taskIds, int now) async {
    final rows =
        await (_db.select(_db.taskDependencies)..where(
              (row) =>
                  row.deletedAt.isNull() &
                  (row.predecessorTaskId.isIn(taskIds) |
                      row.successorTaskId.isIn(taskIds)),
            ))
            .get();
    for (final row in rows) {
      await (_db.update(
        _db.taskDependencies,
      )..where((r) => r.id.equals(row.id))).write(
        TaskDependenciesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await recordSyncChange(
        _db,
        entityType: 'task_dependency',
        entityId: row.id,
        operation: 'delete',
        payload: rowPayload(row, deletedAt: now, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    }
  }

  /// 父任务必须存在、未删除、属于同一项目，且只能作为顶层任务。
  Future<void> _assertValidParent(String parentId, String projectId) async {
    final parent = await (_db.select(
      _db.tasks,
    )..where((row) => row.id.equals(parentId))).getSingleOrNull();
    if (parent == null || parent.deletedAt != null) {
      throw StateError('Parent task does not exist: $parentId');
    }
    if (parent.projectId != projectId) {
      throw StateError(
        'Child task must belong to the same project as its '
        'parent.',
      );
    }
    if (parent.parentTaskId != null) {
      throw StateError('Tasks support only a parent and one child level.');
    }
  }
}
