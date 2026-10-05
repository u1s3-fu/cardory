// 回收站仓库：软删除（tombstone）条目的查询与恢复。
//
// 恢复 = 清除 deletedAt + 抬升 updatedAt + 同事务写入 operation 'update'
// 的完整 payload sync_changes（与既有行级写入口一致），多端按实体级 LWW
// 收敛为「恢复」。assets 的敏感列不出同步通道（与删除/更新路径同一约束）。
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../application/recycle_bin_store.dart';
import '../../domain/recycle_bin_models.dart';
import '../db/app_database.dart';
import 'repository_support.dart';

class RecycleBinRepository implements RecycleBinStore {
  RecycleBinRepository(this._db, {Clock? clock, String? deviceId})
    : _clock = clock ?? nowUtcMillis,
      _deviceId = deviceId ?? repositoryUuid.v4();

  final AppDatabase _db;
  final Clock _clock;
  final String _deviceId;

  /// 列出全部软删除条目（按删除时间倒序）。
  @override
  Future<List<RecycleBinEntry>> loadEntries() async {
    final entries = <RecycleBinEntry>[];
    final now = _clock();

    final projects = await (_db.select(
      _db.projects,
    )..where((row) => row.deletedAt.isNotNull())).get();
    for (final row in projects) {
      entries.add(
        RecycleBinEntry(
          type: RecycleBinEntityType.project,
          id: row.id,
          title: row.name,
          deletedAt: _fromMillis(row.deletedAt, now),
        ),
      );
    }

    final tasks = await (_db.select(
      _db.tasks,
    )..where((row) => row.deletedAt.isNotNull())).get();
    final projectNames = {
      for (final project in projects) project.id: project.name,
    };
    for (final row in tasks) {
      final isSubTodo = row.parentTaskId != null;
      entries.add(
        RecycleBinEntry(
          type: RecycleBinEntityType.task,
          id: row.id,
          title: row.title,
          subtitle: [
            if (isSubTodo) '子待办',
            if (row.projectId != null)
              '项目：${projectNames[row.projectId] ?? '未知'}',
          ].join(' · '),
          deletedAt: _fromMillis(row.deletedAt, now),
        ),
      );
    }

    final assets = await (_db.select(
      _db.assets,
    )..where((row) => row.deletedAt.isNotNull())).get();
    for (final row in assets) {
      entries.add(
        RecycleBinEntry(
          type: RecycleBinEntityType.asset,
          id: row.id,
          title: row.title,
          subtitle: row.projectId == null
              ? ''
              : '项目：${projectNames[row.projectId] ?? '未知'}',
          deletedAt: _fromMillis(row.deletedAt, now),
        ),
      );
    }

    final milestones = await (_db.select(
      _db.milestones,
    )..where((row) => row.deletedAt.isNotNull())).get();
    for (final row in milestones) {
      entries.add(
        RecycleBinEntry(
          type: RecycleBinEntityType.milestone,
          id: row.id,
          title: row.title,
          subtitle: '项目：${projectNames[row.projectId] ?? '未知'}',
          deletedAt: _fromMillis(row.deletedAt, now),
        ),
      );
    }

    entries.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return entries;
  }

  /// 恢复一条软删除记录。
  ///
  /// 幂等：未删除的条目直接返回。里程碑要求所属项目仍存在且未删除
  /// （否则甘特页会重新出现「未知项目」孤儿数据），其余类型不校验宿主：
  /// 项目/待办的从属数据各自作为独立条目恢复，宿主未恢复前不可见但无副作用。
  @override
  Future<void> restore(RecycleBinEntityType type, String id) async {
    final now = _clock();
    await _db.transaction(() async {
      switch (type) {
        case RecycleBinEntityType.project:
          await _restoreProject(id, now);
        case RecycleBinEntityType.task:
          await _restoreTask(id, now);
        case RecycleBinEntityType.asset:
          await _restoreAsset(id, now);
        case RecycleBinEntityType.milestone:
          await _restoreMilestone(id, now);
      }
    });
  }

  Future<void> _restoreProject(String id, int now) async {
    final row = await (_db.select(
      _db.projects,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw StateError('条目不存在，可能已被永久清理。');
    }
    if (row.deletedAt == null) return;
    await (_db.update(_db.projects)..where((r) => r.id.equals(id))).write(
      ProjectsCompanion(deletedAt: const Value(null), updatedAt: Value(now)),
    );
    await recordSyncChange(
      _db,
      entityType: 'project',
      entityId: id,
      operation: 'update',
      payload: _restorePayload(row.toJson(), now),
      deviceId: _deviceId,
      createdAt: now,
    );
  }

  Future<void> _restoreTask(String id, int now) async {
    final row = await (_db.select(
      _db.tasks,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw StateError('条目不存在，可能已被永久清理。');
    }
    if (row.deletedAt == null) return;
    await (_db.update(_db.tasks)..where((r) => r.id.equals(id))).write(
      TasksCompanion(deletedAt: const Value(null), updatedAt: Value(now)),
    );
    await recordSyncChange(
      _db,
      entityType: 'task',
      entityId: id,
      operation: 'update',
      payload: _restorePayload(row.toJson(), now),
      deviceId: _deviceId,
      createdAt: now,
    );
  }

  Future<void> _restoreAsset(String id, int now) async {
    final row = await (_db.select(
      _db.assets,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw StateError('条目不存在，可能已被永久清理。');
    }
    if (row.deletedAt == null) return;
    await (_db.update(_db.assets)..where((r) => r.id.equals(id))).write(
      AssetsCompanion(deletedAt: const Value(null), updatedAt: Value(now)),
    );
    await recordSyncChange(
      _db,
      entityType: 'asset',
      entityId: id,
      operation: 'update',
      payload: _restorePayload(
        row.toJson(),
        now,
        exclude: const {'sensitiveJson'},
      ),
      deviceId: _deviceId,
      createdAt: now,
    );
  }

  Future<void> _restoreMilestone(String id, int now) async {
    final row = await (_db.select(
      _db.milestones,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw StateError('条目不存在，可能已被永久清理。');
    }
    if (row.deletedAt == null) return;
    final project = await (_db.select(
      _db.projects,
    )..where((r) => r.id.equals(row.projectId))).getSingleOrNull();
    if (project == null || project.deletedAt != null) {
      throw StateError('所属项目尚未恢复，请先恢复对应项目。');
    }
    await (_db.update(_db.milestones)..where((r) => r.id.equals(id))).write(
      MilestonesCompanion(deletedAt: const Value(null), updatedAt: Value(now)),
    );
    await recordSyncChange(
      _db,
      entityType: 'milestone',
      entityId: id,
      operation: 'update',
      payload: _restorePayload(row.toJson(), now),
      deviceId: _deviceId,
      createdAt: now,
    );
  }

  /// 恢复载荷 = 行完整字段 + deletedAt 置空 + updatedAt 抬升。
  ///
  /// 不能复用 rowPayload：它只能在非空时覆写 deletedAt，而恢复必须把
  /// 墓碑时间从载荷中清除（远端 fromJson 覆盖写入后才能复活）。
  String _restorePayload(
    Map<String, dynamic> json,
    int now, {
    Set<String> exclude = const <String>{},
  }) {
    final payload = Map<String, dynamic>.from(json)
      ..['deletedAt'] = null
      ..['updatedAt'] = now;
    for (final key in exclude) {
      payload.remove(key);
    }
    return jsonEncode(payload);
  }

  DateTime _fromMillis(int? millis, int fallback) =>
      DateTime.fromMillisecondsSinceEpoch(millis ?? fallback, isUtc: true);
}
