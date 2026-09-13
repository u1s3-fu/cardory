// 里程碑（Milestones）仓库。
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'repository_support.dart';

class MilestoneRepository {
  MilestoneRepository(this._db, {Clock? clock, String? deviceId})
    : _clock = clock ?? nowUtcMillis,
      _deviceId = deviceId ?? repositoryUuid.v4();

  final AppDatabase _db;
  final Clock _clock;
  final String _deviceId;

  Stream<List<Milestone>> watchByProject(String projectId) =>
      (_db.select(_db.milestones)
            ..where(
              (row) => row.projectId.equals(projectId) & row.deletedAt.isNull(),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.dueAt)]))
          .watch();

  Future<List<Milestone>> loadVisible() async => await (_db.select(
    _db.milestones,
  )..where((row) => row.deletedAt.isNull())).get();

  Future<Milestone> create({
    required String projectId,
    required String title,
    required int dueAt,
    String note = '',
    String? id,
  }) async {
    final now = _clock();
    final milestoneId = id ?? repositoryUuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.milestones)
          .insert(
            MilestonesCompanion.insert(
              id: milestoneId,
              projectId: projectId,
              title: title,
              dueAt: dueAt,
              note: Value(note),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final created = await (_db.select(
        _db.milestones,
      )..where((row) => row.id.equals(milestoneId))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'milestone',
        entityId: milestoneId,
        operation: 'create',
        payload: rowPayload(created),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
    return await (_db.select(
      _db.milestones,
    )..where((row) => row.id.equals(milestoneId))).getSingle();
  }

  /// 用行快照更新里程碑业务字段。
  Future<void> update(Milestone milestone) async {
    final now = _clock();
    await _db.transaction(() async {
      await (_db.update(
        _db.milestones,
      )..where((row) => row.id.equals(milestone.id))).write(
        MilestonesCompanion(
          title: Value(milestone.title),
          note: Value(milestone.note),
          dueAt: Value(milestone.dueAt),
          completed: Value(milestone.completed),
          completedAt: Value(milestone.completedAt),
          updatedAt: Value(now),
        ),
      );
      await recordSyncChange(
        _db,
        entityType: 'milestone',
        entityId: milestone.id,
        operation: 'update',
        payload: rowPayload(milestone, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }

  Future<void> softDelete(String id) async {
    final now = _clock();
    await _db.transaction(() async {
      final row =
          await (_db.select(_db.milestones)
                ..where((r) => r.id.equals(id) & r.deletedAt.isNull()))
              .getSingleOrNull();
      if (row == null) return;
      await (_db.update(_db.milestones)..where((r) => r.id.equals(id))).write(
        MilestonesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await recordSyncChange(
        _db,
        entityType: 'milestone',
        entityId: id,
        operation: 'delete',
        payload: rowPayload(row, deletedAt: now, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }
}
