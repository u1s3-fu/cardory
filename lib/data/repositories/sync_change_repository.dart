// 同步变更日志（SyncChanges）仓库。
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'repository_support.dart';

class SyncChangeRepository {
  SyncChangeRepository(this._db);

  final AppDatabase _db;

  /// 尚未被同步确认（acknowledgedAt 为空）的变更，按产生时间升序。
  Future<List<SyncChange>> pending() async =>
      await (_db.select(_db.syncChanges)
            ..where((row) => row.acknowledgedAt.isNull())
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
          .get();

  Future<List<SyncChange>> pendingSince(int sinceUtcMillis) async =>
      await (_db.select(_db.syncChanges)
            ..where(
              (row) =>
                  row.acknowledgedAt.isNull() &
                  row.createdAt.isBiggerOrEqualValue(sinceUtcMillis),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
          .get();

  Future<int> countPending() async {
    final row =
        await (_db.selectOnly(_db.syncChanges)
              ..addColumns([_db.syncChanges.createdAt.count()])
              ..where(_db.syncChanges.acknowledgedAt.isNull()))
            .getSingle();
    return row.read(_db.syncChanges.createdAt.count()) ?? 0;
  }

  /// 确认某条变更已同步。
  Future<void> acknowledge(String id, {int? acknowledgedAt}) async {
    final now = acknowledgedAt ?? nowUtcMillis();
    await (_db.update(_db.syncChanges)..where((row) => row.id.equals(id)))
        .write(SyncChangesCompanion(acknowledgedAt: Value(now)));
  }

  /// 清理确认后且超出 [olderThanMillis] 的日志。
  Future<int> pruneConfirmedOlderThan(int olderThanMillis) async {
    final before = nowUtcMillis() - olderThanMillis;
    final query = _db.delete(_db.syncChanges)
      ..where(
        (row) =>
            row.acknowledgedAt.isNotNull() &
            row.acknowledgedAt.isSmallerThanValue(before),
      );
    return await query.go();
  }

  Future<void> pruneForEntity(String entityType, String entityId) async {
    await (_db.delete(_db.syncChanges)..where(
          (row) =>
              row.entityType.equals(entityType) & row.entityId.equals(entityId),
        ))
        .go();
  }
}
