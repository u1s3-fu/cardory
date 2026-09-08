// 任务依赖（TaskDependencies）仓库。
//
// 表上存在 (predecessorTaskId, successorTaskId, type) 唯一约束。因采用软删除，
// 重建被删依赖时采用"复活旧行"策略（清空 deletedAt）以避免唯一冲突并保留
// 依赖历史一致性。
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'repository_support.dart';

class TaskDependencyRepository {
  TaskDependencyRepository(this._db, {Clock? clock, String? deviceId})
    : _clock = clock ?? nowUtcMillis,
      _deviceId = deviceId ?? repositoryUuid.v4();

  final AppDatabase _db;
  final Clock _clock;
  final String _deviceId;

  /// 与 [taskId] 有关（前置或后继）的可见依赖。
  Stream<List<TaskDependency>> watchInvolving(String taskId) =>
      (_db.select(_db.taskDependencies)
            ..where(
              (row) =>
                  row.deletedAt.isNull() &
                  (row.predecessorTaskId.equals(taskId) |
                      row.successorTaskId.equals(taskId)),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
          .watch();

  Future<List<TaskDependency>> loadVisible() async => await (_db.select(
    _db.taskDependencies,
  )..where((row) => row.deletedAt.isNull())).get();

  /// 建立一条依赖；若同 (前驱, 后继, 类型) 的软删行已存在则复活它。
  Future<TaskDependency> create({
    required String predecessorTaskId,
    required String successorTaskId,
    String type = 'finish_to_start',
    String? id,
  }) async {
    if (predecessorTaskId == successorTaskId) {
      throw StateError('任务不能依赖自身。');
    }
    final now = _clock();
    final targetId = id ?? repositoryUuid.v4();
    final existing =
        await (_db.select(_db.taskDependencies)..where(
              (row) =>
                  row.predecessorTaskId.equals(predecessorTaskId) &
                  row.successorTaskId.equals(successorTaskId) &
                  row.type.equals(type),
            ))
            .getSingleOrNull();

    if (existing != null && existing.deletedAt == null) {
      throw StateError('该依赖关系已存在。');
    }

    await _db.transaction(() async {
      if (existing != null && existing.deletedAt != null) {
        // 复活软删行，避免唯一约束冲突。
        await (_db.update(
          _db.taskDependencies,
        )..where((row) => row.id.equals(existing.id))).write(
          TaskDependenciesCompanion(
            type: Value(type),
            deletedAt: const Value(null),
            updatedAt: Value(now),
          ),
        );
        final revived = await (_db.select(
          _db.taskDependencies,
        )..where((row) => row.id.equals(existing.id))).getSingle();
        await recordSyncChange(
          _db,
          entityType: 'task_dependency',
          entityId: existing.id,
          operation: 'create',
          payload: rowPayload(revived),
          deviceId: _deviceId,
          createdAt: now,
        );
      } else {
        await _db
            .into(_db.taskDependencies)
            .insert(
              TaskDependenciesCompanion.insert(
                id: targetId,
                predecessorTaskId: predecessorTaskId,
                successorTaskId: successorTaskId,
                type: Value(type),
                createdAt: now,
                updatedAt: now,
              ),
            );
        final created = await (_db.select(
          _db.taskDependencies,
        )..where((row) => row.id.equals(targetId))).getSingle();
        await recordSyncChange(
          _db,
          entityType: 'task_dependency',
          entityId: targetId,
          operation: 'create',
          payload: rowPayload(created),
          deviceId: _deviceId,
          createdAt: now,
        );
      }
    });

    final resolvedId = existing != null && existing.deletedAt != null
        ? existing.id
        : targetId;
    return await (_db.select(
      _db.taskDependencies,
    )..where((row) => row.id.equals(resolvedId))).getSingle();
  }

  Future<void> softDelete(String id) async {
    final now = _clock();
    await _db.transaction(() async {
      final row =
          await (_db.select(_db.taskDependencies)
                ..where((r) => r.id.equals(id) & r.deletedAt.isNull()))
              .getSingleOrNull();
      if (row == null) return;
      await (_db.update(
        _db.taskDependencies,
      )..where((r) => r.id.equals(id))).write(
        TaskDependenciesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await recordSyncChange(
        _db,
        entityType: 'task_dependency',
        entityId: id,
        operation: 'delete',
        payload: rowPayload(row, deletedAt: now, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }
}
