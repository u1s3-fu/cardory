// Repository 单事务 + sync_changes 完整 payload 契约测试。
//
// 覆盖：创建/更新载荷非空、资产敏感列不进 payload、项目/任务级联软删除、
// 标签删除摘除引用、依赖复活、计时/番茄钟结束、设置读写。
import 'dart:convert';

import 'package:cardory/data/db/app_database.dart';
import 'package:cardory/data/repositories/database_repositories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  const deviceId = 'test-device';

  setUp(() => database = AppDatabase.inMemory());
  tearDown(() => database.close());

  Future<List<SyncChange>> changes() =>
      database.select(database.syncChanges).get();

  test('project/task/asset 创建写出完整 payload 而非空对象', () async {
    final projects = ProjectRepository(database, deviceId: deviceId);
    final tasks = TaskRepository(database, deviceId: deviceId);
    final assets = AssetRepository(database, deviceId: deviceId);

    final project = await projects.create(name: 'Vault project');
    await tasks.create(title: 'Encrypt me', projectId: project.id);
    await assets.create(
      projectId: project.id,
      type: 'note',
      title: 'Secret note',
      tagIds: const ['t1'],
      sensitiveJson: '{"password":"hunter2"}',
    );

    final log = await changes();
    expect(log, hasLength(3));
    final projectPayload =
        jsonDecode(log.firstWhere((c) => c.entityType == 'project').payloadJson)
            as Map<String, dynamic>;
    expect(projectPayload['name'], 'Vault project');
    expect(projectPayload['createdAt'], isNotNull);

    final taskPayload =
        jsonDecode(log.firstWhere((c) => c.entityType == 'task').payloadJson)
            as Map<String, dynamic>;
    expect(taskPayload['title'], 'Encrypt me');

    final assetChange = log.firstWhere((c) => c.entityType == 'asset');
    final assetPayload =
        jsonDecode(assetChange.payloadJson) as Map<String, dynamic>;
    expect(assetPayload['title'], 'Secret note');
    expect(
      assetPayload.containsKey('sensitiveJson'),
      isFalse,
      reason: '资产敏感列绝不进入同步 payload',
    );
  });

  test('项目软删除级联标记任务/资产/附件且逐条记录变更', () async {
    final projects = ProjectRepository(database, deviceId: deviceId);
    final tasks = TaskRepository(database, deviceId: deviceId);
    final assets = AssetRepository(database, deviceId: deviceId);
    final attachments = AttachmentRecordRepository(
      database,
      deviceId: deviceId,
    );

    final project = await projects.create(name: 'P');
    final main = await tasks.create(title: 'Main', projectId: project.id);
    final child = await tasks.create(
      title: 'Child',
      projectId: project.id,
      parentTaskId: main.id,
    );
    await assets.create(projectId: project.id, type: 'file', title: 'A');
    await attachments.create(
      projectId: project.id,
      taskId: child.id,
      fileName: 'a.bin',
      storageKey: 'k',
      sizeBytes: 1,
      sha256: 'abc',
      kind: 'generic',
    );

    await projects.softDelete(project.id);

    final deletedTasks = await database.select(database.tasks).get();
    expect(deletedTasks.map((r) => r.deletedAt), everyElement(isNotNull));
    final deletedAssets = await database.select(database.assets).get();
    expect(deletedAssets.single.deletedAt, isNotNull);
    final deletedAttachments = await database
        .select(database.attachments)
        .get();
    expect(deletedAttachments.single.deletedAt, isNotNull);

    final log = await changes();
    // 项目 + 2 任务 + 资产 + 附件 = 5 条 delete 变更。
    expect(log.where((c) => c.operation == 'delete'), hasLength(5));
    // 重复删除幂等，不产生额外记录。
    final before = log.length;
    await projects.softDelete(project.id);
    expect(await changes(), hasLength(before));
  });

  test('任务软删除级联其直接子任务；跨项目子任务被拒绝', () async {
    final projects = ProjectRepository(database, deviceId: deviceId);
    final tasks = TaskRepository(database, deviceId: deviceId);

    final project = await projects.create(name: 'P');
    final other = await projects.create(name: 'Other');
    final main = await tasks.create(title: 'Main', projectId: project.id);
    final child = await tasks.create(
      title: 'Child',
      projectId: project.id,
      parentTaskId: main.id,
    );

    await expectLater(
      tasks.create(title: 'Bad', projectId: other.id, parentTaskId: main.id),
      throwsStateError,
    );

    await tasks.softDelete(main.id);
    final rows = await database.select(database.tasks).get();
    expect(rows.where((r) => r.id == main.id).single.deletedAt, isNotNull);
    expect(rows.where((r) => r.id == child.id).single.deletedAt, isNotNull);
  });

  test('标签删除会从资产 tagsJson 摘除并记录资产更新', () async {
    final assets = AssetRepository(database, deviceId: deviceId);
    final tags = AssetTagRepository(database, deviceId: deviceId);

    final tag = await tags.create(name: 'red');
    final asset = await assets.create(
      type: 'note',
      title: 'Tagged',
      tagIds: [tag.id],
    );
    expect(jsonDecode(asset.tagsJson), [tag.id]);

    await tags.softDelete(tag.id);

    final stored = await database.select(database.assets).getSingle();
    expect(stored.tagsJson, '[]');
    final log = await changes();
    expect(
      log.where((c) => c.entityType == 'asset' && c.operation == 'update'),
      isNotEmpty,
    );
  });

  test('依赖软删后同组合重建会复活旧行而非冲突', () async {
    final projects = ProjectRepository(database, deviceId: deviceId);
    final tasks = TaskRepository(database, deviceId: deviceId);
    final dependencies = TaskDependencyRepository(database, deviceId: deviceId);

    final project = await projects.create(name: 'P');
    final a = await tasks.create(title: 'A', projectId: project.id);
    final b = await tasks.create(title: 'B', projectId: project.id);

    final dep = await dependencies.create(
      predecessorTaskId: a.id,
      successorTaskId: b.id,
    );
    await expectLater(
      dependencies.create(predecessorTaskId: a.id, successorTaskId: b.id),
      throwsStateError,
    );
    await dependencies.softDelete(dep.id);
    final revived = await dependencies.create(
      predecessorTaskId: a.id,
      successorTaskId: b.id,
    );
    expect(revived.id, dep.id);
    expect(revived.deletedAt, isNull);
  });

  test('计时结束写入时长；番茄钟完成写入状态', () async {
    final time = TimeEntryRepository(database, deviceId: deviceId);
    final pomodoro = PomodoroSessionRepository(database, deviceId: deviceId);

    final entry = await time.start(startedAt: 10000);
    await time.stop(entry.id, endedAt: 45000);
    final storedEntry = await database.select(database.timeEntries).getSingle();
    expect(storedEntry.durationSeconds, 35);
    expect(storedEntry.endedAt, 45000);

    final session = await pomodoro.start(
      mode: 'focus',
      plannedSeconds: 1500,
      startedAt: 10000,
    );
    await pomodoro.finish(
      session.id,
      completed: true,
      actualSeconds: 1498,
      endedAt: 45498,
    );
    final storedSession = await database
        .select(database.pomodoroSessions)
        .getSingle();
    expect(storedSession.completed, isTrue);
    expect(storedSession.actualSeconds, 1498);
  });

  test('设置键值批量写入并读取', () async {
    final settings = SettingsRepository(database);
    await settings.writeMany({'theme': 'dark', 'sync.interval.seconds': '300'});
    expect(await settings.read('theme'), 'dark');
    expect((await settings.readAll())['sync.interval.seconds'], '300');
    expect(await database.select(database.settings).get(), hasLength(2));
  });
}
