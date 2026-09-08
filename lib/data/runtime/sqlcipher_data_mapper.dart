// SQLCipher 数据库行 → 领域聚合映射。
//
// 收编自旧的「AppDatabaseLegacyMigrationAdapter」（该名称属于旧 LegacyJson
// 迁移模块）。破坏性版本下不再存在旧格式迁移：本类只保留读取侧映射
// （projects/todos/assets/assetTags 聚合），供解锁/加载/快照检查时把数据库行
// 组装为领域模型；所有写入统一走行级 Repository 或 DatabaseSnapshotApplier，
// 不再经过任何“迁移”写入口。

import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import '../../domain/cardory_models.dart';
import '../db/app_database.dart'
    hide AssetTag, AttachmentCategory, ProjectProgressEntry;

class SqlCipherDataMapper {
  const SqlCipherDataMapper(this.database);

  final AppDatabase database;

  Future<List<ProjectData>> loadProjects() async {
    final rows =
        await (database.select(database.projects)
              ..where((row) => row.deletedAt.isNull())
              ..orderBy([(row) => drift.OrderingTerm.asc(row.sortOrder)]))
            .get();
    final results = <ProjectData>[];
    for (final project in rows) {
      final progress =
          await (database.select(database.projectProgressEntries)
                ..where(
                  (row) => drift.Expression.and([
                    row.projectId.equals(project.id),
                    row.deletedAt.isNull(),
                  ]),
                )
                ..orderBy([(row) => drift.OrderingTerm.asc(row.recordedAt)]))
              .get();
      final attachments =
          await (database.select(database.attachments)..where(
                (row) => drift.Expression.and([
                  row.projectId.equals(project.id),
                  row.deletedAt.isNull(),
                ]),
              ))
              .get();
      final categories =
          await (database.select(database.attachmentCategories)..where(
                (row) => drift.Expression.and([
                  row.projectId.equals(project.id),
                  row.deletedAt.isNull(),
                ]),
              ))
              .get();
      results.add(
        ProjectData(
          id: project.id,
          title: project.name,
          description: project.description,
          startDate: _fromMillis(project.startAt),
          endDate: _fromMillis(project.dueAt),
          priority: ProjectPriority.fromName(project.priority),
          stage: ProjectStage.fromName(project.status),
          progressEntries: progress
              .map(
                (entry) => ProjectProgressEntry(
                  id: entry.id,
                  note: entry.note,
                  progress: entry.progress,
                  createdAt: _fromMillis(entry.recordedAt)!,
                ),
              )
              .toList(growable: false),
          attachments: attachments.map(_attachment).toList(growable: false),
          categories: categories
              .map(
                (category) => AttachmentCategory(
                  id: category.id,
                  name: category.name,
                  createdAt: _fromMillis(category.createdAt),
                ),
              )
              .toList(growable: false),
        ),
      );
    }
    return results;
  }

  Future<List<TodoData>> loadTodos() async {
    final projects = await (database.select(
      database.projects,
    )..where((row) => row.deletedAt.isNull())).get();
    final projectTitles = {
      for (final project in projects) project.id: project.name,
    };
    final all =
        await (database.select(database.tasks)
              ..where((row) => row.deletedAt.isNull())
              ..orderBy([(row) => drift.OrderingTerm.asc(row.sortOrder)]))
            .get();
    final childByParent = <String, List<Task>>{};
    for (final row in all.where((row) => row.parentTaskId != null)) {
      childByParent.putIfAbsent(row.parentTaskId!, () => []).add(row);
    }
    return all
        .where((row) => row.parentTaskId == null)
        .map(
          (row) => TodoData(
            id: row.id,
            title: row.title,
            description: row.notes,
            startDate: _fromMillis(row.startAt),
            endDate: _fromMillis(row.dueAt),
            projectId: row.projectId ?? '',
            projectTitle: projectTitles[row.projectId] ?? '未关联项目',
            priority: ProjectPriority.fromName(row.priority),
            done: row.status == 'done',
            subTodos: (childByParent[row.id] ?? const <Task>[])
                .map(
                  (child) => SubTodoData(
                    id: child.id,
                    content: child.title,
                    done: child.status == 'done',
                    createdAt: _fromMillis(child.createdAt),
                    dueAt: _fromMillis(child.dueAt),
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  Future<List<AssetData>> loadAssets() async {
    final rows = await (database.select(
      database.assets,
    )..where((row) => row.deletedAt.isNull())).get();
    return rows
        .map((row) {
          final sensitive = row.sensitiveJson == null
              ? const <String, dynamic>{}
              : jsonDecode(row.sensitiveJson!) as Map<String, dynamic>;
          final metadata = jsonDecode(row.metadataJson) as Map<String, dynamic>;
          return AssetData(
            id: row.id,
            type: AssetType.values.firstWhere(
              (value) => value.name == row.type,
              orElse: () => AssetType.software,
            ),
            name: row.title,
            projectId: row.projectId ?? '',
            version: metadata['version'] as String? ?? '',
            port: metadata['port'] as String? ?? '',
            path: row.uriOrPath,
            serialNumber: metadata['serialNumber'] as String? ?? '',
            network: metadata['network'] as String? ?? '',
            serverType: metadata['serverType'] as String? ?? '',
            username: sensitive['username'] as String? ?? '',
            password: sensitive['password'] as String? ?? '',
            note: row.note,
            tagIds: (jsonDecode(row.tagsJson) as List<dynamic>)
                .whereType<String>()
                .toList(),
            activities: (metadata['activities'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .map(AssetActivity.fromJson)
                .toList(growable: false),
          );
        })
        .toList(growable: false);
  }

  Future<List<AssetTag>> loadAssetTags() async {
    final rows = await (database.select(
      database.assetTags,
    )..where((row) => row.deletedAt.isNull())).get();
    return rows
        .map(
          (row) => AssetTag(
            id: row.id,
            name: row.name,
            createdAt: _fromMillis(row.createdAt),
          ),
        )
        .toList(growable: false);
  }

  AttachmentData _attachment(Attachment row) => AttachmentData(
    id: row.id,
    fileName: row.fileName,
    storageKey: row.storageKey,
    encryptionKey: row.encryptionKey,
    size: row.sizeBytes,
    sha256: row.sha256,
    mimeType: row.mimeType,
    kind: AttachmentKind.fromName(
      row.kind,
      fileName: row.fileName,
      mimeType: row.mimeType,
    ),
    note: row.note,
    createdAt: _fromMillis(row.createdAt)!,
    categoryIds: (jsonDecode(row.categoryIdsJson) as List<dynamic>)
        .whereType<String>()
        .toList(growable: false),
  );

  DateTime? _fromMillis(int? value) => value == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
}
