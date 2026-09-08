// 资产（Assets / AssetTags）仓库。
//
// 敏感列约定：Assets.sensitiveJson 由 SQLCipher 保护，任何写操作都不会把它
// 带入 sync_changes payload；删除标签时会同步把该标签 id 从资产 tagsJson 中
// 移除，避免 UI 渲染悬空标签。
import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'repository_support.dart';

/// 不含敏感列的资产字段子集。
const assetPayloadExclude = {'sensitiveJson'};

class AssetRepository {
  AssetRepository(this._db, {Clock? clock, String? deviceId})
    : _clock = clock ?? nowUtcMillis,
      _deviceId = deviceId ?? repositoryUuid.v4();

  final AppDatabase _db;
  final Clock _clock;
  final String _deviceId;

  Stream<List<Asset>> watchAssets({String? projectId, String? taskId}) =>
      _watchQuery(projectId: projectId, taskId: taskId).watch();

  Future<List<Asset>> loadVisible({String? projectId}) async =>
      await _watchQuery(projectId: projectId).get();

  Stream<Asset?> watchAsset(String id) =>
      (_db.select(_db.assets)
            ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
          .watchSingleOrNull();

  SimpleSelectStatement<$AssetsTable, Asset> _watchQuery({
    String? projectId,
    String? taskId,
  }) {
    final query = _db.select(_db.assets);
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
    query.orderBy([(row) => OrderingTerm.asc(row.createdAt)]);
    return query;
  }

  Future<Asset> create({
    required String type,
    required String title,
    String? projectId,
    String? taskId,
    String uriOrPath = '',
    String note = '',
    List<String> tagIds = const [],
    Map<String, dynamic> metadata = const {},
    bool isLocalOnly = false,
    String? sensitiveJson,
    String? id,
  }) async {
    final now = _clock();
    final assetId = id ?? repositoryUuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.assets)
          .insert(
            AssetsCompanion.insert(
              id: assetId,
              projectId: Value(projectId),
              taskId: Value(taskId),
              type: type,
              title: title,
              uriOrPath: Value(uriOrPath),
              note: Value(note),
              tagsJson: Value(jsonEncode(tagIds)),
              metadataJson: Value(jsonEncode(metadata)),
              isLocalOnly: Value(isLocalOnly),
              sensitiveJson: Value(sensitiveJson),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final created = await (_db.select(
        _db.assets,
      )..where((row) => row.id.equals(assetId))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'asset',
        entityId: assetId,
        operation: 'create',
        payload: rowPayload(created, exclude: assetPayloadExclude),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
    return await (_db.select(
      _db.assets,
    )..where((row) => row.id.equals(assetId))).getSingle();
  }

  Future<void> update(Asset asset) async {
    final now = _clock();
    await _db.transaction(() async {
      await (_db.update(
        _db.assets,
      )..where((row) => row.id.equals(asset.id))).write(
        AssetsCompanion(
          projectId: Value(asset.projectId),
          taskId: Value(asset.taskId),
          type: Value(asset.type),
          title: Value(asset.title),
          uriOrPath: Value(asset.uriOrPath),
          note: Value(asset.note),
          tagsJson: Value(asset.tagsJson),
          metadataJson: Value(asset.metadataJson),
          isLocalOnly: Value(asset.isLocalOnly),
          sensitiveJson: Value(asset.sensitiveJson),
          updatedAt: Value(now),
        ),
      );
      await recordSyncChange(
        _db,
        entityType: 'asset',
        entityId: asset.id,
        operation: 'update',
        payload: rowPayload(
          asset,
          updatedAt: now,
          exclude: assetPayloadExclude,
        ),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }

  Future<void> softDelete(String id) async {
    final now = _clock();
    await _db.transaction(() async {
      final row =
          await (_db.select(_db.assets)
                ..where((r) => r.id.equals(id) & r.deletedAt.isNull()))
              .getSingleOrNull();
      if (row == null) return;
      await (_db.update(_db.assets)..where((r) => r.id.equals(id))).write(
        AssetsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await recordSyncChange(
        _db,
        entityType: 'asset',
        entityId: id,
        operation: 'delete',
        payload: rowPayload(
          row,
          deletedAt: now,
          updatedAt: now,
          exclude: assetPayloadExclude,
        ),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }
}

class AssetTagRepository {
  AssetTagRepository(this._db, {Clock? clock, String? deviceId})
    : _clock = clock ?? nowUtcMillis,
      _deviceId = deviceId ?? repositoryUuid.v4();

  final AppDatabase _db;
  final Clock _clock;
  final String _deviceId;

  Stream<List<AssetTag>> watchTags() => (_db.select(
    _db.assetTags,
  )..where((row) => row.deletedAt.isNull())).watch();

  Future<List<AssetTag>> loadVisibleTags() async => await (_db.select(
    _db.assetTags,
  )..where((row) => row.deletedAt.isNull())).get();

  Future<AssetTag> create({required String name, String? id}) async {
    final now = _clock();
    final tagId = id ?? repositoryUuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.assetTags)
          .insert(
            AssetTagsCompanion.insert(
              id: tagId,
              name: name,
              createdAt: now,
              updatedAt: now,
            ),
          );
      final created = await (_db.select(
        _db.assetTags,
      )..where((row) => row.id.equals(tagId))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'asset_tag',
        entityId: tagId,
        operation: 'create',
        payload: rowPayload(created),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
    return await (_db.select(
      _db.assetTags,
    )..where((row) => row.id.equals(tagId))).getSingle();
  }

  Future<void> rename(String id, String name) async {
    final now = _clock();
    await _db.transaction(() async {
      await (_db.update(_db.assetTags)..where((row) => row.id.equals(id)))
          .write(AssetTagsCompanion(name: Value(name), updatedAt: Value(now)));
      final updated = await (_db.select(
        _db.assetTags,
      )..where((row) => row.id.equals(id))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'asset_tag',
        entityId: id,
        operation: 'update',
        payload: rowPayload(updated),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }

  /// 软删除标签，并把该标签从所有资产的 tagsJson 中移除。
  Future<void> softDelete(String id) async {
    final now = _clock();
    await _db.transaction(() async {
      final row =
          await (_db.select(_db.assetTags)
                ..where((r) => r.id.equals(id) & r.deletedAt.isNull()))
              .getSingleOrNull();
      if (row == null) return;
      await (_db.update(_db.assetTags)..where((r) => r.id.equals(id))).write(
        AssetTagsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await recordSyncChange(
        _db,
        entityType: 'asset_tag',
        entityId: id,
        operation: 'delete',
        payload: rowPayload(row, deletedAt: now, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );

      final linked = await (_db.select(
        _db.assets,
      )..where((r) => r.deletedAt.isNull() & r.tagsJson.like('%$id%'))).get();
      for (final asset in linked) {
        final tags = (jsonDecode(asset.tagsJson) as List<dynamic>)
            .cast<String>()
            .where((tagId) => tagId != id)
            .toList();
        await (_db.update(
          _db.assets,
        )..where((r) => r.id.equals(asset.id))).write(
          AssetsCompanion(
            tagsJson: Value(jsonEncode(tags)),
            updatedAt: Value(now),
          ),
        );
        await recordSyncChange(
          _db,
          entityType: 'asset',
          entityId: asset.id,
          operation: 'update',
          payload: rowPayload(
            asset.copyWith(tagsJson: jsonEncode(tags), updatedAt: now),
            exclude: assetPayloadExclude,
          ),
          deviceId: _deviceId,
          createdAt: now,
        );
      }
    });
  }
}
