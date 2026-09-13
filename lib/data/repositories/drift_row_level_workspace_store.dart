// RowLevelWorkspaceStore 的 drift 生产实现。
//
// 组合各实体 Repository 完成写入；多行操作（项目编辑的差异对齐、待办与
// 子待办、看板重排）包在一个外层事务里，内层 Repository 事务退化为
// savepoint，保证整次写入与全部 sync_changes 审计要么全提交要么全回滚。
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../application/row_level_workspace_store.dart';
import '../../domain/cardory_models.dart';
import '../db/app_database.dart' as db;
import 'asset_repository.dart';
import 'attachment_repositories.dart';
import 'project_repository.dart';
import 'task_repository.dart';

class DriftRowLevelWorkspaceStore implements RowLevelWorkspaceStore {
  DriftRowLevelWorkspaceStore(this._db);

  final db.AppDatabase _db;

  late final _projects = ProjectRepository(_db);
  late final _tasks = TaskRepository(_db);
  late final _assets = AssetRepository(_db);
  late final _assetTags = AssetTagRepository(_db);
  late final _attachments = AttachmentRecordRepository(_db);
  late final _categories = AttachmentCategoryRepository(_db);

  int get _now => DateTime.now().toUtc().millisecondsSinceEpoch;

  static int? _millis(DateTime? value) => value?.toUtc().millisecondsSinceEpoch;

  // ---- 项目 ----

  @override
  Future<void> addProject(ProjectData project) => _db.transaction(() async {
    await _projects.create(
      name: project.title,
      description: project.description,
      status: project.stage.name,
      priority: project.priority.name,
      id: project.id,
      startAt: _millis(project.startDate),
      dueAt: _millis(project.endDate),
      sortOrder: await _nextProjectSortOrder(),
    );
    for (final entry in project.progressEntries) {
      await _createProgressEntry(project.id, entry);
    }
    for (final category in project.categories) {
      await _categories.create(
        projectId: project.id,
        name: category.name,
        id: category.id,
      );
    }
    for (final attachment in project.attachments) {
      await _createAttachment(project.id, attachment);
    }
  });

  @override
  Future<void> updateProject(ProjectData original, ProjectData updated) =>
      _db.transaction(() async {
        final row = await _projectRow(updated.id);
        if (row == null) throw StateError('项目不存在：${updated.id}');
        await _projects.update(
          row.copyWith(
            name: updated.title,
            description: updated.description,
            status: updated.stage.name,
            priority: updated.priority.name,
            startAt: Value(_millis(updated.startDate)),
            dueAt: Value(_millis(updated.endDate)),
            currentProgress: updated.progress,
          ),
        );
        await _reconcileProgressEntries(updated.id, original, updated);
        await _reconcileCategories(updated.id, original, updated);
        await _reconcileAttachments(updated.id, original, updated);
      });

  @override
  Future<void> deleteProject(String projectId) =>
      _projects.softDelete(projectId);

  @override
  Future<void> reorderProjects(List<ProjectData> orderedProjects) =>
      _db.transaction(() async {
        final rows = await _projects.loadVisible();
        final order = {
          for (final (index, project) in orderedProjects.indexed)
            project.id: (index, project.stage.name),
        };
        var fallback = orderedProjects.length;
        for (final row in rows) {
          final target = order[row.id];
          final (sortOrder, status) = target ?? (fallback++, row.status);
          if (row.sortOrder == sortOrder && row.status == status) continue;
          await _projects.update(
            row.copyWith(sortOrder: sortOrder, status: status),
          );
        }
      });

  Future<void> _createProgressEntry(
    String projectId,
    ProjectProgressEntry entry,
  ) => _projects.createProgressEntry(
    projectId: projectId,
    progress: entry.progress,
    note: entry.note,
    recordedAt: _millis(entry.createdAt),
    id: entry.id,
  );

  Future<void> _reconcileProgressEntries(
    String projectId,
    ProjectData original,
    ProjectData updated,
  ) async {
    final before = {
      for (final entry in original.progressEntries) entry.id: entry,
    };
    final updatedIds = updated.progressEntries.map((entry) => entry.id).toSet();

    for (final entry in updated.progressEntries) {
      final previous = before[entry.id];
      if (previous == null) {
        await _createProgressEntry(projectId, entry);
        continue;
      }
      if (previous.progress == entry.progress && previous.note == entry.note) {
        continue;
      }
      final row = await _progressRow(entry.id);
      if (row == null) continue;
      await _projects.updateProgressEntry(
        row.copyWith(progress: entry.progress, note: entry.note),
      );
    }
    for (final id in before.keys.where((id) => !updatedIds.contains(id))) {
      await _projects.softDeleteProgressEntry(id);
    }
  }

  Future<void> _reconcileCategories(
    String projectId,
    ProjectData original,
    ProjectData updated,
  ) async {
    final before = {
      for (final category in original.categories) category.id: category,
    };
    final updatedIds = updated.categories
        .map((category) => category.id)
        .toSet();

    for (final category in updated.categories) {
      final previous = before[category.id];
      if (previous == null) {
        await _categories.create(
          projectId: projectId,
          name: category.name,
          id: category.id,
        );
      } else if (previous.name != category.name) {
        await _categories.rename(category.id, category.name);
      }
    }
    for (final id in before.keys.where((id) => !updatedIds.contains(id))) {
      await _categories.softDelete(id);
    }
  }

  Future<void> _reconcileAttachments(
    String projectId,
    ProjectData original,
    ProjectData updated,
  ) async {
    bool same(AttachmentData a, AttachmentData b) =>
        a.fileName == b.fileName &&
        a.storageKey == b.storageKey &&
        a.size == b.size &&
        a.sha256 == b.sha256 &&
        a.mimeType == b.mimeType &&
        a.note == b.note &&
        a.encryptionKey == b.encryptionKey &&
        a.kind == b.kind &&
        _sameIds(a.categoryIds, b.categoryIds);

    final before = {
      for (final attachment in original.attachments) attachment.id: attachment,
    };
    final updatedIds = updated.attachments
        .map((attachment) => attachment.id)
        .toSet();

    for (final attachment in updated.attachments) {
      final previous = before[attachment.id];
      if (previous == null) {
        await _createAttachment(projectId, attachment);
        continue;
      }
      if (same(previous, attachment)) continue;
      final row = await _attachmentRow(attachment.id);
      if (row == null) continue;
      await _attachments.update(
        row.copyWith(
          fileName: attachment.fileName,
          storageKey: attachment.storageKey,
          sizeBytes: attachment.size,
          sha256: attachment.sha256,
          mimeType: attachment.mimeType,
          note: attachment.note,
          encryptionKey: attachment.encryptionKey,
          kind: attachment.kind.name,
          categoryIdsJson: jsonEncode(attachment.categoryIds),
        ),
      );
    }
    for (final id in before.keys.where((id) => !updatedIds.contains(id))) {
      await _attachments.softDelete(id);
    }
  }

  Future<void> _createAttachment(String projectId, AttachmentData attachment) =>
      _attachments.create(
        projectId: projectId,
        fileName: attachment.fileName,
        storageKey: attachment.storageKey,
        sizeBytes: attachment.size,
        sha256: attachment.sha256,
        mimeType: attachment.mimeType,
        kind: attachment.kind.name,
        note: attachment.note,
        encryptionKey: attachment.encryptionKey,
        categoryIds: attachment.categoryIds,
        id: attachment.id,
        createdAt: _millis(attachment.createdAt),
      );

  Future<int> _nextProjectSortOrder() async {
    final maxOrder = _db.projects.sortOrder.max();
    final query = _db.selectOnly(_db.projects)..addColumns([maxOrder]);
    final row = await query.getSingle();
    return (row.read(maxOrder) ?? -1) + 1;
  }

  Future<db.Project?> _projectRow(String id) =>
      (_db.select(_db.projects)
            ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
          .getSingleOrNull();

  Future<db.ProjectProgressEntry?> _progressRow(String id) =>
      (_db.select(_db.projectProgressEntries)
            ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
          .getSingleOrNull();

  Future<db.Attachment?> _attachmentRow(String id) =>
      (_db.select(_db.attachments)
            ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
          .getSingleOrNull();

  // ---- 待办与子待办 ----

  @override
  Future<void> addTodo(TodoData todo) => _db.transaction(() async {
    final projectId = todo.projectId.isEmpty ? null : todo.projectId;
    await _tasks.create(
      title: todo.title,
      projectId: projectId,
      notes: todo.description,
      status: todo.done ? 'done' : 'todo',
      completedAt: todo.done ? _now : null,
      priority: todo.priority.name,
      id: todo.id,
      startAt: _millis(todo.startDate),
      dueAt: _millis(todo.endDate),
      sortOrder: await _nextTaskSortOrder(),
    );
    for (final (index, subTodo) in todo.subTodos.indexed) {
      await _createSubTodo(todo.id, projectId, subTodo, index);
    }
  });

  @override
  Future<void> updateTodo(TodoData original, TodoData updated) =>
      _db.transaction(() async {
        final row = await _taskRow(updated.id);
        if (row == null) throw StateError('待办不存在：${updated.id}');
        final now = _now;
        await _tasks.update(
          row.copyWith(
            projectId: Value<String?>(
              updated.projectId.isEmpty ? null : updated.projectId,
            ),
            title: updated.title,
            notes: updated.description,
            priority: updated.priority.name,
            startAt: Value(_millis(updated.startDate)),
            dueAt: Value(_millis(updated.endDate)),
            status: updated.done ? 'done' : 'todo',
            completedAt: Value(
              updated.done ? (original.done ? row.completedAt : now) : null,
            ),
          ),
        );
        await _reconcileSubTodos(updated, original.subTodos, updated.subTodos);
      });

  @override
  Future<void> deleteTodo(String todoId) => _tasks.softDelete(todoId);

  @override
  Future<void> setTodoDone(String todoId, {required bool done}) =>
      _tasks.setDone(todoId, done: done);

  @override
  Future<void> addSubTodo(TodoData todo, SubTodoData subTodo) async {
    await _tasks.create(
      title: subTodo.content,
      projectId: todo.projectId.isEmpty ? null : todo.projectId,
      parentTaskId: todo.id,
      dueAt: _millis(subTodo.dueAt),
      createdAt: _millis(subTodo.createdAt),
      sortOrder: await _nextTaskSortOrder(),
    );
  }

  @override
  Future<void> setSubTodoDone(String subTodoId, {required bool done}) =>
      _tasks.setDone(subTodoId, done: done);

  Future<void> _createSubTodo(
    String parentTaskId,
    String? projectId,
    SubTodoData subTodo,
    int sortOrder,
  ) => _tasks.create(
    title: subTodo.content,
    projectId: projectId,
    parentTaskId: parentTaskId,
    status: subTodo.done ? 'done' : 'todo',
    completedAt: subTodo.done ? _now : null,
    dueAt: _millis(subTodo.dueAt),
    id: subTodo.id,
    sortOrder: sortOrder,
    createdAt: _millis(subTodo.createdAt),
  );

  Future<void> _reconcileSubTodos(
    TodoData parent,
    List<SubTodoData> original,
    List<SubTodoData> updated,
  ) async {
    final now = _now;
    final before = {for (final subTodo in original) subTodo.id: subTodo};
    final updatedIds = updated.map((subTodo) => subTodo.id).toSet();

    for (final (index, subTodo) in updated.indexed) {
      final previous = before[subTodo.id];
      if (previous == null) {
        await _createSubTodo(
          parent.id,
          parent.projectId.isEmpty ? null : parent.projectId,
          subTodo,
          index,
        );
        continue;
      }
      if (previous.content == subTodo.content &&
          previous.done == subTodo.done &&
          previous.dueAt == subTodo.dueAt) {
        continue;
      }
      final row = await _taskRow(subTodo.id);
      if (row == null) continue;
      await _tasks.update(
        row.copyWith(
          title: subTodo.content,
          status: subTodo.done ? 'done' : 'todo',
          completedAt: Value(
            subTodo.done ? (previous.done ? row.completedAt : now) : null,
          ),
          dueAt: Value(_millis(subTodo.dueAt)),
        ),
      );
    }
    for (final id in before.keys.where((id) => !updatedIds.contains(id))) {
      await _tasks.softDelete(id);
    }
  }

  Future<int> _nextTaskSortOrder() async {
    final maxOrder = _db.tasks.sortOrder.max();
    final query = _db.selectOnly(_db.tasks)..addColumns([maxOrder]);
    final row = await query.getSingle();
    return (row.read(maxOrder) ?? -1) + 1;
  }

  Future<db.Task?> _taskRow(String id) =>
      (_db.select(_db.tasks)
            ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
          .getSingleOrNull();

  // ---- 资产与标签 ----

  @override
  Future<void> addAsset(AssetData asset) => _assets.create(
    type: asset.type.name,
    title: asset.name,
    projectId: asset.projectId.isEmpty ? null : asset.projectId,
    uriOrPath: asset.path,
    note: asset.note,
    tagIds: asset.tagIds,
    metadata: _assetMetadata(asset),
    sensitiveJson: jsonEncode(_assetSensitive(asset)),
    id: asset.id,
  );

  @override
  Future<void> editAsset(AssetData original, AssetData updated) async {
    final row = await _assetRow(updated.id);
    if (row == null) throw StateError('资产不存在：${updated.id}');
    await _assets.update(
      row.copyWith(
        type: updated.type.name,
        title: updated.name,
        uriOrPath: updated.path,
        note: updated.note,
        projectId: Value<String?>(
          updated.projectId.isEmpty ? null : updated.projectId,
        ),
        tagsJson: jsonEncode(updated.tagIds),
        metadataJson: jsonEncode(_assetMetadata(updated)),
        sensitiveJson: Value<String?>(jsonEncode(_assetSensitive(updated))),
      ),
    );
  }

  @override
  Future<void> deleteAsset(String assetId) => _assets.softDelete(assetId);

  @override
  Future<void> addAssetTag(AssetTag tag) =>
      _assetTags.create(name: tag.name, id: tag.id);

  @override
  Future<void> updateAssetTag(AssetTag tag) =>
      _assetTags.rename(tag.id, tag.name);

  @override
  Future<void> deleteAssetTag(String tagId) => _assetTags.softDelete(tagId);

  @override
  Future<void> updateAssetsTags(Set<String> assetIds, Set<String> tagIds) =>
      _db.transaction(() async {
        final encoded = jsonEncode(tagIds.toList());
        for (final id in assetIds) {
          final row = await _assetRow(id);
          if (row == null) continue;
          await _assets.update(row.copyWith(tagsJson: encoded));
        }
      });

  Map<String, dynamic> _assetMetadata(AssetData asset) => {
    'version': asset.version,
    'port': asset.port,
    'serialNumber': asset.serialNumber,
    'network': asset.network,
    'serverType': asset.serverType,
    'activities': [for (final activity in asset.activities) activity.toJson()],
  };

  Map<String, dynamic> _assetSensitive(AssetData asset) => {
    'username': asset.username,
    'password': asset.password,
  };

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<db.Asset?> _assetRow(String id) =>
      (_db.select(_db.assets)
            ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
          .getSingleOrNull();
}
