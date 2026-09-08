// 项目（Projects / ProjectProgressEntries）仓库。
//
// 单事务写入契约：实体行 + updatedAt + tombstone 与 sync_changes 在同一个
// drift 事务内完成；软删除项目时按依赖顺序级联标记任务、资产、附件、附件
// 分类、进度记录、计时/番茄钟记录与任务依赖，避免留下可见孤儿行。
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'repository_support.dart';

class ProjectRepository {
  ProjectRepository(this._db, {Clock? clock, String? deviceId})
    : _clock = clock ?? nowUtcMillis,
      _deviceId = deviceId ?? repositoryUuid.v4();

  final AppDatabase _db;
  final Clock _clock;
  final String _deviceId;

  Stream<List<Project>> watchProjects() =>
      (_db.select(_db.projects)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
          .watch();

  Stream<Project?> watchProject(String id) =>
      (_db.select(_db.projects)
            ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
          .watchSingleOrNull();

  Future<List<Project>> loadVisible() async =>
      await (_db.select(_db.projects)
            ..where((row) => row.deletedAt.isNull())
            ..orderBy([(row) => OrderingTerm.asc(row.sortOrder)]))
          .get();

  Future<Project> create({
    required String name,
    String description = '',
    String status = 'planned',
    String priority = 'p2',
    String? id,
    int sortOrder = 0,
    int? startAt,
    int? dueAt,
  }) async {
    final now = _clock();
    final projectId = id ?? repositoryUuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: projectId,
              name: name,
              description: Value(description),
              status: status,
              priority: priority,
              startAt: Value(startAt),
              dueAt: Value(dueAt),
              sortOrder: Value(sortOrder),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final created = await (_db.select(
        _db.projects,
      )..where((row) => row.id.equals(projectId))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'project',
        entityId: projectId,
        operation: 'create',
        payload: rowPayload(created),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
    return await (_db.select(
      _db.projects,
    )..where((row) => row.id.equals(projectId))).getSingle();
  }

  /// 用行快照更新项目的全部业务字段；createdAt 等时间戳保留原值。
  Future<void> update(Project project) async {
    final now = _clock();
    await _db.transaction(() async {
      await (_db.update(
        _db.projects,
      )..where((row) => row.id.equals(project.id))).write(
        ProjectsCompanion(
          name: Value(project.name),
          description: Value(project.description),
          color: Value(project.color),
          status: Value(project.status),
          priority: Value(project.priority),
          startAt: Value(project.startAt),
          dueAt: Value(project.dueAt),
          sortOrder: Value(project.sortOrder),
          pinned: Value(project.pinned),
          currentProgress: Value(project.currentProgress),
          updatedAt: Value(now),
        ),
      );
      await recordSyncChange(
        _db,
        entityType: 'project',
        entityId: project.id,
        operation: 'update',
        payload: rowPayload(project, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }

  Stream<List<ProjectProgressEntry>> watchProgressEntries(String projectId) =>
      (_db.select(_db.projectProgressEntries)
            ..where(
              (row) => Expression.and([
                row.projectId.equals(projectId),
                row.deletedAt.isNull(),
              ]),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.recordedAt)]))
          .watch();

  Future<List<ProjectProgressEntry>> loadProgressEntries(
    String projectId,
  ) async =>
      await (_db.select(_db.projectProgressEntries)
            ..where(
              (row) => Expression.and([
                row.projectId.equals(projectId),
                row.deletedAt.isNull(),
              ]),
            )
            ..orderBy([(row) => OrderingTerm.asc(row.recordedAt)]))
          .get();

  /// 新建一条进度记录；时间戳与 sync_changes 与插入同事务。
  Future<ProjectProgressEntry> createProgressEntry({
    required String projectId,
    required double progress,
    String note = '',
    int? recordedAt,
    String? id,
  }) async {
    final now = _clock();
    final entryId = id ?? repositoryUuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.projectProgressEntries)
          .insert(
            ProjectProgressEntriesCompanion.insert(
              id: entryId,
              projectId: projectId,
              progress: progress,
              note: Value(note),
              recordedAt: recordedAt ?? now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      final created = await (_db.select(
        _db.projectProgressEntries,
      )..where((row) => row.id.equals(entryId))).getSingle();
      await recordSyncChange(
        _db,
        entityType: 'project_progress_entry',
        entityId: entryId,
        operation: 'create',
        payload: rowPayload(created),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
    return await (_db.select(
      _db.projectProgressEntries,
    )..where((row) => row.id.equals(entryId))).getSingle();
  }

  /// 用行快照更新进度记录的业务字段（note/progress）；recordedAt 与时间戳保留。
  Future<void> updateProgressEntry(ProjectProgressEntry entry) async {
    final now = _clock();
    await _db.transaction(() async {
      await (_db.update(
        _db.projectProgressEntries,
      )..where((row) => row.id.equals(entry.id))).write(
        ProjectProgressEntriesCompanion(
          progress: Value(entry.progress),
          note: Value(entry.note),
          updatedAt: Value(now),
        ),
      );
      await recordSyncChange(
        _db,
        entityType: 'project_progress_entry',
        entityId: entry.id,
        operation: 'update',
        payload: rowPayload(entry, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }

  /// 软删除单条进度记录（幂等：已删除行直接返回）。
  Future<void> softDeleteProgressEntry(String id) async {
    final now = _clock();
    await _db.transaction(() async {
      final entry =
          await (_db.select(_db.projectProgressEntries)
                ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
              .getSingleOrNull();
      if (entry == null) return;
      await (_db.update(
        _db.projectProgressEntries,
      )..where((row) => row.id.equals(id))).write(
        ProjectProgressEntriesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      await recordSyncChange(
        _db,
        entityType: 'project_progress_entry',
        entityId: id,
        operation: 'delete',
        payload: rowPayload(entry, deletedAt: now, updatedAt: now),
        deviceId: _deviceId,
        createdAt: now,
      );
    });
  }

  /// 级联软删除项目及其从属数据（幂等：已删除项目直接返回）。
  Future<void> softDelete(String id) async {
    final now = _clock();
    await _db.transaction(() async {
      final project =
          await (_db.select(_db.projects)
                ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
              .getSingleOrNull();
      if (project == null) return;

      // 项目本体。
      await _markDeletedProject(project, now);

      // 任务（项目下全部层级）及依附任务的数据。
      final tasks =
          await (_db.select(_db.tasks)..where(
                (row) => row.projectId.equals(id) & row.deletedAt.isNull(),
              ))
              .get();
      for (final task in tasks) {
        await _markDeletedTask(task, now);
      }
      final taskIds = tasks.map((row) => row.id).toList();

      // 资产（项目级或任务级）与附件记录。
      final assets =
          await (_db.select(_db.assets)..where(
                (row) =>
                    row.deletedAt.isNull() &
                    (row.projectId.equals(id) |
                        (taskIds.isNotEmpty
                            ? row.taskId.isIn(taskIds)
                            : const Constant(false))),
              ))
              .get();
      for (final asset in assets) {
        await _markDeletedAsset(asset, now);
      }

      final attachments =
          await (_db.select(_db.attachments)..where(
                (row) =>
                    row.deletedAt.isNull() &
                    (row.projectId.equals(id) |
                        (taskIds.isNotEmpty
                            ? row.taskId.isIn(taskIds)
                            : const Constant(false))),
              ))
              .get();
      for (final attachment in attachments) {
        await _markDeletedAttachment(attachment, now);
      }

      // 附件分类与进度记录（项目级）。
      final categories =
          await (_db.select(_db.attachmentCategories)..where(
                (row) => row.projectId.equals(id) & row.deletedAt.isNull(),
              ))
              .get();
      for (final category in categories) {
        await _markDeletedAttachmentCategory(category, now);
      }

      final progress =
          await (_db.select(_db.projectProgressEntries)..where(
                (row) => row.projectId.equals(id) & row.deletedAt.isNull(),
              ))
              .get();
      for (final entry in progress) {
        await _markDeletedProgressEntry(entry, now);
      }

      // 计时与番茄钟：项目级或项目任务级（历史记录一并收口避免孤儿可见）。
      final timeEntries =
          await (_db.select(_db.timeEntries)..where(
                (row) =>
                    row.deletedAt.isNull() &
                    (row.projectId.equals(id) |
                        (taskIds.isNotEmpty
                            ? row.taskId.isIn(taskIds)
                            : const Constant(false))),
              ))
              .get();
      for (final entry in timeEntries) {
        await _markDeletedTimeEntry(entry, now);
      }

      final pomodoros =
          await (_db.select(_db.pomodoroSessions)..where(
                (row) =>
                    row.deletedAt.isNull() &
                    (row.projectId.equals(id) |
                        (taskIds.isNotEmpty
                            ? row.taskId.isIn(taskIds)
                            : const Constant(false))),
              ))
              .get();
      for (final session in pomodoros) {
        await _markDeletedPomodoro(session, now);
      }

      // 依赖：涉及项目任务集合的行。
      if (taskIds.isNotEmpty) {
        final dependencies =
            await (_db.select(_db.taskDependencies)..where(
                  (row) =>
                      row.deletedAt.isNull() &
                      (row.predecessorTaskId.isIn(taskIds) |
                          row.successorTaskId.isIn(taskIds)),
                ))
                .get();
        for (final dependency in dependencies) {
          await _markDeletedDependency(dependency, now);
        }
      }
    });
  }

  Future<void> _markDeletedProject(Project row, int now) async {
    await (_db.update(_db.projects)..where((r) => r.id.equals(row.id))).write(
      ProjectsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await recordSyncChange(
      _db,
      entityType: 'project',
      entityId: row.id,
      operation: 'delete',
      payload: rowPayload(row, deletedAt: now, updatedAt: now),
      deviceId: _deviceId,
      createdAt: now,
    );
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

  Future<void> _markDeletedAsset(Asset row, int now) async {
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

  Future<void> _markDeletedAttachment(Attachment row, int now) async {
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

  Future<void> _markDeletedAttachmentCategory(
    AttachmentCategory row,
    int now,
  ) async {
    await (_db.update(
      _db.attachmentCategories,
    )..where((r) => r.id.equals(row.id))).write(
      AttachmentCategoriesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await recordSyncChange(
      _db,
      entityType: 'attachment_category',
      entityId: row.id,
      operation: 'delete',
      payload: rowPayload(row, deletedAt: now, updatedAt: now),
      deviceId: _deviceId,
      createdAt: now,
    );
  }

  Future<void> _markDeletedProgressEntry(
    ProjectProgressEntry row,
    int now,
  ) async {
    await (_db.update(
      _db.projectProgressEntries,
    )..where((r) => r.id.equals(row.id))).write(
      ProjectProgressEntriesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    await recordSyncChange(
      _db,
      entityType: 'project_progress_entry',
      entityId: row.id,
      operation: 'delete',
      payload: rowPayload(row, deletedAt: now, updatedAt: now),
      deviceId: _deviceId,
      createdAt: now,
    );
  }

  Future<void> _markDeletedTimeEntry(TimeEntry row, int now) async {
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

  Future<void> _markDeletedPomodoro(PomodoroSession row, int now) async {
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

  Future<void> _markDeletedDependency(TaskDependency row, int now) async {
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
