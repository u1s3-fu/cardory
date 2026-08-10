import 'package:cardory/main.dart';
import 'package:cardory/data/cardory_store.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/sync/sync_credentials.dart';
import 'package:cardory/sync/sync_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Cardory home renders loaded data', (WidgetTester tester) async {
    await tester.pumpWidget(CardoryApp(repository: _MemoryRepository()));
    await tester.pumpAndSettle();

    expect(find.text('板记 Cardory'), findsOneWidget);
    expect(find.text('把项目推进，落到今天'), findsOneWidget);
    expect(find.byType(CardoryApp), findsOneWidget);
  });

  testWidgets('Cardory shows a recoverable load error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(CardoryApp(repository: _FailingRepository()));
    await tester.pumpAndSettle();

    expect(find.text('无法加载本地数据'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('quick add sub reminder supports multiline content', (
    WidgetTester tester,
  ) async {
    SubTodoData? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<SubTodoData>(
                context: context,
                builder: (_) =>
                    const QuickAddSubTodoDialog(recordCreatedAt: true),
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final contentField = find.byKey(const Key('quick-add-subtodo-content'));
    final textField = tester.widget<TextField>(contentField);
    expect(textField.keyboardType, TextInputType.multiline);
    expect(textField.textInputAction, TextInputAction.newline);
    expect(textField.minLines, 3);
    expect(textField.maxLines, 6);
    expect(
      find.byKey(const Key('quick-add-subtodo-reminder-time')),
      findsOneWidget,
    );

    await tester.enterText(contentField, '第一行\n第二行');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(result?.content, '第一行\n第二行');
    expect(result?.createdAt, isNotNull);
    expect(result?.dueAt, isNull);
  });

  testWidgets('sub reminder timestamps wrap without layout overflow', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(260, 360);
    addTearDown(tester.view.reset);
    final createdAt = DateTime(2026, 7, 31, 9, 15);
    final reminderAt = DateTime(2026, 8, 1, 10, 30);
    final todo = TodoData(
      id: 'todo-with-reminder-time',
      title: '待办',
      projectId: '',
      projectTitle: '未关联项目',
      priority: ProjectPriority.p1,
      done: false,
      subTodos: [
        SubTodoData(
          id: 'subtodo-with-reminder-time',
          content: '第一行\n第二行',
          done: false,
          createdAt: createdAt,
          dueAt: reminderAt,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubTodoTile(
            todo: todo,
            subTodo: todo.subTodos.single,
            onToggle: (_, _) async {},
          ),
        ),
      ),
    );

    expect(find.text('添加 2026-07-31 09:15'), findsOneWidget);
    expect(find.text('提醒 2026-08-01 10:30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final viewport in <(String, Size)>[
    ('手机', const Size(390, 844)),
    ('平板', const Size(900, 1100)),
    ('桌面', const Size(1440, 900)),
    ('最大化', const Size(2560, 1440)),
  ]) {
    testWidgets('Cardory ${viewport.$1}布局无溢出', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport.$2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(CardoryApp(repository: _MemoryRepository()));
      await tester.pumpAndSettle();

      if (viewport.$1 == '手机') {
        expect(find.byKey(const Key('bottom-navigation')), findsOneWidget);
        expect(find.byType(Sidebar), findsNothing);
      } else {
        expect(find.byKey(const Key('section-navigation')), findsNothing);
        expect(find.byType(Sidebar), findsOneWidget);
      }
      expect(find.byKey(const Key('kanban-responsive-board')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final layout in <(String, Size, int)>[
    ('窄屏单列', const Size(400, 1600), 1),
    ('中屏双列', const Size(700, 1600), 2),
    ('宽屏四列', const Size(1000, 1600), 4),
  ]) {
    testWidgets('项目看板${layout.$1}自适应容器', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = layout.$2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KanbanBoard(
                data: CardoryData.seed(),
                onOpenProject: (_) async {},
                onEditProject: (_) async {},
                onDeleteProject: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boardWidth = tester
          .getSize(find.byKey(const Key('kanban-responsive-board')))
          .width;
      final expectedColumnWidth =
          (boardWidth - 12 * (layout.$3 - 1)) / layout.$3;
      expect(
        tester.getSize(find.byType(KanbanColumn).first).width,
        closeTo(expectedColumnWidth, 0.1),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('手机弹窗在窄屏和低高度下可滚动', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(CardoryApp(repository: _MemoryRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();

    expect(find.byType(ProjectDialog), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings panel exposes sync state and manual action', (
    WidgetTester tester,
  ) async {
    var syncCount = 0;
    SettingsCategoryType? openedCategory;
    var passwordChangeCount = 0;
    var restoreCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPanel(
            dataPath: '/vault/cardory-data.cardory',
            settings: const AppSettings(
              syncProvider: SyncProviderType.directory,
              syncDirectoryPath: '/sync',
            ),
            syncStatus: const SyncStatus(
              phase: SyncPhase.failure,
              message: '网络不可用',
            ),
            onSync: () => syncCount++,
            onOpenSettings: (category) => openedCategory = category,
            onChangePassword: () => passwordChangeCount++,
            onRestoreBackup: () => restoreCount++,
          ),
        ),
      ),
    );

    expect(find.text('工作台偏好'), findsOneWidget);
    expect(find.text('安全'), findsOneWidget);
    expect(find.text('本地数据'), findsOneWidget);
    expect(find.text('同步'), findsOneWidget);
    expect(find.text('配置同步'), findsNothing);
    expect(find.text('同步方式：同步目录'), findsOneWidget);
    expect(find.text('网络不可用'), findsOneWidget);
    expect(find.text('修改密码'), findsOneWidget);
    expect(find.text('恢复数据'), findsOneWidget);

    await tester.tap(find.text('安全'));
    expect(openedCategory, SettingsCategoryType.security);
    await tester.tap(find.text('立即同步'));
    await tester.tap(find.text('修改密码'));
    await tester.tap(find.text('恢复数据'));
    expect(syncCount, 1);
    expect(passwordChangeCount, 1);
    expect(restoreCount, 1);
  });

  testWidgets('asset dialog switches fields by asset type', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AssetDialog(serverTypes: ['物理服务器'])),
      ),
    );

    expect(find.text('版本'), findsOneWidget);
    expect(find.text('路径'), findsOneWidget);
    expect(find.text('服务器序列号'), findsNothing);

    await tester.tap(find.text('硬件资产'));
    await tester.pumpAndSettle();

    expect(find.text('服务器序列号'), findsOneWidget);
    expect(find.text('服务器类型'), findsOneWidget);
    expect(find.text('版本'), findsNothing);
  });

  testWidgets('asset detail dialog is read-only and opens editing explicitly', (
    tester,
  ) async {
    const asset = AssetData(
      id: 'asset-1',
      type: AssetType.software,
      name: 'Cardory API',
      projectId: 'project-1',
      version: '1.2.0',
      port: '8080',
      path: '/srv/cardory',
      username: 'admin',
      password: 'secret',
      note: '主服务',
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    showDialog<bool>(
      context: tester.element(find.byType(SizedBox)),
      builder: (_) => const AssetDetailDialog(asset: asset),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cardory API'), findsOneWidget);
    expect(find.text('版本'), findsOneWidget);
    expect(find.text('1.2.0'), findsOneWidget);
    expect(find.text('••••••'), findsOneWidget);
    expect(find.byKey(const Key('edit-asset-button')), findsOneWidget);
    expect(find.text('保存'), findsNothing);
  });

  testWidgets('security settings only show security fields', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsDialog(
          settings: const AppSettings(),
          currentDataPath: '/vault/cardory-data.cardory',
          credentialStore: _CredentialStore(null),
          category: SettingsCategoryType.security,
        ),
      ),
    );

    expect(find.text('安全'), findsOneWidget);
    expect(find.text('应用切到后台时自动锁定'), findsOneWidget);
    expect(find.text('工作台'), findsNothing);
    expect(find.text('本地数据'), findsNothing);
    expect(find.text('同步'), findsNothing);
  });
  testWidgets('password dialog validates and returns credentials', (
    WidgetTester tester,
  ) async {
    PasswordChangeResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDialog<PasswordChangeResult>(
                context: context,
                builder: (_) => const PasswordChangeDialog(),
              );
            },
            child: const Text('打开修改密码'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开修改密码'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '当前密码'),
      'current password',
    );
    await tester.enterText(find.widgetWithText(TextField, '新密码'), 'short');
    await tester.enterText(find.widgetWithText(TextField, '确认新密码'), 'short');
    await tester.tap(find.widgetWithText(FilledButton, '修改密码'));
    await tester.pump();
    expect(find.text('新密码至少需要 8 个字符。'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '新密码'),
      'replacement password',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '确认新密码'),
      'different password',
    );
    await tester.tap(find.widgetWithText(FilledButton, '修改密码'));
    await tester.pump();
    expect(find.text('两次输入的新密码不一致。'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '确认新密码'),
      'replacement password',
    );
    await tester.tap(find.widgetWithText(FilledButton, '修改密码'));
    await tester.pumpAndSettle();
    expect(result?.currentPassword, 'current password');
    expect(result?.newPassword, 'replacement password');
  });

  testWidgets('recovery dialog shows the new key and invalidation warning', (
    WidgetTester tester,
  ) async {
    const recoveryKey = 'abcdefgh-ijklmnop-qrstuvwx-yz012345-6789ABCD-EFGHIJKL';
    final clipboardCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: RecoveryKeyDialog(recoveryKey: recoveryKey)),
    );

    expect(find.text('保存新恢复码'), findsOneWidget);
    expect(find.text(recoveryKey), findsOneWidget);
    expect(find.text('旧恢复码已失效。新恢复码可用于重设密码或恢复备份。'), findsOneWidget);
    expect(find.text('导出恢复文件'), findsNothing);
    await tester.tap(find.text('复制恢复码'));
    await tester.pump();
    expect(find.text('恢复码已复制，请粘贴到安全位置手动保存。'), findsOneWidget);
    expect(clipboardCalls, hasLength(1));
    expect(clipboardCalls.single.method, 'Clipboard.setData');
    expect(clipboardCalls.single.arguments, {'text': recoveryKey});
  });

  testWidgets('initial recovery key is copied without opening file export', (
    WidgetTester tester,
  ) async {
    const recoveryKey = 'initial-recovery-key-for-manual-storage';
    final repository = _SetupRepository(recoveryKey);
    final clipboardCalls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CardoryVaultGate(
          repository: repository,
          credentialStore: _CredentialStore(null),
          vaultCredentialStore: _MemoryVaultCredentialStore(),
          autoLockEnabled: true,
          onSettingsChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '密码'), 'password123');
    await tester.enterText(
      find.widgetWithText(TextField, '确认密码'),
      'password123',
    );
    await tester.tap(find.text('创建加密保险库'));
    await tester.pumpAndSettle();

    expect(find.text('保存你的恢复码'), findsOneWidget);
    expect(find.text(recoveryKey), findsOneWidget);
    expect(find.text('导出恢复文件'), findsNothing);
    await tester.tap(find.text('复制恢复码'));
    await tester.pump();

    expect(repository.exportCallCount, 0);
    expect(clipboardCalls, hasLength(1));
    expect(clipboardCalls.single.arguments, {'text': recoveryKey});
  });

  testWidgets('setup screen exposes the manual backup recovery form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CardoryVaultGate(
          repository: _SetupRepository('recovery-key'),
          credentialStore: _CredentialStore(null),
          vaultCredentialStore: _MemoryVaultCredentialStore(),
          autoLockEnabled: true,
          onSettingsChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-backup-restore')));
    await tester.pumpAndSettle();

    expect(find.text('从备份恢复'), findsOneWidget);
    expect(find.byKey(const Key('pick-cardory-backup')), findsOneWidget);
    expect(find.byKey(const Key('restore-recovery-key')), findsOneWidget);
    expect(find.byKey(const Key('restore-new-password')), findsOneWidget);
    expect(find.byKey(const Key('restore-confirm-password')), findsOneWidget);
  });

  testWidgets('recovery key resets the password before unlocking', (
    WidgetTester tester,
  ) async {
    final repository = _LockedRepository();
    final vault = _MemoryVaultCredentialStore();
    await tester.pumpWidget(
      MaterialApp(
        home: CardoryVaultGate(
          repository: repository,
          credentialStore: _CredentialStore(null),
          vaultCredentialStore: vault,
          autoLockEnabled: true,
          onSettingsChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复码'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '恢复码'),
      'saved-recovery-key',
    );
    await tester.enterText(
      find.byKey(const Key('recovery-new-password')),
      'replacement password',
    );
    await tester.enterText(
      find.byKey(const Key('recovery-confirm-password')),
      'replacement password',
    );
    await tester.tap(find.text('重设密码并解锁'));
    await tester.pumpAndSettle();

    expect(repository.recoveryKey, 'saved-recovery-key');
    expect(repository.newPassword, 'replacement password');
    expect(vault.password, 'replacement password');
    expect(find.text('板记 Cardory'), findsOneWidget);
  });

  testWidgets('settings dialog keeps stored password out of text controller', (
    WidgetTester tester,
  ) async {
    SettingsResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDialog<SettingsResult>(
                context: context,
                builder: (_) => SettingsDialog(
                  settings: const AppSettings(
                    syncProvider: SyncProviderType.webdav,
                    webDavUrl: 'https://dav.example.com/old/',
                    webDavUsername: 'user',
                    syncRevision: 'v1',
                    syncLocalHash: 'hash',
                  ),
                  currentDataPath: '/vault/cardory-data.cardory',
                  credentialStore: _CredentialStore('secret'),
                ),
              );
            },
            child: const Text('打开设置'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    final passwordField = tester.widget<TextField>(
      find.widgetWithText(TextField, '密码（已保存）'),
    );
    expect(passwordField.controller!.text, isEmpty);
    expect(find.text('自托管 API'), findsNothing);
    expect(find.text('记录子任务添加时间'), findsOneWidget);
    expect(find.text('新建子任务时记录当前本地日期时间'), findsOneWidget);
    expect(find.text('自动设置子任务提醒时间'), findsNothing);

    expect(find.text('自定义主题颜色'), findsNothing);
    final redSlider = find.byKey(const Key('theme-color-red-slider'));
    await tester.ensureVisible(redSlider);
    final redBefore = tester.widget<Slider>(redSlider).value;
    await tester.drag(redSlider, const Offset(100, 0));
    await tester.pump();
    expect(tester.widget<Slider>(redSlider).value, greaterThan(redBefore));

    final priorityField = find.byKey(const Key('home-reminder-priority-field'));
    await tester.ensureVisible(priorityField);
    await tester.tap(priorityField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('中优先级及以上').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('record-subtodo-created-at')));
    await tester.pump();

    final urlField = find.widgetWithText(TextField, 'WebDAV 地址');
    await tester.enterText(urlField, 'https://dav.example.com/new/');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.settings.syncRevision, isNull);
    expect(result!.settings.syncLocalHash, isNull);
    expect(result!.settings.homeReminderPriorityThreshold, ProjectPriority.p1);
    expect(result!.settings.recordSubTodoCreatedAt, isTrue);
    expect(result!.credentials.password, isEmpty);
  });

  testWidgets('self-hosted settings remain editable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsDialog(
          settings: const AppSettings(
            syncProvider: SyncProviderType.selfHosted,
            selfHostedUrl: 'https://sync.example.com',
          ),
          currentDataPath: '/vault/cardory-data.cardory',
          credentialStore: _CredentialStore(null),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('自托管 API'), findsOneWidget);
    expect(find.text('自托管 API 地址'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home reminders include priorities through the configured level',
    (tester) async {
      final todos = ProjectPriority.values
          .map(
            (priority) => TodoData(
              id: 'todo-${priority.name}',
              title: '${priority.label} 待办',
              projectId: '',
              projectTitle: '未关联项目',
              priority: priority,
              done: false,
            ),
          )
          .toList();
      todos.addAll(
        List.generate(
          7,
          (index) => TodoData(
            id: 'todo-extra-$index',
            title: 'P2 追加待办 ${index + 1}',
            projectId: '',
            projectTitle: '未关联项目',
            priority: ProjectPriority.p2,
            done: false,
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReminderPanel(
                todos: todos,
                priorityThreshold: ProjectPriority.p2,
                onToggleTodo: (todo) async => todo,
                onToggleSubTodo: (todo, _) async => todo,
                onAddSubTodo: (_) async {},
                onOpenTodo: (todo) async => todo,
              ),
            ),
          ),
        ),
      );

      expect(find.text('高优先级 待办'), findsOneWidget);
      expect(find.text('中 待办'), findsOneWidget);
      expect(find.text('普通 待办'), findsOneWidget);
      expect(find.text('P2 追加待办 7'), findsOneWidget);
      expect(find.text('低 待办'), findsNothing);
    },
  );

  testWidgets('task and progress surfaces dispatch their actions', (
    tester,
  ) async {
    final todo = TodoData(
      id: 'todo-action',
      title: '可操作待办',
      projectId: '',
      projectTitle: '未关联项目',
      priority: ProjectPriority.p0,
      done: false,
      subTodos: const [
        SubTodoData(id: 'subtodo-action', content: '可操作子待办', done: false),
      ],
    );
    final progress = ProjectProgressEntry(
      id: 'progress-action',
      note: '可编辑进度',
      progress: 0.5,
      createdAt: DateTime(2026, 7, 30),
    );
    var opened = false;
    var completed = false;
    var subTodoCompleted = false;
    var deleted = false;
    var edited = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ReminderPanel(
                todos: [todo],
                priorityThreshold: ProjectPriority.p2,
                onToggleTodo: (_) async {
                  completed = true;
                  return todo.copyWith(done: true);
                },
                onToggleSubTodo: (_, _) async {
                  subTodoCompleted = true;
                  return todo;
                },
                onAddSubTodo: (_) async {},
                onOpenTodo: (_) async {
                  opened = true;
                  return todo;
                },
              ),
              TodoPanel(
                todos: [todo],
                onToggle: (_) async {},
                onToggleSubTodo: (_, _) async {},
                onOpenTodo: (_) async {},
                onDeleteTodo: (_) async {
                  deleted = true;
                  return true;
                },
              ),
              ProgressTimeline(
                entries: [progress],
                onEdit: (_) async => edited = true,
              ),
            ],
          ),
        ),
      ),
    );

    // 卡片式待办：点击卡片打开编辑，点击勾选方块完成待办。
    await tester.tap(find.text('可操作待办').first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.check_box_outline_blank_rounded).first);
    await tester.pump();
    // 子待办行可切换完成状态。
    await tester.tap(find.text('可操作子待办').first);
    await tester.pump();
    // 待办页（TodoTile）提供删除入口。
    await tester.tap(find.byTooltip('删除待办'));
    await tester.pump();
    await tester.scrollUntilVisible(find.byTooltip('编辑进度'), 200);
    await tester.tap(find.byTooltip('编辑进度'));
    await tester.pump();

    expect(opened, isTrue);
    expect(completed, isTrue);
    expect(subTodoCompleted, isTrue);
    expect(deleted, isTrue);
    expect(edited, isTrue);
  });

  testWidgets('progress dialog preserves identity while editing', (
    tester,
  ) async {
    final createdAt = DateTime(2026, 7, 30, 9, 30);
    final entry = ProjectProgressEntry(
      id: 'progress-existing',
      note: '原始说明',
      progress: 0.4,
      createdAt: createdAt,
    );
    ProjectProgressEntry? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDialog<ProjectProgressEntry>(
                context: context,
                builder: (_) => ProgressDialog(entry: entry),
              );
            },
            child: const Text('编辑已有进度'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('编辑已有进度'));
    await tester.pumpAndSettle();
    expect(find.text('编辑进度'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
    final noteField = find.widgetWithText(TextField, '进度说明');
    expect(tester.widget<TextField>(noteField).controller?.text, '原始说明');
    expect(find.textContaining('%'), findsNothing);

    await tester.enterText(noteField, '更新说明');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(result?.id, entry.id);
    expect(result?.createdAt, createdAt);
    expect(result?.note, '更新说明');
    expect(result?.progress, entry.progress);
  });
}

class _MemoryRepository implements CardoryRepository {
  CardoryData data = CardoryData.seed();
  AppSettings settings = const AppSettings();

  @override
  Future<CardoryAccessState> accessState() async => CardoryAccessState.unlocked;

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {}

  @override
  Future<CardoryLoadResult> setup(String password) async => load();

  @override
  Future<CardoryLoadResult> unlockWithPassword(String password) async => load();

  @override
  Future<CardoryLoadResult> unlockWithRecoveryKey(String recoveryKey) async =>
      load();

  @override
  Future<CardoryLoadResult> resetPasswordWithRecoveryKey(
    String recoveryKey,
    String newPassword,
  ) async => load();

  @override
  Future<CardoryLoadResult> restoreFromBackup(
    List<int> bytes,
    String recoveryKey,
    String newPassword,
  ) async => load();

  @override
  Future<String> exportRecoveryFile(String path, String recoveryKey) async =>
      path;

  @override
  Future<List<int>> exportContainer() async => [1, 2, 3];

  @override
  Future<CardoryData> importContainer(
    List<int> bytes,
    AppSettings settings,
  ) async => data;

  @override
  Future<CardoryLoadResult> load() async => CardoryLoadResult(
    data: data,
    settings: settings,
    path: 'memory/cardory-data.json',
  );

  @override
  Future<void> save(CardoryData data, AppSettings settings) async {
    this.data = data;
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    this.settings = settings;
  }
}

class _SetupRepository extends _MemoryRepository {
  _SetupRepository(this.recoveryKey);

  final String recoveryKey;
  int exportCallCount = 0;

  @override
  Future<CardoryAccessState> accessState() async =>
      CardoryAccessState.setupRequired;

  @override
  Future<CardoryLoadResult> setup(String password) async => CardoryLoadResult(
    data: data,
    settings: settings,
    path: 'memory/cardory-data.json',
    recoveryKey: recoveryKey,
  );

  @override
  Future<String> exportRecoveryFile(String path, String recoveryKey) async {
    exportCallCount++;
    return path;
  }
}

class _LockedRepository extends _MemoryRepository {
  String? recoveryKey;
  String? newPassword;

  @override
  Future<CardoryAccessState> accessState() async => CardoryAccessState.locked;

  @override
  Future<CardoryLoadResult> resetPasswordWithRecoveryKey(
    String recoveryKey,
    String newPassword,
  ) async {
    this.recoveryKey = recoveryKey;
    this.newPassword = newPassword;
    return load();
  }
}

class _FailingRepository implements CardoryRepository {
  @override
  Future<CardoryAccessState> accessState() async => CardoryAccessState.unlocked;

  @override
  Future<void> changePassword(String currentPassword, String newPassword) =>
      Future.error(const CardoryStorageException('测试读取失败'));

  @override
  Future<CardoryLoadResult> setup(String password) => load();

  @override
  Future<CardoryLoadResult> unlockWithPassword(String password) => load();

  @override
  Future<CardoryLoadResult> unlockWithRecoveryKey(String recoveryKey) => load();

  @override
  Future<CardoryLoadResult> resetPasswordWithRecoveryKey(
    String recoveryKey,
    String newPassword,
  ) => load();

  @override
  Future<CardoryLoadResult> restoreFromBackup(
    List<int> bytes,
    String recoveryKey,
    String newPassword,
  ) => load();

  @override
  Future<String> exportRecoveryFile(String path, String recoveryKey) async =>
      path;

  @override
  Future<List<int>> exportContainer() =>
      Future.error(const CardoryStorageException('测试读取失败'));

  @override
  Future<CardoryData> importContainer(List<int> bytes, AppSettings settings) =>
      Future.error(const CardoryStorageException('测试读取失败'));

  @override
  Future<CardoryLoadResult> load() =>
      Future.error(const CardoryStorageException('测试读取失败'));

  @override
  Future<void> save(CardoryData data, AppSettings settings) async {}

  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

class _CredentialStore implements SyncCredentialStore {
  _CredentialStore(this.password);

  final String? password;

  @override
  Future<void> deleteSelfHostedToken() async {}

  @override
  Future<void> deleteWebDav() async {}

  @override
  Future<String?> readSelfHostedToken() async => null;

  @override
  Future<WebDavCredentials?> readWebDav() async =>
      password == null ? null : WebDavCredentials(password: password!);

  @override
  Future<void> writeSelfHostedToken(String token) async {}

  @override
  Future<void> writeWebDav(WebDavCredentials credentials) async {}
}

class _MemoryVaultCredentialStore implements VaultCredentialStore {
  String? password;

  @override
  Future<void> deletePassword() async => password = null;

  @override
  Future<String?> readPassword() async => password;

  @override
  Future<void> writePassword(String password) async {
    this.password = password;
  }
}
