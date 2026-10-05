// P1 功能测试：任务截止提醒（复用到期提醒管道）、被阻塞集合、
// 任务完成率自动进度与全局搜索对话框。

import 'package:cardory/application/workspace_controller.dart';
import 'package:cardory/application/workspace_settings_service.dart';
import 'package:cardory/domain/attachment_repository.dart'
    show AttachmentRepository;
import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/domain/cardory_repository.dart';
import 'package:cardory/domain/dependency_schedule.dart';
import 'package:cardory/domain/due_reminder_service.dart';
import 'package:cardory/domain/milestone_models.dart';
import 'package:cardory/domain/schedule_queries.dart';
import 'package:cardory/domain/sync_credentials.dart';
import 'package:cardory/presentation/widgets/global_search_dialog.dart';
import 'package:cardory/presentation/widgets/todo_panel.dart';
import 'package:cardory/sync/sync_coordinator.dart';
import 'package:cardory/sync/sync_models.dart';
import 'support/in_memory_row_level_workspace_store.dart' as support;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------- 纯函数：被阻塞集合 ----------

void main() {
  group('computeBlockedTodoIds', () {
    final a = _todo('a', done: false);
    final b = _todo('b', done: false);
    final c = _todo('c', done: true);

    test('未完成前置阻塞后继；已完成前置与已删除前置不阻塞', () {
      final blocked = computeBlockedTodoIds(
        [a, b, c],
        [
          _dep(predecessor: 'a', successor: 'b'),
          _dep(predecessor: 'c', successor: 'a'),
        ],
      );
      // a 未完成 → b 被阻塞；c 已完成 → a 不被阻塞。
      expect(blocked, {'b'});
    });

    test('前置不在可见列表（已删除）时不阻塞', () {
      final blocked = computeBlockedTodoIds(
        [a],
        [_dep(predecessor: 'ghost', successor: 'a')],
      );
      expect(blocked, isEmpty);
    });
  });

  group('taskDueEntries', () {
    test('只取未完成且有截止日的任务，bounds 过滤生效', () {
      final today = localDayKey(DateTime.now());
      final entries = taskDueEntries(
        [
          _todo('t1', done: false, endDate: today),
          _todo('t2', done: true, endDate: today),
          _todo('t3', done: false),
          _todo('t4', done: false, endDate: today.add(const Duration(days: 9))),
        ],
        bounds: (today, today),
      );
      expect(entries.map((entry) => entry.assetId), ['t1']);
      expect(entries.single.title, '任务截止 · 待办-t1');
      expect(entries.single.fieldKey, 'task-due');
    });
  });

  group('任务截止系统通知', () {
    late _MemoryRepository repository;
    late support.InMemoryRowLevelWorkspaceStore rowLevelStore;
    late _RecordingReminderService reminders;
    late WorkspaceController controller;

    TodoData todo(String id, {bool done = false, DateTime? endDate}) =>
        TodoData(
          id: id,
          title: '截止任务-$id',
          projectId: 'p1',
          projectTitle: '项目一',
          priority: ProjectPriority.p1,
          done: done,
          endDate: endDate,
        );

    setUp(() {
      final today = localDayKey(DateTime.now());
      repository = _MemoryRepository(
        CardoryData(
          projects: [
            ProjectData(
              id: 'p1',
              title: '项目一',
              description: '',
              priority: ProjectPriority.p1,
              stage: ProjectStage.doing,
              progressEntries: const [],
            ),
          ],
          todos: [
            todo('t1', endDate: today),
            todo('t2', endDate: today.add(const Duration(days: 3))),
          ],
        ),
      );
      rowLevelStore = support.InMemoryRowLevelWorkspaceStore(
        () => repository.data,
        (data) => repository.data = data,
      );
      reminders = _RecordingReminderService();
      controller = WorkspaceController(
        repository: repository,
        vaultRepository: repository,
        settingsService: WorkspaceSettingsService(
          repository: repository,
          credentialStore: _MemoryCredentialStore(),
        ),
        syncService: SyncCoordinator(
          repository: repository,
          providerFactory: (_) async =>
              throw const SyncUnavailableException('not used'),
          attachmentRepositoryFactory: (_) => _NoopAttachments(),
        ),
        attachmentRepositoryFactory: (_) => _NoopAttachments(),
        rowLevelStore: rowLevelStore,
        dueReminderService: reminders,
      );
    });

    tearDown(() => controller.dispose());

    test('今日截止立即提醒、未来截止按日预约，标题为「任务截止 · 标题」', () async {
      await controller.initialize(await repository.load());
      expect(
        reminders.notified.map((payload) => payload.title),
        contains('任务截止 · 截止任务-t1'),
      );
      expect(
        reminders.scheduled.map((reminder) => reminder.payload.title),
        contains('任务截止 · 截止任务-t2'),
      );
    });

    test('关闭任务截止通知开关后不再提醒任务', () async {
      repository.settings = repository.settings.copyWith(
        taskDueRemindersEnabled: false,
      );
      await controller.initialize(await repository.load());
      expect(
        reminders.notified.map((payload) => payload.title),
        isNot(contains('任务截止 · 截止任务-t1')),
      );
    });
  });

  group('任务完成率自动记录项目进度', () {
    late _MemoryRepository repository;
    late support.InMemoryRowLevelWorkspaceStore rowLevelStore;
    late WorkspaceController controller;

    setUp(() {
      repository = _MemoryRepository(
        CardoryData(
          projects: [
            ProjectData(
              id: 'p1',
              title: '项目一',
              description: '',
              priority: ProjectPriority.p1,
              stage: ProjectStage.doing,
              progressEntries: const [],
            ),
          ],
          todos: [
            _todo('a', done: true, projectId: 'p1'),
            _todo('b', done: false, projectId: 'p1'),
          ],
        ),
      );
      repository.settings = repository.settings.copyWith(
        autoProgressFromTasks: true,
      );
      rowLevelStore = support.InMemoryRowLevelWorkspaceStore(
        () => repository.data,
        (data) => repository.data = data,
      );
      controller = WorkspaceController(
        repository: repository,
        vaultRepository: repository,
        settingsService: WorkspaceSettingsService(
          repository: repository,
          credentialStore: _MemoryCredentialStore(),
        ),
        syncService: SyncCoordinator(
          repository: repository,
          providerFactory: (_) async =>
              throw const SyncUnavailableException('not used'),
          attachmentRepositoryFactory: (_) => _NoopAttachments(),
        ),
        attachmentRepositoryFactory: (_) => _NoopAttachments(),
        rowLevelStore: rowLevelStore,
      );
    });

    tearDown(() => controller.dispose());

    test('勾选任务后按完成率追加自动进度记录', () async {
      await controller.initialize(await repository.load());
      final b = controller.data.todos.firstWhere((todo) => todo.id == 'b');
      await controller.toggleTodo(b);

      final entries = controller.data.projects.single.progressEntries;
      expect(entries, hasLength(1));
      expect(entries.single.progress, closeTo(1.0, 0.0001));
      expect(entries.single.note, '按任务完成率自动记录');
    });

    test('最近记录与完成率相同则不重复追加', () async {
      final seeded = repository.data.projects.single.copyWith(
        progressEntries: [
          ProjectProgressEntry(
            id: 'seed',
            note: 'seed',
            progress: 1.0,
            createdAt: DateTime(2026),
          ),
        ],
      );
      repository.data = CardoryData(
        projects: [seeded],
        todos: repository.data.todos,
      );
      await controller.initialize(await repository.load());
      final b = controller.data.todos.firstWhere((todo) => todo.id == 'b');
      await controller.toggleTodo(b);

      expect(controller.data.projects.single.progressEntries, hasLength(1));
    });

    test('设置关闭时不追加自动进度记录', () async {
      repository.settings = repository.settings.copyWith(
        autoProgressFromTasks: false,
      );
      await controller.initialize(await repository.load());
      final b = controller.data.todos.firstWhere((todo) => todo.id == 'b');
      await controller.toggleTodo(b);
      expect(controller.data.projects.single.progressEntries, isEmpty);
    });
  });

  group('全局搜索对话框', () {
    final project = ProjectData(
      id: 'p1',
      title: '搜索引擎重构',
      description: '描述',
      priority: ProjectPriority.p1,
      stage: ProjectStage.doing,
      progressEntries: const [],
    );
    final todo = TodoData(
      id: 't1',
      title: '搜索框接入',
      projectId: 'p1',
      projectTitle: '项目一',
      priority: ProjectPriority.p2,
      done: false,
    );

    Future<_SearchHarness> pumpDialog(WidgetTester tester, String query) async {
      final harness = _SearchHarness();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => GlobalSearchDialog.show(
                    context,
                    GlobalSearchDialog(
                      projects: [project],
                      todos: [todo],
                      assets: const [],
                      loadMilestones: () async => [
                        MilestoneData(
                          id: 'm1',
                          projectId: 'p1',
                          title: '搜索里程碑',
                          dueAt: DateTime(2026, 10, 10),
                        ),
                      ],
                      onOpenProject: (_) => harness.projectOpened = true,
                      onOpenTodo: (value) async => harness.openedTodo = value,
                      onOpenAsset: (_) async => null,
                      onOpenGantt: () {},
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('global-search-field')),
        query,
      );
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('按标题过滤并按类型分发跳转', (tester) async {
      final harness = await pumpDialog(tester, '搜索');
      // 三条命中：项目/待办/里程碑。
      expect(find.text('搜索引擎重构'), findsOneWidget);
      expect(find.text('搜索框接入'), findsOneWidget);
      expect(find.text('搜索里程碑'), findsOneWidget);

      await tester.tap(find.text('搜索框接入'));
      await tester.pumpAndSettle();
      expect(harness.openedTodo?.id, 't1');
      expect(find.byType(GlobalSearchDialog), findsNothing);

      final negative = await pumpDialog(tester, '不存在的词');
      expect(find.text('没有匹配的结果'), findsOneWidget);
      expect(negative.projectOpened, isFalse);
    });

    testWidgets('跳转项目后关闭对话框', (tester) async {
      final harness = await pumpDialog(tester, '引擎');
      await tester.tap(find.text('搜索引擎重构'));
      await tester.pumpAndSettle();
      expect(harness.projectOpened, isTrue);
      expect(find.byType(GlobalSearchDialog), findsNothing);
    });
  });

  group('待办被阻塞徽标', () {
    testWidgets('TodoTile 展示「被阻塞」标识', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TodoTile(
              todo: _todo('a', done: false),
              onToggle: (_) async {},
              onToggleSubTodo: (_, __) async {},
              onOpenTodo: (_) async {},
              onDeleteTodo: (_) async => true,
              blocked: true,
            ),
          ),
        ),
      );
      expect(find.text('被阻塞'), findsOneWidget);
    });
  });
}

TodoData _todo(
  String id, {
  bool done = false,
  DateTime? endDate,
  String projectId = 'p1',
}) => TodoData(
  id: id,
  title: '待办-$id',
  projectId: projectId,
  projectTitle: '项目一',
  priority: ProjectPriority.p2,
  done: done,
  endDate: endDate,
);

TaskDependencyData _dep({
  required String predecessor,
  required String successor,
}) => TaskDependencyData(
  id: '$predecessor->$successor',
  predecessorTaskId: predecessor,
  successorTaskId: successor,
);

class _MemoryRepository implements CardoryRepository {
  _MemoryRepository(this.data);

  CardoryData data;
  AppSettings settings = const AppSettings();

  @override
  Future<CardoryLoadResult> load() async => CardoryLoadResult(
    data: data,
    settings: settings,
    path: 'memory/cardory.db',
  );

  @override
  Future<void> save(CardoryData data, AppSettings settings) async {
    this.data = data;
    this.settings = settings;
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    this.settings = settings;
  }

  @override
  Future<CardoryAccessState> accessState() async => CardoryAccessState.unlocked;

  @override
  Future<CardoryLoadResult> setup(String password) => load();

  @override
  Future<CardoryLoadResult> unlockWithPassword(String password) => load();

  @override
  Future<CardoryLoadResult> restoreFromBackup(
    List<int> bytes,
    String password,
  ) => load();

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {}

  @override
  Future<List<int>> exportContainer() async => const [1];

  @override
  Future<CardoryData> importContainer(
    List<int> bytes,
    AppSettings settings,
  ) async => data;

  @override
  Future<String> saveSyncConflictSnapshot(
    List<int> bytes, {
    DateTime? timestamp,
  }) async => 'snapshot';
}

/// 空操作附件仓库：applyLoadResult 会无条件构建附件仓库，测试用空实现。
class _NoopAttachments implements AttachmentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) async => null;
}

class _MemoryCredentialStore implements SyncCredentialStore {
  @override
  Future<SyncCredentials> read() async => const SyncCredentials();

  @override
  Future<void> write(SyncCredentials credentials) async {}
}

class _RecordingReminderService implements DueReminderService {
  final List<DueReminderPayload> notified = [];
  final List<ScheduledDueReminder> scheduled = [];
  int cancelAllCount = 0;
  Set<String> state = {};

  @override
  Future<bool> ensurePermissions() async => true;

  @override
  Future<void> notify(DueReminderPayload payload) async =>
      notified.add(payload);

  @override
  Future<void> schedule(ScheduledDueReminder reminder) async =>
      scheduled.add(reminder);

  @override
  Future<void> cancelAll() async => cancelAllCount++;

  @override
  Future<Set<String>> loadNotifiedKeys() async => state;

  @override
  Future<void> saveNotifiedKeys(Set<String> keys) async => state = keys;
}

/// 记录搜索跳转回调的 harness（闭包捕获字段而非局部变量）。
class _SearchHarness {
  bool projectOpened = false;
  TodoData? openedTodo;
}
