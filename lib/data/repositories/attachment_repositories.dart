// 附件（Attachments 元数据 / AttachmentCategories）仓库。
//
// 附件正文内容由 AttachmentStore 单独加密存放，本仓库只管理元数据行；
// 删除附件分类时会同步清理附件 categoryIdsJson 中的分类 id。删除附件行
// 仅做 tombstone，密文文件保留到显式 reconcile/prune 阶段再清理。
import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'repository_support.dart';

class AttachmentCategoryRepository {
  AttachmentCategoryRepository(this._db, {Clock? clock, String? deviceId})
    : _clock = clock ?? nowUtcMillis,
      _deviceId = deviceId ?? repositoryUuid.v4();

  final AppDatabase _db;
  final Clock _clock;
  final String _deviceId;

  Stream<List<AttachmentCategory>> watchCategories(String projectId) =>
      (_db.select(_db.attachmentCategories)..where(
            (row) => row.projectId.equals(projectId) & row.deletedAt.isNull(),
          ))
          .watch();

  Future<AttachmentCategory> create({
    required String projectId,
    required String name,
    String? id,
  }) async {
    final now = _clock();
    final categoryId = id ?? repositoryUuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.attachmentCategories)
          .insert(
            AttachmentCategoriesCompanion.insert(
              id: categoryId,
              projectId: projectId,
              name: name,
              createdAt: now,
              updatedAt: now,
            ),
          );
      final created = await (_db.select(
        _db.attachmentCategories,
      )..where((row) => row.id.equals(categoryId))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'attachment_category',
        entityId: categoryId,
        operation: 'create',
        payload: rowPayload(created),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
    return await (_db.select(
      _db.attachmentCategories,
    )..where((row) => row.id.equals(categoryId))).getSingle();
  }

  Future<void> rename(String id, String name) async {
    final now = _clock();
    await _db.transaction(() async {
      await (_db.update(
        _db.attachmentCategories,
      )..where((row) => row.id.equals(id))).write(
        AttachmentCategoriesCompanion(name: Value(name), updatedAt: Value(now)),
      );
      final updated = await (_db.select(
        _db.attachmentCategories,
      )..where((row) => row.id.equals(id))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'attachment_category',
        entityId: id,
        operation: 'update',
        payload: rowPayload(updated),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }

  /// 软删除分类并从附件记录中摘除引用。
  Future<void> softDelete(String id) async {
    final now = _clock();
    await _db.transaction(() async {
      final row =
          await (_db.select(_db.attachmentCategories)
                ..where((r) => r.id.equals(id) & r.deletedAt.isNull()))
              .getSingleOrNull();
      if (row == null) return;
      await (_db.update(
        _db.attachmentCategories,
      )..where((r) => r.id.equals(id))).write(
        AttachmentCategoriesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await recordSyncChange(
        _db,
        entityType: 'attachment_category',
        entityId: id,
        operation: 'delete',
        payload: rowPayload(row, deletedAt: now, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );

      final linked =
          await (_db.select(_db.attachments)..where(
                (r) => r.deletedAt.isNull() & r.categoryIdsJson.like('%$id%'),
              ))
              .get();
      for (final attachment in linked) {
        final categories =
            (jsonDecode(attachment.categoryIdsJson) as List<dynamic>)
                .cast<String>()
                .where((categoryId) => categoryId != id)
                .toList();
        final updated = attachment.copyWith(
          categoryIdsJson: jsonEncode(categories),
          updatedAt: now,
        );
        await (_db.update(
          _db.attachments,
        )..where((r) => r.id.equals(attachment.id))).write(
          AttachmentsCompanion(
            categoryIdsJson: Value(updated.categoryIdsJson),
            updatedAt: Value(now),
          ),
        );
        await recordSyncChange(
          _db,
          entityType: 'attachment',
          entityId: attachment.id,
          operation: 'update',
          payload: rowPayload(updated),
          deviceId: _deviceId,
          createdAt: now,
        );
      }
    });
  }
}

/// 附件元数据仓库；附件正文字节由 AttachmentStore 管理。
class AttachmentRecordRepository {
  AttachmentRecordRepository(this._db, {Clock? clock, String? deviceId})
    : _clock = clock ?? nowUtcMillis,
      _deviceId = deviceId ?? repositoryUuid.v4();

  final AppDatabase _db;
  final Clock _clock;
  final String _deviceId;

  Stream<List<Attachment>> watchByProject(String projectId) =>
      (_db.select(_db.attachments)
            ..where(
              (row) => row.projectId.equals(projectId) & row.deletedAt.isNull(),
            )
            ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
          .watch();

  Stream<List<Attachment>> watchByTask(String taskId) =>
      (_db.select(_db.attachments)
            ..where((row) => row.taskId.equals(taskId) & row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm.desc(row.createdAt)]))
          .watch();

  Future<List<Attachment>> loadVisible() async => await (_db.select(
    _db.attachments,
  )..where((row) => row.deletedAt.isNull())).get();

  Future<Attachment> create({
    String? projectId,
    String? taskId,
    required String fileName,
    required String storageKey,
    required int sizeBytes,
    required String sha256,
    String mimeType = '',
    required String kind,
    String note = '',
    bool isLocalOnly = false,
    String encryptionKey = '',
    List<String> categoryIds = const [],
    String? id,
    int? createdAt,
  }) async {
    final now = _clock();
    final attachmentId = id ?? repositoryUuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: attachmentId,
              projectId: Value(projectId),
              taskId: Value(taskId),
              fileName: fileName,
              storageKey: storageKey,
              sizeBytes: sizeBytes,
              sha256: sha256,
              mimeType: Value(mimeType),
              kind: kind,
              note: Value(note),
              isLocalOnly: Value(isLocalOnly),
              encryptionKey: Value(encryptionKey),
              categoryIdsJson: Value(jsonEncode(categoryIds)),
              createdAt: createdAt ?? now,
              updatedAt: now,
            ),
          );
      final created = await (_db.select(
        _db.attachments,
      )..where((row) => row.id.equals(attachmentId))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'attachment',
        entityId: attachmentId,
        operation: 'create',
        payload: rowPayload(created),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
    return await (_db.select(
      _db.attachments,
    )..where((row) => row.id.equals(attachmentId))).getSingle();
  }

  Future<void> update(Attachment attachment) async {
    final now = _clock();
    await _db.transaction(() async {
      await (_db.update(
        _db.attachments,
      )..where((row) => row.id.equals(attachment.id))).write(
        AttachmentsCompanion(
          projectId: Value(attachment.projectId),
          taskId: Value(attachment.taskId),
          fileName: Value(attachment.fileName),
          storageKey: Value(attachment.storageKey),
          sizeBytes: Value(attachment.sizeBytes),
          sha256: Value(attachment.sha256),
          mimeType: Value(attachment.mimeType),
          kind: Value(attachment.kind),
          note: Value(attachment.note),
          isLocalOnly: Value(attachment.isLocalOnly),
          encryptionKey: Value(attachment.encryptionKey),
          categoryIdsJson: Value(attachment.categoryIdsJson),
          updatedAt: Value(now),
        ),
      );
      await recordSyncChange(
        _db,
        entityType: 'attachment',
        entityId: attachment.id,
        operation: 'update',
        payload: rowPayload(attachment, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }

  Future<void> softDelete(String id) async {
    final now = _clock();
    await _db.transaction(() async {
      final row =
          await (_db.select(_db.attachments)
                ..where((r) => r.id.equals(id) & r.deletedAt.isNull()))
              .getSingleOrNull();
      if (row == null) return;
      await (_db.update(_db.attachments)..where((r) => r.id.equals(id))).write(
        AttachmentsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
      await recordSyncChange(
        _db,
        entityType: 'attachment',
        entityId: id,
        operation: 'delete',
        payload: rowPayload(row, deletedAt: now, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }
}
