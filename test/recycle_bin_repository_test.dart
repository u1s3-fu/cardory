// RecycleBinRepository 的数据库级测试：软删除条目列表、恢复语义
// （deletedAt 清除 + sync_changes 完整载荷）与宿主守卫。

import 'dart:convert';

import 'package:cardory/data/db/app_database.dart'
    hide ProjectProgressEntry, AttachmentCategory, AssetTag;
import 'package:cardory/data/repositories/drift_row_level_workspace_store.dart';
import 'package:cardory/data/repositories/recycle_bin_repository.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/domain/milestone_models.dart';
import 'package:cardory/domain/recycle_bin_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftRowLevelWorkspaceStore store;
  late RecycleBinRepository recycleBin;

  setUp(() {
    database = AppDatabase.inMemory();
    store = DriftRowLevelWorkspaceStore(database);
    recycleBin = RecycleBinRepository(database);
  });
  tearDown(() => database.close());

  Future<ProjectData> createProject(String id, String title) async {
    final project = ProjectData(
      id: id,
      title: title,
      description: '说明-$title',
      priority: ProjectPriority.p1,
      stage: ProjectStage.planned,
      progressEntries: const [],
    );
    await store.addProject(project);
    return project;
  }

  Future<TodoData> createTodo(String id, String title, String projectId) async {
    final todo = TodoData(
      id: id,
      title: title,
      projectId: projectId,
      projectTitle: title,
      priority: ProjectPriority.p2,
      done: false,
    );
    await store.addTodo(todo);
    return todo;
  }

  Future<void> createAsset(String id, String name, String projectId) {
    return store.addAsset(
      AssetData(
        id: id,
        type: AssetType.software,
        name: name,
        projectId: projectId,
        username: 'admin',
        password: 'secret-password',
      ),
    );
  }

  test('loadEntries 列出四类软删除条目并按删除时间倒序', () async {
    await createProject('p1', '项目一');
    await createTodo('t1', '待办一', 'p1');
    await createAsset('a1', '资产一', 'p1');
    await store.addMilestone(
      MilestoneData(
        id: 'm1',
        projectId: 'p1',
        title: '里程碑一',
        dueAt: DateTime(2026, 10, 1),
      ),
    );

    await store.deleteTodo('t1');
    // 留出毫秒差，保证删除时间戳可比较排序。
    await Future<void>.delayed(const Duration(milliseconds: 15));
    await store.deleteProject('p1');

    final entries = await recycleBin.loadEntries();
    expect(
      entries.map((entry) => entry.id),
      containsAll(['p1', 't1', 'a1', 'm1']),
    );
    // 排序：后删的 p1 在先删的 t1 之前。
    expect(entries.first.id, 'p1');
    expect(
      entries.firstWhere((entry) => entry.id == 'p1').type,
      RecycleBinEntityType.project,
    );
    expect(
      entries.firstWhere((entry) => entry.id == 'a1').type,
      RecycleBinEntityType.asset,
    );
    expect(
      entries.firstWhere((entry) => entry.id == 'm1').type,
      RecycleBinEntityType.milestone,
    );
  });

  test('子待办在列表中标记「子待办」', () async {
    await createProject('p1', '项目一');
    final todo = await createTodo('t1', '待办一', 'p1');
    await store.addSubTodo(
      todo,
      SubTodoData(id: 's1', content: '子任务一', done: false),
    );
    // addSubTodo 落库时生成新的任务 id（domain id 不透传），按标题定位。
    final rows = await (database.select(
      database.tasks,
    )..where((row) => row.title.equals('子任务一'))).get();
    expect(rows, hasLength(1));
    await store.deleteTodo(rows.single.id);

    final entries = await recycleBin.loadEntries();
    final sub = entries.firstWhere((entry) => entry.id == rows.single.id);
    expect(sub.type, RecycleBinEntityType.task);
    expect(sub.subtitle, contains('子待办'));
  });

  test('恢复待办：清除 deletedAt 并写入 deletedAt 为 null 的 update 记录', () async {
    await createProject('p1', '项目一');
    await createTodo('t1', '待办一', 'p1');
    await store.deleteTodo('t1');

    await recycleBin.restore(RecycleBinEntityType.task, 't1');

    final row = await (database.select(
      database.tasks,
    )..where((row) => row.id.equals('t1'))).getSingle();
    expect(row.deletedAt, isNull);

    final change = await (database.select(
      database.syncChanges,
    )..where((row) => row.entityId.equals('t1'))).get();
    final restore = change.last;
    expect(restore.operation, 'update');
    final payload = jsonDecode(restore.payloadJson) as Map<String, dynamic>;
    expect(payload['deletedAt'], isNull);
    expect(payload['title'], '待办一');
  });

  test('恢复资产：sync 载荷剔除敏感列，行内敏感列保留', () async {
    await createProject('p1', '项目一');
    await createAsset('a1', '资产一', 'p1');
    await store.deleteAsset('a1');

    await recycleBin.restore(RecycleBinEntityType.asset, 'a1');

    final row = await (database.select(
      database.assets,
    )..where((row) => row.id.equals('a1'))).getSingle();
    expect(row.deletedAt, isNull);
    expect(row.sensitiveJson, contains('secret-password'));

    final change = await (database.select(
      database.syncChanges,
    )..where((row) => row.entityId.equals('a1'))).get();
    final payload = jsonDecode(change.last.payloadJson) as Map<String, dynamic>;
    expect(payload.containsKey('sensitiveJson'), isFalse);
  });

  test('项目删除级联后：先恢复里程碑被拒，恢复项目后可恢复里程碑', () async {
    await createProject('p1', '项目一');
    await store.addMilestone(
      MilestoneData(
        id: 'm1',
        projectId: 'p1',
        title: '里程碑一',
        dueAt: DateTime(2026, 10, 1),
      ),
    );
    await store.deleteProject('p1');

    expect(
      () => recycleBin.restore(RecycleBinEntityType.milestone, 'm1'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('所属项目尚未恢复'),
        ),
      ),
    );

    await recycleBin.restore(RecycleBinEntityType.project, 'p1');
    await recycleBin.restore(RecycleBinEntityType.milestone, 'm1');

    final row = await (database.select(
      database.milestones,
    )..where((row) => row.id.equals('m1'))).getSingle();
    expect(row.deletedAt, isNull);
  });

  test('重复恢复幂等：不追加 sync_changes', () async {
    await createProject('p1', '项目一');
    await createTodo('t1', '待办一', 'p1');
    await store.deleteTodo('t1');
    await recycleBin.restore(RecycleBinEntityType.task, 't1');

    final before = await database.select(database.syncChanges).get();
    await recycleBin.restore(RecycleBinEntityType.task, 't1');
    final after = await database.select(database.syncChanges).get();

    expect(after.length, before.length);
  });

  test('恢复不存在的条目抛错', () async {
    expect(
      () => recycleBin.restore(RecycleBinEntityType.task, 'missing'),
      throwsA(isA<StateError>()),
    );
  });

  test('恢复后条目不再出现在回收站列表', () async {
    await createProject('p1', '项目一');
    await createTodo('t1', '待办一', 'p1');
    // 项目删除会级联软删除其待办；单独恢复待办后项目仍在回收站。
    await store.deleteProject('p1');
    await recycleBin.restore(RecycleBinEntityType.task, 't1');

    final entries = await recycleBin.loadEntries();
    expect(entries.where((entry) => entry.id == 't1'), isEmpty);
    expect(entries.where((entry) => entry.id == 'p1'), isNotEmpty);
  });
}
