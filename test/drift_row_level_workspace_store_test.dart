// DriftRowLevelWorkspaceStore 的数据库级测试：验证行级写入语义
// （投影回读、差异对齐、tombstone、sync_changes）。

import 'package:cardory/data/db/app_database.dart'
    hide ProjectProgressEntry, AttachmentCategory, AssetTag;
import 'package:cardory/data/repositories/drift_row_level_workspace_store.dart';
import 'package:cardory/data/runtime/sqlcipher_data_mapper.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftRowLevelWorkspaceStore store;

  setUp(() {
    database = AppDatabase.inMemory();
    store = DriftRowLevelWorkspaceStore(database);
  });
  tearDown(() => database.close());

  ProjectData project({
    required String id,
    required String title,
    ProjectStage stage = ProjectStage.planned,
    List<ProjectProgressEntry> progressEntries = const [],
  }) => ProjectData(
    id: id,
    title: title,
    description: '说明-$title',
    priority: ProjectPriority.p1,
    stage: stage,
    progressEntries: progressEntries,
  );

  test('addProject 写入项目行、进度、附件与分类，并可从投影回读', () async {
    final entry = ProjectProgressEntry(
      id: 'entry-1',
      note: '启动',
      progress: 0.25,
      createdAt: DateTime.utc(2026, 9, 1),
    );
    final attachment = AttachmentData(
      id: 'attachment-1',
      fileName: 'spec.pdf',
      storageKey: 'attachment-1.cardory-attachment',
      size: 10,
      sha256: 'hash',
      createdAt: DateTime.utc(2026, 9, 1),
    );
    await store.addProject(
      project(id: 'project-1', title: '项目一', progressEntries: [entry]).copyWith(
        attachments: [attachment],
        categories: const [AttachmentCategory(id: 'category-1', name: '文档')],
      ),
    );

    final mapper = SqlCipherDataMapper(database);
    final loaded = await mapper.loadProjects();
    expect(loaded, hasLength(1));
    expect(loaded.single.title, '项目一');
    expect(loaded.single.stage, ProjectStage.planned);
    expect(loaded.single.progressEntries.single.note, '启动');
    expect(loaded.single.attachments.single.fileName, 'spec.pdf');
    expect(loaded.single.categories.single.name, '文档');

    final changes = await database.select(database.syncChanges).get();
    final entities = changes.map((change) => change.entityType).toSet();
    expect(
      entities,
      containsAll(['project', 'project_progress_entry', 'attachment']),
    );
  });

  test('updateProject 按差异对齐进度/附件/分类，行级更新记录 sync_changes', () async {
    final original =
        project(
          id: 'project-1',
          title: '原名',
          progressEntries: [
            ProjectProgressEntry(
              id: 'entry-keep',
              note: '保留',
              progress: 0.1,
              createdAt: DateTime.utc(2026, 9, 1),
            ),
            ProjectProgressEntry(
              id: 'entry-remove',
              note: '删除',
              progress: 0.2,
              createdAt: DateTime.utc(2026, 9, 2),
            ),
          ],
        ).copyWith(
          attachments: [
            AttachmentData(
              id: 'attachment-keep',
              fileName: 'keep.txt',
              storageKey: 'attachment-keep.cardory-attachment',
              size: 1,
              sha256: 'hash',
              createdAt: DateTime.utc(2026, 9, 1),
            ),
            AttachmentData(
              id: 'attachment-remove',
              fileName: 'remove.txt',
              storageKey: 'attachment-remove.cardory-attachment',
              size: 1,
              sha256: 'hash',
              createdAt: DateTime.utc(2026, 9, 1),
            ),
          ],
          categories: const [
            AttachmentCategory(id: 'category-keep', name: '保留'),
            AttachmentCategory(id: 'category-remove', name: '删除'),
          ],
        );
    await store.addProject(original);

    final updated = original.copyWith(
      title: '新名',
      stage: ProjectStage.doing,
      progressEntries: [
        ProjectProgressEntry(
          id: 'entry-keep',
          note: '更新说明',
          progress: 0.5,
          createdAt: DateTime.utc(2026, 9, 1),
        ),
        ProjectProgressEntry(
          id: 'entry-add',
          note: '新增',
          progress: 0.9,
          createdAt: DateTime.utc(2026, 9, 3),
        ),
      ],
      attachments: [
        original.attachments.first.copyWith(note: '备注更新'),
        AttachmentData(
          id: 'attachment-add',
          fileName: 'add.txt',
          storageKey: 'attachment-add.cardory-attachment',
          size: 2,
          sha256: 'hash2',
          createdAt: DateTime.utc(2026, 9, 3),
        ),
      ],
      categories: const [
        AttachmentCategory(id: 'category-keep', name: '改名'),
        AttachmentCategory(id: 'category-add', name: '新增'),
      ],
    );
    await store.updateProject(original, updated);

    final loaded = await SqlCipherDataMapper(database).loadProjects();
    expect(loaded.single.title, '新名');
    expect(loaded.single.stage, ProjectStage.doing);
    expect(loaded.single.progressEntries.map((entry) => entry.id), [
      'entry-keep',
      'entry-add',
    ]);
    expect(loaded.single.progressEntries.first.note, '更新说明');
    expect(loaded.single.attachments.map((attachment) => attachment.id), [
      'attachment-keep',
      'attachment-add',
    ]);
    expect(loaded.single.attachments.first.note, '备注更新');
    expect(loaded.single.categories.map((category) => category.name), [
      '改名',
      '新增',
    ]);

    final removedRows = await (database.select(
      database.attachments,
    )..where((row) => row.id.equals('attachment-remove'))).getSingle();
    expect(removedRows.deletedAt, isNotNull);
  });

  test('deleteProject 级联软删除，投影不再包含该项目', () async {
    final original = project(id: 'project-1', title: '项目');
    await store.addProject(original);
    await store.addTodo(
      TodoData(
        id: 'todo-1',
        title: '待办',
        projectId: 'project-1',
        projectTitle: '项目',
        priority: ProjectPriority.p2,
        done: false,
      ),
    );

    await store.deleteProject('project-1');

    final mapper = SqlCipherDataMapper(database);
    expect(await mapper.loadProjects(), isEmpty);
    expect(await mapper.loadTodos(), isEmpty);
    final taskRow = await (database.select(
      database.tasks,
    )..where((row) => row.id.equals('todo-1'))).getSingle();
    expect(taskRow.deletedAt, isNotNull);
  });

  test('待办与子待办：新增、编辑差异对齐、完成切换与级联删除', () async {
    final original = TodoData(
      id: 'todo-1',
      title: '待办',
      projectId: '',
      projectTitle: '未关联项目',
      priority: ProjectPriority.p2,
      done: false,
      subTodos: [
        const SubTodoData(id: 'sub-keep', content: '保留', done: false),
        const SubTodoData(id: 'sub-remove', content: '删除', done: false),
      ],
    );
    await store.addTodo(original);

    final updated = original.copyWith(
      title: '待办-改',
      done: true,
      subTodos: [
        original.subTodos.first.copyWith(content: '保留-改', done: true),
        const SubTodoData(id: 'sub-add', content: '新增', done: false),
      ],
    );
    await store.updateTodo(original, updated);

    final loaded = await SqlCipherDataMapper(database).loadTodos();
    expect(loaded.single.title, '待办-改');
    expect(loaded.single.done, isTrue);
    expect(loaded.single.subTodos.map((subTodo) => subTodo.id), [
      'sub-keep',
      'sub-add',
    ]);
    expect(loaded.single.subTodos.first.content, '保留-改');
    expect(loaded.single.subTodos.first.done, isTrue);

    // 取消完成：status 回 todo 且 completedAt 清空。
    await store.setTodoDone('todo-1', done: false);
    final row = await (database.select(
      database.tasks,
    )..where((row) => row.id.equals('todo-1'))).getSingle();
    expect(row.status, 'todo');
    expect(row.completedAt, isNull);

    // 子待办完成切换。
    await store.setSubTodoDone('sub-add', done: true);
    final subRow = await (database.select(
      database.tasks,
    )..where((row) => row.id.equals('sub-add'))).getSingle();
    expect(subRow.status, 'done');

    // 删除父待办级联软删除子待办。
    await store.deleteTodo('todo-1');
    final visible = await SqlCipherDataMapper(database).loadTodos();
    expect(visible, isEmpty);
    final subAfterDelete = await (database.select(
      database.tasks,
    )..where((row) => row.id.equals('sub-add'))).getSingle();
    expect(subAfterDelete.deletedAt, isNotNull);
  });

  test('reorderProjects 写入阶段与 sortOrder，未变化行不产生 sync_changes', () async {
    await store.addProject(project(id: 'a', title: 'A'));
    await store.addProject(project(id: 'b', title: 'B'));
    await store.addProject(
      project(id: 'c', title: 'C', stage: ProjectStage.doing),
    );

    final changesBefore = await database.select(database.syncChanges).get();
    // 把 C 拖到首位并改回 planned；A、B 相对顺序不变但 sortOrder 后移。
    final loaded = await SqlCipherDataMapper(database).loadProjects();
    final byId = {for (final item in loaded) item.id: item};
    await store.reorderProjects([
      byId['c']!.copyWith(stage: ProjectStage.planned),
      byId['a']!,
      byId['b']!,
    ]);

    final after = await SqlCipherDataMapper(database).loadProjects();
    expect(after.map((item) => item.id).toList(), ['c', 'a', 'b']);
    expect(after.first.stage, ProjectStage.planned);

    final changesAfter = await database.select(database.syncChanges).get();
    final reorderChanges = changesAfter.skip(changesBefore.length);
    // C：阶段+顺序变化；A、B：sortOrder 后移各一条；共 3 条 update。
    expect(reorderChanges.length, 3);
    expect(
      reorderChanges.every((change) => change.operation == 'update'),
      isTrue,
    );
  });

  test('资产与标签：创建、更新、删除与标签清理', () async {
    final asset = AssetData(
      id: 'asset-1',
      type: AssetType.software,
      name: '服务',
      projectId: '',
      username: 'admin',
      password: 'secret',
      tagIds: const [],
    );
    await store.addAsset(asset);

    final loaded = await SqlCipherDataMapper(database).loadAssets();
    expect(loaded.single.name, '服务');
    expect(loaded.single.username, 'admin');

    final updated = loaded.single.copyWith(name: '服务-改', port: '8080');
    await store.editAsset(asset, updated);
    final reloaded = await SqlCipherDataMapper(database).loadAssets();
    expect(reloaded.single.name, '服务-改');
    expect(reloaded.single.port, '8080');

    await store.addAssetTag(const AssetTag(id: 'tag-1', name: '生产'));
    await store.updateAssetsTags({'asset-1'}, {'tag-1'});
    final withTag = await SqlCipherDataMapper(database).loadAssets();
    expect(withTag.single.tagIds, ['tag-1']);

    // 删除标签会把标签从资产 tagsJson 中摘除。
    await store.deleteAssetTag('tag-1');
    final withoutTag = await SqlCipherDataMapper(database).loadAssets();
    expect(withoutTag.single.tagIds, isEmpty);

    await store.deleteAsset('asset-1');
    expect(await SqlCipherDataMapper(database).loadAssets(), isEmpty);
  });
}
