import 'package:cardory/data/db/app_database.dart';
import 'package:cardory/data/repositories/database_repositories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase.inMemory());
  tearDown(() => database.close());

  test('creates schema and records project writes as sync changes', () async {
    var now = 1000;
    final projects = ProjectRepository(
      database,
      clock: () => ++now,
      deviceId: 'test-device',
    );

    final project = await projects.create(name: 'Encrypted project');

    expect(project.name, 'Encrypted project');
    expect(project.deletedAt, isNull);
    final changes = await database.select(database.syncChanges).get();
    expect(changes, hasLength(1));
    expect(changes.single.entityId, project.id);
    expect(changes.single.operation, 'create');
  });

  test('soft deletion preserves row and records a deletion change', () async {
    final projects = ProjectRepository(database, deviceId: 'test-device');
    final project = await projects.create(name: 'To delete');

    await projects.softDelete(project.id);

    final stored = await (database.select(
      database.projects,
    )..where((row) => row.id.equals(project.id))).getSingle();
    expect(stored.deletedAt, isNotNull);
    final visible = await projects.watchProjects().first;
    expect(visible, isEmpty);
    final changes = await database.select(database.syncChanges).get();
    expect(changes.map((change) => change.operation), ['create', 'delete']);
  });

  test('limits tasks to a main task and one child level', () async {
    final projects = ProjectRepository(database, deviceId: 'test-device');
    final tasks = TaskRepository(database, deviceId: 'test-device');
    final project = await projects.create(name: 'Project');
    final main = await tasks.create(title: 'Main', projectId: project.id);
    final child = await tasks.create(
      title: 'Child',
      projectId: project.id,
      parentTaskId: main.id,
    );

    await expectLater(
      tasks.create(
        title: 'Grandchild',
        projectId: project.id,
        parentTaskId: child.id,
      ),
      throwsStateError,
    );
  });

  test(
    'marks a task complete and emits a change in the same write flow',
    () async {
      final projects = ProjectRepository(database, deviceId: 'test-device');
      final tasks = TaskRepository(database, deviceId: 'test-device');
      final project = await projects.create(name: 'Project');
      final task = await tasks.create(title: 'Task', projectId: project.id);

      await tasks.complete(task.id);

      final completed = await (database.select(
        database.tasks,
      )..where((row) => row.id.equals(task.id))).getSingle();
      expect(completed.status, 'done');
      expect(completed.completedAt, isNotNull);
    },
  );
}
