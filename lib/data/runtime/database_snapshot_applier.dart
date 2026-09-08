// UI 快照写入的增量对齐器（DatabaseSnapshotApplier）。
//
// 背景：UI 写入口目前仍以“整包 CardoryData”调用仓储的 save()。旧实现把
// 业务表物理删除后全量重插，每次保存都会：
//   - 抹掉行级 Repository 留下的 tombstone / 时间语义；
//   - 把所有行的 createdAt 重置、updatedAt 全部刷新；
//   - 不为任何实体追加 sync_changes 审计（导致远端无法按增量重建）。
//
// 本对齐器把“整包快照”解释为“期望的可见终态”，并在单个数据库事务内完成：
//   - 逐行比较数据库可见行与快照期望值，仅写入真正发生变化的行；
//   - 新增/变更行保留 createdAt 并追加完整 payload 的 create/update 审计；
//   - 快照中已消失的可见行仅做 tombstone（软删除），并追加 delete 审计；
//   - 绝不动 TimeEntries/PomodoroSessions/TaskDependencies/SyncChanges 等
//     快照之外的数据；快照只管理项目、任务（待办+子待办）、资产、标签及其
//     项目级子表（进度记录、附件、附件分类）。
//
// 后续阶段把 UI 写入口全部迁移到行级 Repository 后，本类仅保留给同步导入
// （manualMerge/keepLocal 落库）使用；届时整个快照仍是同一套终态语义。
import 'dart:convert';

import 'package:drift/drift.dart' as drift;

import '../../domain/asset_models.dart';
import '../../domain/cardory_data.dart';
import '../../domain/project_models.dart';
import '../../domain/todo_models.dart';
import '../db/app_database.dart'
    hide AssetTag, AttachmentCategory, ProjectProgressEntry;
import '../repositories/repository_support.dart';

/// 资产行写审计时永不进入 sync_changes 的敏感列。
const _assetPayloadExclude = {'sensitiveJson'};

/// 将一整套 DTO 快照与 SQLCipher 数据库做行级增量对齐（单事务、幂等）。
class DatabaseSnapshotApplier {
  DatabaseSnapshotApplier(this._db, {Clock? clock, String? deviceId})
    : _clock = clock ?? nowUtcMillis,
      _deviceId = deviceId ?? repositoryUuid.v4();

  final AppDatabase _db;
  final Clock _clock;
  final String _deviceId;

  Future<void> apply(CardoryData data) => _db.transaction(() async {
    final now = _clock();
    // 项目先行：项目若从快照消失，其子表由各自 reconcile 一并收口 tombstone。
    await _reconcileProjects(data.projects, now);
    await _reconcileProgressEntries(data.projects, now);
    await _reconcileAttachmentCategories(data.projects, now);
    await _reconcileAttachments(data.projects, now);
    await _reconcileTasks(data.todos, now);
    await _reconcileAssetTags(data.assetTags, now);
    await _reconcileAssets(data.assets, now);
  });

  // ---------------------------------------------------------------- 项目

  Future<void> _reconcileProjects(List<ProjectData> projects, int now) async {
    final visible = await (_db.select(
      _db.projects,
    )..where((row) => row.deletedAt.isNull())).get();
    final byId = {for (final row in visible) row.id: row};
    final desiredIds = projects.map((item) => item.id).toSet();

    var sortOrder = 0;
    for (final project in projects) {
      final desired = _projectFields(project, sortOrder);
      final existing = byId[project.id];
      if (existing == null) {
        await _insertProject(project, sortOrder, now);
      } else if (!_sameFields(existing.toJson(), desired)) {
        await _updateProject(project, sortOrder, now);
      }
      sortOrder += 1;
    }
    for (final row in visible) {
      if (desiredIds.contains(row.id)) continue;
      await _tombstone(
        entityType: 'project',
        entityId: row.id,
        row: row,
        markDeleted: () =>
            (_db.update(_db.projects)..where((r) => r.id.equals(row.id))).write(
              ProjectsCompanion(
                deletedAt: drift.Value(now),
                updatedAt: drift.Value(now),
              ),
            ),
        now: now,
      );
    }
  }

  Map<String, Object?> _projectFields(ProjectData project, int sortOrder) => {
    'id': project.id,
    'name': project.title,
    'description': project.description,
    'status': project.stage.name,
    'priority': project.priority.name,
    'startAt': project.startDate?.toUtc().millisecondsSinceEpoch,
    'dueAt': project.endDate?.toUtc().millisecondsSinceEpoch,
    'sortOrder': sortOrder,
    'currentProgress': project.progress.toDouble(),
  };

  Future<void> _insertProject(
    ProjectData project,
    int sortOrder,
    int now,
  ) async {
    final companion = ProjectsCompanion.insert(
      id: project.id,
      name: project.title,
      description: drift.Value(project.description),
      status: project.stage.name,
      priority: project.priority.name,
      startAt: drift.Value(project.startDate?.toUtc().millisecondsSinceEpoch),
      dueAt: drift.Value(project.endDate?.toUtc().millisecondsSinceEpoch),
      sortOrder: drift.Value(sortOrder),
      currentProgress: drift.Value(project.progress.toDouble()),
      createdAt: now,
      updatedAt: now,
    );
    await _insertOrRevive(
      entityType: 'project',
      entityId: project.id,
      doInsert: () => _db.into(_db.projects).insert(companion),
      auditCreate: () async => _audit(
        entityType: 'project',
        entityId: project.id,
        operation: 'create',
        row: await _readProject(project.id),
        now: now,
      ),
      revive: () async {
        final cleared =
            await (_db.update(
              _db.projects,
            )..where((row) => row.id.equals(project.id))).write(
              ProjectsCompanion(
                name: drift.Value(project.title),
                description: drift.Value(project.description),
                status: drift.Value(project.stage.name),
                priority: drift.Value(project.priority.name),
                startAt: drift.Value(
                  project.startDate?.toUtc().millisecondsSinceEpoch,
                ),
                dueAt: drift.Value(
                  project.endDate?.toUtc().millisecondsSinceEpoch,
                ),
                sortOrder: drift.Value(sortOrder),
                currentProgress: drift.Value(project.progress.toDouble()),
                deletedAt: const drift.Value(null),
                updatedAt: drift.Value(now),
              ),
            );
        if (cleared == 0) return false;
        await _audit(
          entityType: 'project',
          entityId: project.id,
          operation: 'update',
          row: await _readProject(project.id),
          now: now,
        );
        return true;
      },
    );
  }

  Future<void> _updateProject(
    ProjectData project,
    int sortOrder,
    int now,
  ) async {
    await (_db.update(
      _db.projects,
    )..where((row) => row.id.equals(project.id))).write(
      ProjectsCompanion(
        name: drift.Value(project.title),
        description: drift.Value(project.description),
        status: drift.Value(project.stage.name),
        priority: drift.Value(project.priority.name),
        startAt: drift.Value(project.startDate?.toUtc().millisecondsSinceEpoch),
        dueAt: drift.Value(project.endDate?.toUtc().millisecondsSinceEpoch),
        sortOrder: drift.Value(sortOrder),
        currentProgress: drift.Value(project.progress.toDouble()),
        updatedAt: drift.Value(now),
      ),
    );
    await _audit(
      entityType: 'project',
      entityId: project.id,
      operation: 'update',
      row: await _readProject(project.id),
      now: now,
    );
  }

  // ---------------------------------------------------------- 项目进度记录

  Future<void> _reconcileProgressEntries(
    List<ProjectData> projects,
    int now,
  ) async {
    final visible = await (_db.select(
      _db.projectProgressEntries,
    )..where((row) => row.deletedAt.isNull())).get();
    final desired = <String, Map<String, Object?>>{
      for (final project in projects)
        for (final entry in project.progressEntries)
          entry.id: _progressFields(project.id, entry),
    };
    for (final row in visible) {
      final fields = desired[row.id];
      if (fields == null) {
        await _tombstone(
          entityType: 'project_progress_entry',
          entityId: row.id,
          row: row,
          markDeleted: () =>
              (_db.update(
                _db.projectProgressEntries,
              )..where((r) => r.id.equals(row.id))).write(
                ProjectProgressEntriesCompanion(
                  deletedAt: drift.Value(now),
                  updatedAt: drift.Value(now),
                ),
              ),
          now: now,
        );
      } else if (!_sameFields(row.toJson(), fields)) {
        await _updateProgressEntry(row.id, fields, now);
      }
    }
    final visibleIds = {for (final row in visible) row.id};
    for (final entry in desired.entries) {
      if (visibleIds.contains(entry.key)) continue;
      final fields = entry.value;
      final id = entry.key;
      await _insertOrRevive(
        entityType: 'project_progress_entry',
        entityId: id,
        doInsert: () => _db
            .into(_db.projectProgressEntries)
            .insert(
              ProjectProgressEntriesCompanion.insert(
                id: id,
                projectId: fields['projectId']! as String,
                progress: fields['progress']! as double,
                note: drift.Value(fields['note']! as String),
                recordedAt: fields['recordedAt']! as int,
                createdAt: now,
                updatedAt: now,
              ),
            ),
        auditCreate: () async => _audit(
          entityType: 'project_progress_entry',
          entityId: id,
          operation: 'create',
          row: await _readProgressEntry(id),
          now: now,
        ),
        revive: () async {
          final cleared =
              await (_db.update(
                _db.projectProgressEntries,
              )..where((row) => row.id.equals(id))).write(
                ProjectProgressEntriesCompanion(
                  deletedAt: const drift.Value(null),
                ),
              );
          if (cleared == 0) return false;
          await _updateProgressEntry(id, fields, now);
          return true;
        },
      );
    }
  }

  Map<String, Object?> _progressFields(
    String projectId,
    ProjectProgressEntry entry,
  ) => {
    'id': entry.id,
    'projectId': projectId,
    'progress': entry.progress,
    'note': entry.note,
    'recordedAt': entry.createdAt.toUtc().millisecondsSinceEpoch,
  };

  Future<void> _updateProgressEntry(
    String id,
    Map<String, Object?> fields,
    int now,
  ) async {
    await (_db.update(
      _db.projectProgressEntries,
    )..where((row) => row.id.equals(id))).write(
      ProjectProgressEntriesCompanion(
        progress: drift.Value(fields['progress']! as double),
        note: drift.Value(fields['note']! as String),
        recordedAt: drift.Value(fields['recordedAt']! as int),
        updatedAt: drift.Value(now),
      ),
    );
    await _audit(
      entityType: 'project_progress_entry',
      entityId: id,
      operation: 'update',
      row: await _readProgressEntry(id),
      now: now,
    );
  }

  // ------------------------------------------------------------ 附件分类

  Future<void> _reconcileAttachmentCategories(
    List<ProjectData> projects,
    int now,
  ) async {
    final visible = await (_db.select(
      _db.attachmentCategories,
    )..where((row) => row.deletedAt.isNull())).get();
    final desired = <String, Map<String, Object?>>{
      for (final project in projects)
        for (final category in project.categories)
          category.id: _categoryFields(project.id, category),
    };
    for (final row in visible) {
      final fields = desired[row.id];
      if (fields == null) {
        await _tombstone(
          entityType: 'attachment_category',
          entityId: row.id,
          row: row,
          markDeleted: () =>
              (_db.update(
                _db.attachmentCategories,
              )..where((r) => r.id.equals(row.id))).write(
                AttachmentCategoriesCompanion(
                  deletedAt: drift.Value(now),
                  updatedAt: drift.Value(now),
                ),
              ),
          now: now,
        );
      } else if (!_sameFields(row.toJson(), fields)) {
        await _updateCategory(row.id, fields, now);
      }
    }
    final visibleIds = {for (final row in visible) row.id};
    for (final entry in desired.entries) {
      if (visibleIds.contains(entry.key)) continue;
      final fields = entry.value;
      final id = entry.key;
      await _insertOrRevive(
        entityType: 'attachment_category',
        entityId: id,
        doInsert: () => _db
            .into(_db.attachmentCategories)
            .insert(
              AttachmentCategoriesCompanion.insert(
                id: id,
                projectId: fields['projectId']! as String,
                name: fields['name']! as String,
                createdAt: now,
                updatedAt: now,
              ),
            ),
        auditCreate: () async => _audit(
          entityType: 'attachment_category',
          entityId: id,
          operation: 'create',
          row: await _readCategory(id),
          now: now,
        ),
        revive: () async {
          final cleared =
              await (_db.update(
                _db.attachmentCategories,
              )..where((row) => row.id.equals(id))).write(
                AttachmentCategoriesCompanion(
                  deletedAt: const drift.Value(null),
                ),
              );
          if (cleared == 0) return false;
          await _updateCategory(id, fields, now);
          return true;
        },
      );
    }
  }

  Map<String, Object?> _categoryFields(
    String projectId,
    AttachmentCategory category,
  ) => {'id': category.id, 'projectId': projectId, 'name': category.name};

  Future<void> _updateCategory(
    String id,
    Map<String, Object?> fields,
    int now,
  ) async {
    await (_db.update(
      _db.attachmentCategories,
    )..where((row) => row.id.equals(id))).write(
      AttachmentCategoriesCompanion(
        name: drift.Value(fields['name']! as String),
        updatedAt: drift.Value(now),
      ),
    );
    await _audit(
      entityType: 'attachment_category',
      entityId: id,
      operation: 'update',
      row: await _readCategory(id),
      now: now,
    );
  }

  // ---------------------------------------------------------------- 附件

  Future<void> _reconcileAttachments(
    List<ProjectData> projects,
    int now,
  ) async {
    final visible = await (_db.select(
      _db.attachments,
    )..where((row) => row.deletedAt.isNull())).get();
    final desired = <String, Map<String, Object?>>{
      for (final project in projects)
        for (final attachment in project.attachments)
          attachment.id: _attachmentFields(project.id, attachment),
    };
    for (final row in visible) {
      final fields = desired[row.id];
      if (fields == null) {
        await _tombstone(
          entityType: 'attachment',
          entityId: row.id,
          row: row,
          markDeleted: () =>
              (_db.update(
                _db.attachments,
              )..where((r) => r.id.equals(row.id))).write(
                AttachmentsCompanion(
                  deletedAt: drift.Value(now),
                  updatedAt: drift.Value(now),
                ),
              ),
          now: now,
        );
      } else if (!_sameFields(row.toJson(), fields)) {
        await _updateAttachment(row.id, fields, now);
      }
    }
    final visibleIds = {for (final row in visible) row.id};
    for (final entry in desired.entries) {
      if (visibleIds.contains(entry.key)) continue;
      final fields = entry.value;
      final id = entry.key;
      await _insertOrRevive(
        entityType: 'attachment',
        entityId: id,
        doInsert: () => _db
            .into(_db.attachments)
            .insert(
              AttachmentsCompanion.insert(
                id: id,
                projectId: drift.Value(fields['projectId']! as String),
                fileName: fields['fileName']! as String,
                storageKey: fields['storageKey']! as String,
                encryptionKey: drift.Value(fields['encryptionKey']! as String),
                sizeBytes: fields['sizeBytes']! as int,
                sha256: fields['sha256']! as String,
                mimeType: drift.Value(fields['mimeType']! as String),
                kind: fields['kind']! as String,
                note: drift.Value(fields['note']! as String),
                categoryIdsJson: drift.Value(
                  fields['categoryIdsJson']! as String,
                ),
                createdAt: now,
                updatedAt: now,
              ),
            ),
        auditCreate: () async => _audit(
          entityType: 'attachment',
          entityId: id,
          operation: 'create',
          row: await _readAttachment(id),
          now: now,
        ),
        revive: () async {
          final cleared =
              await (_db.update(
                _db.attachments,
              )..where((row) => row.id.equals(id))).write(
                AttachmentsCompanion(deletedAt: const drift.Value(null)),
              );
          if (cleared == 0) return false;
          await _updateAttachment(id, fields, now);
          return true;
        },
      );
    }
  }

  Map<String, Object?> _attachmentFields(
    String projectId,
    AttachmentData attachment,
  ) => {
    'id': attachment.id,
    'projectId': projectId,
    'fileName': attachment.fileName,
    'storageKey': attachment.storageKey,
    'encryptionKey': attachment.encryptionKey,
    'sizeBytes': attachment.size,
    'sha256': attachment.sha256,
    'mimeType': attachment.mimeType,
    'kind': attachment.kind.name,
    'note': attachment.note,
    'categoryIdsJson': jsonEncode(attachment.categoryIds),
  };

  Future<void> _updateAttachment(
    String id,
    Map<String, Object?> fields,
    int now,
  ) async {
    await (_db.update(
      _db.attachments,
    )..where((row) => row.id.equals(id))).write(
      AttachmentsCompanion(
        fileName: drift.Value(fields['fileName']! as String),
        storageKey: drift.Value(fields['storageKey']! as String),
        encryptionKey: drift.Value(fields['encryptionKey']! as String),
        sizeBytes: drift.Value(fields['sizeBytes']! as int),
        sha256: drift.Value(fields['sha256']! as String),
        mimeType: drift.Value(fields['mimeType']! as String),
        kind: drift.Value(fields['kind']! as String),
        note: drift.Value(fields['note']! as String),
        categoryIdsJson: drift.Value(fields['categoryIdsJson']! as String),
        updatedAt: drift.Value(now),
      ),
    );
    await _audit(
      entityType: 'attachment',
      entityId: id,
      operation: 'update',
      row: await _readAttachment(id),
      now: now,
    );
  }

  // ------------------------------------------------------ 任务（待办+子待办）

  Future<void> _reconcileTasks(List<TodoData> todos, int now) async {
    final visible = await (_db.select(
      _db.tasks,
    )..where((row) => row.deletedAt.isNull())).get();
    final desired = <String, Map<String, Object?>>{};
    var parentOrder = 0;
    for (final todo in todos) {
      desired[todo.id] = _taskFields(
        todo,
        projectId: todo.projectId.isEmpty ? null : todo.projectId,
        parentTaskId: null,
        sortOrder: parentOrder,
      );
      var childOrder = 0;
      for (final subTodo in todo.subTodos) {
        desired[subTodo.id] = _subTaskFields(todo, subTodo, childOrder);
        childOrder += 1;
      }
      parentOrder += 1;
    }
    for (final row in visible) {
      final fields = desired[row.id];
      if (fields == null) {
        await _tombstone(
          entityType: 'task',
          entityId: row.id,
          row: row,
          markDeleted: () =>
              (_db.update(_db.tasks)..where((r) => r.id.equals(row.id))).write(
                TasksCompanion(
                  deletedAt: drift.Value(now),
                  updatedAt: drift.Value(now),
                ),
              ),
          now: now,
        );
      } else if (!_sameFields(row.toJson(), fields)) {
        await _updateTask(row.id, fields, now);
      }
    }
    final visibleIds = {for (final row in visible) row.id};
    for (final entry in desired.entries) {
      if (visibleIds.contains(entry.key)) continue;
      await _insertTask(entry.key, entry.value, now);
    }
  }

  Map<String, Object?> _taskFields(
    TodoData todo, {
    required String? projectId,
    required String? parentTaskId,
    required int sortOrder,
  }) => {
    'id': todo.id,
    'projectId': projectId,
    'parentTaskId': parentTaskId,
    'title': todo.title,
    'notes': todo.description,
    'status': todo.done ? 'done' : 'todo',
    'priority': todo.priority.name,
    'startAt': todo.startDate?.toUtc().millisecondsSinceEpoch,
    'dueAt': todo.endDate?.toUtc().millisecondsSinceEpoch,
    'sortOrder': sortOrder,
  };

  Map<String, Object?> _subTaskFields(
    TodoData todo,
    SubTodoData subTodo,
    int sortOrder,
  ) => {
    'id': subTodo.id,
    'projectId': todo.projectId.isEmpty ? null : todo.projectId,
    'parentTaskId': todo.id,
    'title': subTodo.content,
    'notes': '',
    'status': subTodo.done ? 'done' : 'todo',
    'priority': todo.priority.name,
    'startAt': null,
    'dueAt': subTodo.dueAt?.toUtc().millisecondsSinceEpoch,
    'sortOrder': sortOrder,
  };

  Future<void> _insertTask(
    String id,
    Map<String, Object?> fields,
    int now,
  ) async {
    final companion = TasksCompanion.insert(
      id: id,
      projectId: drift.Value(fields['projectId'] as String?),
      parentTaskId: drift.Value(fields['parentTaskId'] as String?),
      title: fields['title']! as String,
      notes: drift.Value(fields['notes']! as String),
      status: fields['status']! as String,
      priority: fields['priority']! as String,
      startAt: drift.Value(fields['startAt'] as int?),
      dueAt: drift.Value(fields['dueAt'] as int?),
      sortOrder: drift.Value(fields['sortOrder']! as int),
      completedAt: drift.Value(fields['status'] == 'done' ? now : null),
      createdAt: now,
      updatedAt: now,
    );
    await _insertOrRevive(
      entityType: 'task',
      entityId: id,
      doInsert: () => _db.into(_db.tasks).insert(companion),
      auditCreate: () async => _audit(
        entityType: 'task',
        entityId: id,
        operation: 'create',
        row: await _readTask(id),
        now: now,
      ),
      revive: () async {
        final cleared =
            await (_db.update(_db.tasks)..where((row) => row.id.equals(id)))
                .write(TasksCompanion(deletedAt: const drift.Value(null)));
        if (cleared == 0) return false;
        await _updateTask(id, fields, now);
        return true;
      },
    );
  }

  Future<void> _updateTask(
    String id,
    Map<String, Object?> fields,
    int now,
  ) async {
    final existing = await (_db.select(
      _db.tasks,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    final becomingDone = fields['status'] == 'done';
    await (_db.update(_db.tasks)..where((row) => row.id.equals(id))).write(
      TasksCompanion(
        projectId: drift.Value(fields['projectId'] as String?),
        parentTaskId: drift.Value(fields['parentTaskId'] as String?),
        title: drift.Value(fields['title']! as String),
        notes: drift.Value(fields['notes']! as String),
        status: drift.Value(fields['status']! as String),
        priority: drift.Value(fields['priority']! as String),
        startAt: drift.Value(fields['startAt'] as int?),
        dueAt: drift.Value(fields['dueAt'] as int?),
        sortOrder: drift.Value(fields['sortOrder']! as int),
        completedAt: drift.Value(
          becomingDone ? (existing?.completedAt ?? now) : null,
        ),
        updatedAt: drift.Value(now),
      ),
    );
    await _audit(
      entityType: 'task',
      entityId: id,
      operation: 'update',
      row: await _readTask(id),
      now: now,
    );
  }

  // ------------------------------------------------------------ 资产标签

  Future<void> _reconcileAssetTags(List<AssetTag> tags, int now) async {
    final visible = await (_db.select(
      _db.assetTags,
    )..where((row) => row.deletedAt.isNull())).get();
    final desired = {for (final tag in tags) tag.id: tag.name};
    for (final row in visible) {
      final name = desired[row.id];
      if (name == null) {
        await _tombstone(
          entityType: 'asset_tag',
          entityId: row.id,
          row: row,
          markDeleted: () =>
              (_db.update(
                _db.assetTags,
              )..where((r) => r.id.equals(row.id))).write(
                AssetTagsCompanion(
                  deletedAt: drift.Value(now),
                  updatedAt: drift.Value(now),
                ),
              ),
          now: now,
        );
      } else if (row.name != name) {
        await _updateAssetTagRow(row.id, name, now);
      }
    }
    final visibleIds = {for (final row in visible) row.id};
    for (final entry in desired.entries) {
      if (visibleIds.contains(entry.key)) continue;
      final id = entry.key;
      final name = entry.value;
      await _insertOrRevive(
        entityType: 'asset_tag',
        entityId: id,
        doInsert: () => _db
            .into(_db.assetTags)
            .insert(
              AssetTagsCompanion.insert(
                id: id,
                name: name,
                createdAt: now,
                updatedAt: now,
              ),
            ),
        auditCreate: () async => _audit(
          entityType: 'asset_tag',
          entityId: id,
          operation: 'create',
          row: await _readAssetTag(id),
          now: now,
        ),
        revive: () async {
          final cleared =
              await (_db.update(
                _db.assetTags,
              )..where((row) => row.id.equals(id))).write(
                AssetTagsCompanion(deletedAt: const drift.Value(null)),
              );
          if (cleared == 0) return false;
          await _updateAssetTagRow(id, name, now);
          return true;
        },
      );
    }
  }

  /// 行级写资产标签名称（含审计）。
  Future<void> _updateAssetTagRow(String id, String name, int now) async {
    await (_db.update(_db.assetTags)..where((row) => row.id.equals(id))).write(
      AssetTagsCompanion(name: drift.Value(name), updatedAt: drift.Value(now)),
    );
    await _audit(
      entityType: 'asset_tag',
      entityId: id,
      operation: 'update',
      row: await _readAssetTag(id),
      now: now,
    );
  }

  // ---------------------------------------------------------------- 资产

  Future<void> _reconcileAssets(List<AssetData> assets, int now) async {
    final visible = await (_db.select(
      _db.assets,
    )..where((row) => row.deletedAt.isNull())).get();
    final desired = {for (final asset in assets) asset.id: _assetFields(asset)};
    for (final row in visible) {
      final fields = desired[row.id];
      if (fields == null) {
        await _tombstone(
          entityType: 'asset',
          entityId: row.id,
          row: row,
          excludePayload: _assetPayloadExclude,
          markDeleted: () =>
              (_db.update(_db.assets)..where((r) => r.id.equals(row.id))).write(
                AssetsCompanion(
                  deletedAt: drift.Value(now),
                  updatedAt: drift.Value(now),
                ),
              ),
          now: now,
        );
      } else if (!_sameFields(row.toJson(), fields)) {
        await _updateAsset(row.id, fields, now);
      }
    }
    final visibleIds = {for (final row in visible) row.id};
    for (final entry in desired.entries) {
      if (visibleIds.contains(entry.key)) continue;
      await _insertAsset(entry.key, entry.value, now);
    }
  }

  Map<String, Object?> _assetFields(AssetData asset) {
    final sensitive = <String, String>{
      if (asset.username.isNotEmpty) 'username': asset.username,
      if (asset.password.isNotEmpty) 'password': asset.password,
    };
    final metadata = <String, Object>{
      'version': asset.version,
      'port': asset.port,
      'serialNumber': asset.serialNumber,
      'network': asset.network,
      'serverType': asset.serverType,
      'activities': asset.activities
          .map((activity) => activity.toJson())
          .toList(),
    };
    return {
      'id': asset.id,
      'projectId': asset.projectId.isEmpty ? null : asset.projectId,
      'type': asset.type.name,
      'title': asset.name,
      'uriOrPath': asset.path,
      'note': asset.note,
      'tagsJson': jsonEncode(asset.tagIds),
      'metadataJson': jsonEncode(metadata),
      'sensitiveJson': sensitive.isEmpty ? null : jsonEncode(sensitive),
    };
  }

  Future<void> _insertAsset(
    String id,
    Map<String, Object?> fields,
    int now,
  ) async {
    final companion = AssetsCompanion.insert(
      id: id,
      projectId: drift.Value(fields['projectId'] as String?),
      type: fields['type']! as String,
      title: fields['title']! as String,
      uriOrPath: drift.Value(fields['uriOrPath']! as String),
      note: drift.Value(fields['note']! as String),
      tagsJson: drift.Value(fields['tagsJson']! as String),
      metadataJson: drift.Value(fields['metadataJson']! as String),
      sensitiveJson: drift.Value(fields['sensitiveJson'] as String?),
      createdAt: now,
      updatedAt: now,
    );
    await _insertOrRevive(
      entityType: 'asset',
      entityId: id,
      doInsert: () => _db.into(_db.assets).insert(companion),
      auditCreate: () async => _audit(
        entityType: 'asset',
        entityId: id,
        operation: 'create',
        excludePayload: _assetPayloadExclude,
        row: await _readAsset(id),
        now: now,
      ),
      revive: () async {
        final cleared =
            await (_db.update(_db.assets)..where((row) => row.id.equals(id)))
                .write(AssetsCompanion(deletedAt: const drift.Value(null)));
        if (cleared == 0) return false;
        await _updateAsset(id, fields, now);
        return true;
      },
    );
  }

  Future<void> _updateAsset(
    String id,
    Map<String, Object?> fields,
    int now,
  ) async {
    await (_db.update(_db.assets)..where((row) => row.id.equals(id))).write(
      AssetsCompanion(
        projectId: drift.Value(fields['projectId'] as String?),
        type: drift.Value(fields['type']! as String),
        title: drift.Value(fields['title']! as String),
        uriOrPath: drift.Value(fields['uriOrPath']! as String),
        note: drift.Value(fields['note']! as String),
        tagsJson: drift.Value(fields['tagsJson']! as String),
        metadataJson: drift.Value(fields['metadataJson']! as String),
        sensitiveJson: drift.Value(fields['sensitiveJson'] as String?),
        updatedAt: drift.Value(now),
      ),
    );
    await _audit(
      entityType: 'asset',
      entityId: id,
      operation: 'update',
      excludePayload: _assetPayloadExclude,
      row: await _readAsset(id),
      now: now,
    );
  }

  // ---------------------------------------------------------------- 读回与审计

  Future<Object?> _readProject(String id) async => (await (_db.select(
    _db.projects,
  )..where((row) => row.id.equals(id))).getSingleOrNull());

  Future<Object?> _readProgressEntry(String id) async => (await (_db.select(
    _db.projectProgressEntries,
  )..where((row) => row.id.equals(id))).getSingleOrNull());

  Future<Object?> _readCategory(String id) async => (await (_db.select(
    _db.attachmentCategories,
  )..where((row) => row.id.equals(id))).getSingleOrNull());

  Future<Object?> _readAttachment(String id) async => (await (_db.select(
    _db.attachments,
  )..where((row) => row.id.equals(id))).getSingleOrNull());

  Future<Object?> _readTask(String id) async => (await (_db.select(
    _db.tasks,
  )..where((row) => row.id.equals(id))).getSingleOrNull());

  Future<Object?> _readAssetTag(String id) async => (await (_db.select(
    _db.assetTags,
  )..where((row) => row.id.equals(id))).getSingleOrNull());

  Future<Object?> _readAsset(String id) async => (await (_db.select(
    _db.assets,
  )..where((row) => row.id.equals(id))).getSingleOrNull());

  /// 仅比较快照管理的字段（按 desired 键顺序），忽略 createdAt/updatedAt/
  /// deletedAt 与快照未管理的列，避免无业务变化的行被无谓刷新。
  bool _sameFields(
    Map<String, dynamic> existing,
    Map<String, Object?> desired,
  ) {
    for (final entry in desired.entries) {
      if (existing[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// 先按新行插入；若撞上“同 id 的 tombstone 行”（例如手动合并/恢复时远端
  /// 重新带回了此前本地删除的实体），则清除 deletedAt 复活并追加 update 审计。
  /// 只有确认既有行可更新才算复活成功，否则把原始异常继续抛出。
  Future<void> _insertOrRevive({
    required String entityType,
    required String entityId,
    required Future<void> Function() doInsert,
    required Future<void> Function() auditCreate,
    required Future<bool> Function() revive,
  }) async {
    try {
      await doInsert();
      await auditCreate();
    } catch (_) {
      final revived = await revive();
      if (!revived) rethrow;
    }
  }

  /// 在事务内将可见行软删除并追加 delete 审计（幂等由调用方保证）。
  Future<void> _tombstone({
    required String entityType,
    required String entityId,
    required Object row,
    required Future<void> Function() markDeleted,
    Set<String> excludePayload = const <String>{},
    required int now,
  }) async {
    await markDeleted();
    await recordSyncChange(
      _db,
      entityType: entityType,
      entityId: entityId,
      operation: 'delete',
      payload: rowPayload(
        row,
        deletedAt: now,
        updatedAt: now,
        exclude: excludePayload,
      ),
      deviceId: _deviceId,
      createdAt: now,
    );
  }

  /// 追加 create/update 审计；[row] 为写入后回读的完整行。
  Future<void> _audit({
    required String entityType,
    required String entityId,
    required String operation,
    required Object? row,
    Set<String> excludePayload = const <String>{},
    required int now,
  }) async {
    if (row == null) return;
    await recordSyncChange(
      _db,
      entityType: entityType,
      entityId: entityId,
      operation: operation,
      payload: rowPayload(row, updatedAt: now, exclude: excludePayload),
      deviceId: _deviceId,
      createdAt: now,
    );
  }
}
