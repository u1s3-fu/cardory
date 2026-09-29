import 'dart:typed_data';

import 'package:cardory/domain/attachment_repository.dart';
import 'package:cardory/domain/calendar_push_registry.dart';
import 'package:cardory/domain/due_reminder_service.dart';
import 'package:cardory/domain/widget_data_service.dart';
import 'package:cardory/application/workspace_controller.dart';
import 'package:cardory/application/workspace_settings_service.dart';
import 'package:cardory/domain/asset_template.dart';
import 'package:cardory/domain/cardory_repository.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/services/system_calendar_service.dart';
import 'package:cardory/sync/sync_credentials.dart';
import 'package:cardory/sync/sync_models.dart';
import 'package:cardory/sync/sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/in_memory_row_level_workspace_store.dart';

void main() {
  late _MemoryRepository repository;
  late _MemoryAttachments attachments;
  late _RecordingWidgetService widgetService;
  late InMemoryRowLevelWorkspaceStore rowLevelStore;
  late WorkspaceController controller;

  setUp(() {
    repository = _MemoryRepository(_workspaceData());
    attachments = _MemoryAttachments();
    widgetService = _RecordingWidgetService();
    rowLevelStore = InMemoryRowLevelWorkspaceStore(
      () => repository.data,
      (data) => repository.data = data,
    );
    controller = WorkspaceController(
      repository: repository,
      vaultRepository: repository,
      settingsService: WorkspaceSettingsService(
        repository: repository,
        credentialStore: _Credentials(),
      ),
      syncService: SyncCoordinator(
        repository: repository,
        providerFactory: (_) async =>
            throw const SyncUnavailableException('not used'),
        attachmentRepositoryFactory: (_) => attachments,
      ),
      attachmentRepositoryFactory: (_) => attachments,
      rowLevelStore: rowLevelStore,
      widgetDataService: widgetService,
    );
  });

  tearDown(() => controller.dispose());

  test('project deletion cascades metadata and attachment cleanup', () async {
    await controller.initialize(await repository.load());

    await controller.deleteProject('project-1');

    expect(controller.data.projects, isEmpty);
    expect(controller.data.todos, isEmpty);
    expect(controller.data.assets, isEmpty);
    expect(attachments.deleted.map((item) => item.id), ['attachment-1']);
    expect(controller.settings.pendingAttachmentDeletes, [
      'attachment-1.cardory-attachment',
    ]);
    expect(repository.data.assets, isEmpty);
    expect(widgetService.lastData, same(controller.data));
  });

  test('project rename keeps denormalized todo title consistent', () async {
    await controller.initialize(await repository.load());
    final renamed = controller.data.projects.single.copyWith(title: '新名称');

    await controller.editProject(renamed);

    expect(controller.data.projects.single.title, '新名称');
    expect(controller.data.todos.single.projectTitle, '新名称');
  });

  test(
    'failed mutation restores state and removes newly added files',
    () async {
      await controller.initialize(await repository.load());
      rowLevelStore.failNextWrite = true;
      final attachment = _attachment('new-attachment');
      final project = ProjectData(
        id: 'new-project',
        title: '新项目',
        description: '',
        priority: ProjectPriority.p1,
        stage: ProjectStage.planned,
        progressEntries: const [],
        attachments: [attachment],
      );

      await expectLater(controller.addProject(project), throwsStateError);

      expect(controller.data.projects, hasLength(1));
      expect(attachments.deleted, [attachment]);
    },
  );

  test('row-level write failure surfaces without snapshot fallback', () async {
    await controller.initialize(await repository.load());
    final controllerWithoutStore = WorkspaceController(
      repository: repository,
      vaultRepository: repository,
      settingsService: WorkspaceSettingsService(
        repository: repository,
        credentialStore: _Credentials(),
      ),
      syncService: SyncCoordinator(
        repository: repository,
        providerFactory: (_) async =>
            throw const SyncUnavailableException('not used'),
        attachmentRepositoryFactory: (_) => attachments,
      ),
      attachmentRepositoryFactory: (_) => attachments,
    );
    addTearDown(controllerWithoutStore.dispose);

    await expectLater(
      controllerWithoutStore.addTodo(
        const TodoData(
          id: 'todo-x',
          title: '待办',
          projectId: '',
          projectTitle: '',
          priority: ProjectPriority.p2,
          done: false,
        ),
      ),
      throwsStateError,
    );
  });

  test(
    'project edit deletes removed attachments and queues remote cleanup',
    () async {
      await controller.initialize(await repository.load());
      final original = controller.data.projects.single;

      await controller.editProject(original.copyWith(attachments: const []));

      expect(controller.data.projects.single.attachments, isEmpty);
      expect(attachments.deleted.map((item) => item.id), ['attachment-1']);
      expect(controller.settings.pendingAttachmentDeletes, [
        'attachment-1.cardory-attachment',
      ]);
    },
  );

  test(
    'due reminders fire on load, dedupe on reload, and honor settings',
    () async {
      final today = DateTime.now();
      final todayKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final repository =
          _MemoryRepository(
              CardoryData(
                projects: const [],
                todos: const [],
                assets: [
                  AssetData(
                    id: 'asset-due',
                    type: AssetType.software,
                    name: '到期资产',
                    templateId: 'tpl-test',
                    customFields: {'expireDate': todayKey},
                  ),
                ],
              ),
            )
            ..settings = const AppSettings(
              assetTemplates: [
                AssetTemplate(
                  id: 'tpl-test',
                  name: '测试模板',
                  fields: [
                    AssetTemplateField(
                      key: 'expireDate',
                      label: '注册到期',
                      kind: AssetFieldKind.date,
                      remind: true,
                    ),
                  ],
                ),
              ],
            );
      final reminderService = _RecordingReminderService();
      final reminderController = WorkspaceController(
        repository: repository,
        vaultRepository: repository,
        settingsService: WorkspaceSettingsService(
          repository: repository,
          credentialStore: _Credentials(),
        ),
        syncService: SyncCoordinator(
          repository: repository,
          providerFactory: (_) async =>
              throw const SyncUnavailableException('not used'),
          attachmentRepositoryFactory: (_) => attachments,
        ),
        attachmentRepositoryFactory: (_) => attachments,
        widgetDataService: widgetService,
        dueReminderService: reminderService,
      );
      addTearDown(reminderController.dispose);

      await reminderController.initialize(await repository.load());
      // 当日到期：立即通知一次，标题沿用「字段标签 · 资产名」。
      expect(reminderService.notified.length, 1);
      expect(reminderService.notified.single.title, '注册到期 · 到期资产');
      expect(reminderService.notified.single.body, '今天到期');
      expect(reminderService.state, isNotEmpty);

      // 重新加载：去重状态生效，不再重复通知。
      await reminderController.reload();
      expect(reminderService.notified.length, 1);

      // 关闭提醒开关：清空全部通知且不再扫描。
      reminderService.notified.clear();
      repository.settings = repository.settings.copyWith(
        dueRemindersEnabled: false,
      );
      await reminderController.reload();
      expect(reminderService.notified, isEmpty);
      expect(reminderService.cancelAllCount, greaterThanOrEqualTo(1));
    },
  );

  test(
    'calendar reconcile recycles pushed events on asset edit and delete',
    () async {
      final repository =
          _MemoryRepository(
              CardoryData(
                projects: const [],
                todos: const [],
                assets: [
                  AssetData(
                    id: 'asset-cal',
                    type: AssetType.software,
                    name: '日历资产',
                    templateId: 'tpl-test',
                    customFields: {'expireDate': '2026-10-01'},
                  ),
                ],
              ),
            )
            ..settings = const AppSettings(
              assetTemplates: [
                AssetTemplate(
                  id: 'tpl-test',
                  name: '测试模板',
                  fields: [
                    AssetTemplateField(
                      key: 'expireDate',
                      label: '注册到期',
                      kind: AssetFieldKind.date,
                      remind: true,
                    ),
                  ],
                ),
              ],
            );
      final calendarService = _RecordingCalendarService();
      final registry = _MemoryCalendarRegistry()
        ..entries = {
          calendarPushRegistryKey(
            'asset-cal',
            'expireDate',
          ): const CalendarPushRecord(
            eventId: 'evt-1',
            date: '2026-10-01',
            title: '注册到期 · 日历资产',
          ),
        };
      final controller = WorkspaceController(
        repository: repository,
        vaultRepository: repository,
        settingsService: WorkspaceSettingsService(
          repository: repository,
          credentialStore: _Credentials(),
        ),
        syncService: SyncCoordinator(
          repository: repository,
          providerFactory: (_) async =>
              throw const SyncUnavailableException('not used'),
          attachmentRepositoryFactory: (_) => attachments,
        ),
        attachmentRepositoryFactory: (_) => attachments,
        rowLevelStore: InMemoryRowLevelWorkspaceStore(
          () => repository.data,
          (data) => repository.data = data,
        ),
        widgetDataService: widgetService,
        systemCalendarService: calendarService,
        calendarPushRegistry: registry,
      );
      addTearDown(controller.dispose);

      // 加载对账：登记与当前到期一致，不回收。
      await controller.initialize(await repository.load());
      expect(calendarService.deleted, isEmpty);

      // 修改到期日：旧事件删除 + 按新日期/标题新建，登记更新。
      final asset = controller.data.assets.single;
      await controller.editAsset(
        asset,
        asset.copyWith(customFields: {'expireDate': '2026-11-05'}),
      );
      expect(calendarService.deleted, ['evt-1']);
      expect(calendarService.created, hasLength(1));
      expect(calendarService.created.single.title, '注册到期 · 日历资产');
      expect(calendarService.created.single.start, DateTime(2026, 11, 5));
      expect(
        registry
            .entries[calendarPushRegistryKey('asset-cal', 'expireDate')]!
            .eventId,
        'fake-event-1',
      );

      // 删除资产：回收事件，登记清空。
      await controller.deleteAsset(controller.data.assets.single);
      expect(calendarService.deleted, ['evt-1', 'fake-event-1']);
      expect(registry.entries, isEmpty);
    },
  );
}

CardoryData _workspaceData() {
  final project = ProjectData(
    id: 'project-1',
    title: '项目',
    description: '',
    priority: ProjectPriority.p1,
    stage: ProjectStage.doing,
    progressEntries: const [],
    attachments: [_attachment('attachment-1')],
  );
  const todo = TodoData(
    id: 'todo-1',
    title: '待办',
    projectId: 'project-1',
    projectTitle: '项目',
    priority: ProjectPriority.p1,
    done: false,
  );
  final asset = AssetData(
    id: 'asset-1',
    type: AssetType.software,
    name: '资产',
    projectId: 'project-1',
  );
  return CardoryData(projects: [project], todos: const [todo], assets: [asset]);
}

AttachmentData _attachment(String id) => AttachmentData(
  id: id,
  fileName: '$id.txt',
  storageKey: '$id.cardory-attachment',
  encryptionKey: 'key',
  size: 1,
  sha256: 'hash',
  createdAt: DateTime(2026),
);

class _MemoryRepository implements CardoryRepository {
  _MemoryRepository(this.data);

  CardoryData data;
  AppSettings settings = const AppSettings();
  bool failNextSave = false;

  @override
  Future<CardoryLoadResult> load() async => CardoryLoadResult(
    data: data,
    settings: settings,
    path: 'memory/cardory-data.cardory',
  );

  @override
  Future<void> save(CardoryData data, AppSettings settings) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('save failed');
    }
    this.data = data;
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    this.settings = settings;
  }

  @override
  Future<CardoryAccessState> accessState() async => CardoryAccessState.unlocked;

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
  Future<CardoryLoadResult> restoreFromBackup(
    List<int> bytes,
    String password,
  ) => load();

  @override
  Future<String> saveSyncConflictSnapshot(
    List<int> bytes, {
    DateTime? timestamp,
  }) async => 'snapshot';

  @override
  Future<CardoryLoadResult> setup(String password) => load();

  @override
  Future<CardoryLoadResult> unlockWithPassword(String password) => load();
}

class _MemoryAttachments implements AttachmentRepository {
  final List<AttachmentData> deleted = [];

  @override
  Future<Uint8List> readAttachmentBytes(AttachmentData attachment) =>
      throw UnimplementedError();

  @override
  Future<void> prune(Set<String> activeStorageKeys) async {}

  @override
  Future<void> delete(AttachmentData attachment) async =>
      deleted.add(attachment);

  @override
  Future<bool> contains(AttachmentData attachment) async => false;

  @override
  Future<String> createDownloadTarget(AttachmentData attachment) =>
      throw UnimplementedError();

  @override
  String encryptedPath(AttachmentData attachment) => throw UnimplementedError();

  @override
  Future<void> exportFile(AttachmentData attachment, String targetPath) =>
      throw UnimplementedError();

  @override
  Future<AttachmentData> importFile({
    required String sourcePath,
    required String id,
    required String fileName,
    String mimeType = '',
    String note = '',
    DateTime? createdAt,
  }) => throw UnimplementedError();

  @override
  Future<void> installEncrypted(
    AttachmentData attachment,
    String downloadedPath,
  ) => throw UnimplementedError();
}

class _RecordingWidgetService implements WidgetDataService {
  CardoryData? lastData;
  int clearCount = 0;

  @override
  Future<void> updateWidgetData(CardoryData data) async => lastData = data;

  @override
  Future<void> clearWidgetData() async => clearCount++;
}

/// 记录日历事件写入/删除的假服务。
class _RecordingCalendarService implements SystemCalendarService {
  final List<String> deleted = [];
  final List<({String title, DateTime start, DateTime end, String note})>
  created = [];
  int _nextId = 1;

  @override
  Future<List<SystemCalendarEvent>> loadEvents(
    DateTime start,
    DateTime end,
  ) async => const [];

  @override
  Future<SystemCalendarWriteResult> createEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    String note = '',
  }) async {
    created.add((title: title, start: start, end: end, note: note));
    return SystemCalendarWriteResult(
      success: true,
      detail: '已写入。',
      eventId: 'fake-event-${_nextId++}',
    );
  }

  @override
  Future<bool> deleteEvent(String eventId) async {
    deleted.add(eventId);
    return true;
  }
}

/// 内存版日历推送登记表。
class _MemoryCalendarRegistry implements CalendarPushRegistry {
  Map<String, CalendarPushRecord> entries = {};

  @override
  Future<Map<String, CalendarPushRecord>> load() async => Map.of(entries);

  @override
  Future<void> save(Map<String, CalendarPushRecord> saved) async {
    entries = Map.of(saved);
  }
}

/// 记录到期提醒调用的假服务（授权默认通过，状态保存在内存）。
class _RecordingReminderService implements DueReminderService {
  bool permissionsGranted = true;
  int permissionRequests = 0;
  int cancelAllCount = 0;
  final List<DueReminderPayload> notified = [];
  final List<ScheduledDueReminder> scheduled = [];
  Set<String> state = {};

  @override
  Future<bool> ensurePermissions() async {
    permissionRequests++;
    return permissionsGranted;
  }

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

class _Credentials implements SyncCredentialStore {
  @override
  Future<SyncCredentials> read() async => const SyncCredentials();

  @override
  Future<void> write(SyncCredentials credentials) async {}
}
