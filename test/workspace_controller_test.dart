import 'package:cardory/application/attachment_repository.dart';
import 'package:cardory/application/widget_data_service.dart';
import 'package:cardory/application/workspace_controller.dart';
import 'package:cardory/application/workspace_settings_service.dart';
import 'package:cardory/data/cardory_store.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/sync/sync_credentials.dart';
import 'package:cardory/sync/sync_models.dart';
import 'package:cardory/sync/sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _MemoryRepository repository;
  late _MemoryAttachments attachments;
  late _RecordingWidgetService widgetService;
  late WorkspaceController controller;

  setUp(() {
    repository = _MemoryRepository(_workspaceData());
    attachments = _MemoryAttachments();
    widgetService = _RecordingWidgetService();
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
      repository.failNextSave = true;
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
  Future<void> prune(Set<String> activeStorageKeys) async {}

  @override
  Future<void> delete(AttachmentData attachment) async =>
      deleted.add(attachment);

  @override
  Future<AttachmentData> migrateLegacy(AttachmentData attachment) async =>
      attachment;

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

  @override
  Future<void> updateWidgetData(CardoryData data) async => lastData = data;
}

class _Credentials implements SyncCredentialStore {
  @override
  Future<SyncCredentials> read() async => const SyncCredentials();

  @override
  Future<void> write(SyncCredentials credentials) async {}
}
