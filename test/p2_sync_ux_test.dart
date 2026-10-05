// P2 功能测试：实体冲突差异字段、Windows 桌面提醒服务、待办「进行中」。

import 'package:cardory/data/db/app_database.dart';
import 'package:cardory/data/repositories/drift_row_level_workspace_store.dart';
import 'package:cardory/data/runtime/sqlcipher_data_mapper.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/domain/due_reminder_service.dart';
import 'package:cardory/presentation/widgets/todo_dialog.dart';
import 'package:cardory/presentation/widgets/todo_panel.dart';
import 'package:cardory/services/windows_due_reminder_service.dart';
import 'package:cardory/sync/delta_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DeltaRecord _record(
  String changeId, {
  required String entityId,
  required Map<String, dynamic> payload,
  String deviceId = 'device-a',
}) => DeltaRecord(
  changeId: changeId,
  entityType: 'project',
  entityId: entityId,
  operation: 'update',
  payload: payload,
  deviceId: deviceId,
  createdAt: 1000,
);

Map<String, dynamic> _projectPayload({
  required String id,
  required String name,
  required int updatedAt,
  String description = '',
}) => {
  'id': id,
  'name': name,
  'description': description,
  'status': 'planned',
  'priority': 'p2',
  'sortOrder': 0,
  'pinned': false,
  'currentProgress': 0.0,
  'createdAt': 1,
  'updatedAt': updatedAt,
};

void main() {
  group('实体冲突差异字段', () {
    late AppDatabase db;
    late DeltaApplier applier;

    setUp(() {
      db = AppDatabase.inMemory();
      applier = DeltaApplier(db, localDeviceId: 'local');
    });
    tearDown(() => db.close());

    test('相同 updatedAt 不同载荷：冲突记录列出差异字段（不含 updatedAt）', () async {
      await applier.apply([
        _record(
          'c1',
          entityId: 'p1',
          payload: _projectPayload(id: 'p1', name: '初始', updatedAt: 100),
        ),
      ]);
      final result = await applier.apply([
        _record(
          'c2',
          entityId: 'p1',
          payload: _projectPayload(
            id: 'p1',
            name: '远端改名',
            description: '远端补充说明',
            updatedAt: 100,
          ),
        ),
      ]);
      final conflict = result.conflicts.single;
      expect(conflict.differingFields, contains('name'));
      expect(conflict.differingFields, contains('description'));
      expect(conflict.differingFields, isNot(contains('updatedAt')));
    });

    test('载荷与本地一致时不产生冲突', () async {
      await applier.apply([
        _record(
          'c1',
          entityId: 'p1',
          payload: _projectPayload(id: 'p1', name: '一致', updatedAt: 100),
        ),
      ]);
      final result = await applier.apply([
        _record(
          'c2',
          entityId: 'p1',
          payload: _projectPayload(id: 'p1', name: '一致', updatedAt: 100),
        ),
      ]);
      expect(result.conflicts, isEmpty);
      expect(result.skipped, 1);
    });
  });

  group('Windows 提醒服务', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('已提醒键经 shared_preferences 往返；通知能力不可用时静默降级', () async {
      SharedPreferences.setMockInitialValues({});
      final service = WindowsDueReminderService();

      expect(await service.loadNotifiedKeys(), isEmpty);
      await service.saveNotifiedKeys({'a|b|2026-10-05'});
      expect(await service.loadNotifiedKeys(), {'a|b|2026-10-05'});

      // 权限结果依赖测试宿主是否注册了 local_notifier 平台实现
      // （Windows 测试未注册 → 不可用；Linux 注册 → 可用），不在此断言，
      // 只验证通知/预约/取消链路在任何宿主下都不抛异常。
      await service.ensurePermissions();
      await service.notify(
        const DueReminderPayload(id: 1, title: 't', body: 'b'),
      );
      await service.schedule(
        ScheduledDueReminder(
          payload: const DueReminderPayload(id: 2, title: 't', body: 'b'),
          fireAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );
      await service.cancelAll();
    });
  });

  group('待办进行中状态', () {
    late AppDatabase db;
    late DriftRowLevelWorkspaceStore store;

    setUp(() {
      db = AppDatabase.inMemory();
      store = DriftRowLevelWorkspaceStore(db);
    });
    tearDown(() => db.close());

    test('切换 doing/todo，完成态忽略进行中', () async {
      await store.addTodo(
        TodoData(
          id: 't1',
          title: '任务一',
          projectId: '',
          projectTitle: '',
          priority: ProjectPriority.p2,
          done: false,
        ),
      );

      await store.setTodoInProgress('t1', inProgress: true);
      var todos = await SqlCipherDataMapper(db).loadTodos();
      expect(todos.single.inProgress, isTrue);
      expect(todos.single.done, isFalse);

      await store.setTodoInProgress('t1', inProgress: false);
      todos = await SqlCipherDataMapper(db).loadTodos();
      expect(todos.single.inProgress, isFalse);

      await store.setTodoInProgress('t1', inProgress: true);
      await store.setTodoDone('t1', done: true);
      await store.setTodoInProgress('t1', inProgress: false);
      todos = await SqlCipherDataMapper(db).loadTodos();
      // 已完成任务不受切换影响。
      expect(todos.single.done, isTrue);
      expect(todos.single.inProgress, isFalse);
    });

    testWidgets('TodoTile 展示「进行中」徽标', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodoTile(
              todo: TodoData(
                id: 't1',
                title: '任务一',
                projectId: '',
                projectTitle: '',
                priority: ProjectPriority.p2,
                done: false,
                inProgress: true,
              ),
              onToggle: (_) async {},
              onToggleSubTodo: (_, __) async {},
              onOpenTodo: (_) async {},
              onDeleteTodo: (_) async => true,
            ),
          ),
        ),
      );
      expect(find.text('进行中'), findsOneWidget);
    });

    testWidgets('编辑对话框开关「进行中」并回传', (tester) async {
      TodoData? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    saved = await showDialog<TodoData>(
                      context: context,
                      builder: (_) => TodoDialog(
                        projects: const [],
                        todo: TodoData(
                          id: 't1',
                          title: '任务一',
                          projectId: '',
                          projectTitle: '',
                          priority: ProjectPriority.p2,
                          done: false,
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('todo-in-progress')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('todo-in-progress')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved?.inProgress, isTrue);
    });
  });
}
