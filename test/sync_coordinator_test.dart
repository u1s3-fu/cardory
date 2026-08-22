import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:cardory/domain/attachment_repository.dart';
import 'package:cardory/data/cardory_store.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/sync/sync_coordinator.dart';
import 'package:cardory/sync/sync_models.dart';
import 'package:cardory/sync/sync_provider.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uploads local encrypted container when remote is empty', () async {
    final repository = _Repository([1, 2, 3]);
    final provider = _Provider();
    final coordinator = SyncCoordinator(
      repository: repository,
      providerFactory: (_) async => provider,
      attachmentRepositoryFactory: (_) => _EmptyAttachments(),
    );

    final settings = await coordinator.synchronize(
      const AppSettings(syncProvider: SyncProviderType.directory),
    );

    expect(provider.written, [1, 2, 3]);
    expect(settings.syncRevision, 'v1');
    expect(settings.syncLocalHash, isNotNull);
    expect(coordinator.status.phase, SyncPhase.success);
    expect(provider.disposed, isTrue);
  });

  test(
    'removes pending remote attachments after publishing metadata',
    () async {
      final repository = _Repository([1, 2, 3]);
      final provider = _Provider();
      final coordinator = SyncCoordinator(
        repository: repository,
        providerFactory: (_) async => provider,
        attachmentRepositoryFactory: (_) => _EmptyAttachments(),
      );

      final settings = await coordinator.synchronize(
        const AppSettings(
          syncProvider: SyncProviderType.directory,
          pendingAttachmentDeletes: ['removed.cardory-attachment'],
        ),
      );

      expect(provider.deleted, ['attachments/v1/removed.cardory-attachment']);
      expect(settings.pendingAttachmentDeletes, isEmpty);
    },
  );

  test('uploads encrypted attachments owned by projects', () async {
    final attachment = AttachmentData(
      id: 'project-file',
      fileName: 'specification.pdf',
      storageKey: 'project-file.cardory-attachment',
      encryptionKey: 'key',
      size: 42,
      sha256: 'hash',
      createdAt: DateTime.utc(2026, 8, 20),
    );
    final repository = _Repository(
      [1, 2, 3],
      data: CardoryData(
        projects: [
          ProjectData(
            id: 'project-1',
            title: '项目',
            description: '',
            priority: ProjectPriority.p1,
            stage: ProjectStage.doing,
            progressEntries: const [],
            attachments: [attachment],
          ),
        ],
        todos: const [],
      ),
    );
    final provider = _Provider();
    final coordinator = SyncCoordinator(
      repository: repository,
      providerFactory: (_) async => provider,
      attachmentRepositoryFactory: (_) => _PresentAttachments(),
    );

    await coordinator.synchronize(
      const AppSettings(syncProvider: SyncProviderType.directory),
    );

    expect(provider.uploaded, [
      (
        'attachments/v1/project-file.cardory-attachment',
        'encrypted/project-file.cardory-attachment',
      ),
    ]);
  });

  test(
    'local push preserves an existing immutable remote attachment',
    () async {
      final attachment = _projectAttachment();
      final provider = _Provider(remoteFilesExist: true);
      final coordinator = SyncCoordinator(
        repository: _Repository([1], data: _dataWithAttachment(attachment)),
        providerFactory: (_) async => provider,
        attachmentRepositoryFactory: (_) => _PresentAttachments(),
      );

      await coordinator.synchronize(
        const AppSettings(syncProvider: SyncProviderType.directory),
      );

      expect(provider.uploaded, isEmpty);
    },
  );

  test(
    'remote pull preserves an existing immutable local attachment',
    () async {
      final attachment = _projectAttachment();
      final repository = _Repository([
        1,
        2,
        3,
      ], data: _dataWithAttachment(attachment));
      final provider = _Provider(
        document: SyncDocument(
          bytes: Uint8List.fromList([4, 5]),
          revision: 'v2',
        ),
        remoteFilesExist: true,
      );
      final store = _PresentAttachments();
      final localHash = await Sha256().hash([1, 2, 3]);
      final coordinator = SyncCoordinator(
        repository: repository,
        providerFactory: (_) async => provider,
        attachmentRepositoryFactory: (_) => store,
      );

      await coordinator.synchronize(
        AppSettings(
          syncProvider: SyncProviderType.directory,
          syncRevision: 'v1',
          syncLocalHash: base64Url.encode(localHash.bytes),
        ),
      );

      expect(provider.downloaded, isEmpty);
      expect(store.installed, isEmpty);
    },
  );

  test('downloads a remote-only change', () async {
    final repository = _Repository([1, 2, 3]);
    final provider = _Provider(
      document: SyncDocument(bytes: Uint8List.fromList([4, 5]), revision: 'v2'),
    );
    final hash = await Sha256().hash([1, 2, 3]);
    final coordinator = SyncCoordinator(
      repository: repository,
      providerFactory: (_) async => provider,
      attachmentRepositoryFactory: (_) => _EmptyAttachments(),
    );

    final settings = await coordinator.synchronize(
      AppSettings(
        syncProvider: SyncProviderType.directory,
        syncRevision: 'v1',
        syncLocalHash: base64Url.encode(hash.bytes),
      ),
    );

    expect(repository.container, [4, 5]);
    expect(settings.syncRevision, 'v2');
    expect(coordinator.status.message, '已下载远端更新');
  });

  test('keeps both sides untouched when both changed until a choice is made', () async {
    final repository = _Repository([9]);
    final provider = _Provider(
      document: SyncDocument(bytes: Uint8List.fromList([4]), revision: 'v2'),
    );
    final coordinator = SyncCoordinator(
      repository: repository,
      providerFactory: (_) async => provider,
      attachmentRepositoryFactory: (_) => _EmptyAttachments(),
    );

    final settings = await coordinator.synchronize(
      const AppSettings(
        syncProvider: SyncProviderType.directory,
        syncRevision: 'v1',
        syncLocalHash: 'old',
      ),
    );

    expect(settings.syncRevision, 'v1');
    expect(repository.container, [9]);
    expect(provider.written, isNull);
    expect(coordinator.hasPendingConflict, isTrue);
    expect(coordinator.status.phase, SyncPhase.conflict);
    expect(coordinator.status.message, contains('已暂停同步'));
  });

  test('uses remote data only after keepRemote conflict choice', () async {
    final repository = _Repository([9]);
    final provider = _Provider(
      document: SyncDocument(bytes: Uint8List.fromList([4]), revision: 'v2'),
    );
    final coordinator = SyncCoordinator(
      repository: repository,
      providerFactory: (_) async => provider,
      attachmentRepositoryFactory: (_) => _EmptyAttachments(),
    );

    await coordinator.synchronize(
      const AppSettings(
        syncProvider: SyncProviderType.directory,
        syncRevision: 'v1',
        syncLocalHash: 'old',
      ),
    );
    final resolved = await coordinator.resolveConflict(
      SyncConflictChoice.keepRemote,
    );

    expect(repository.container, [4]);
    expect(resolved.syncRevision, 'v2');
    expect(coordinator.hasPendingConflict, isFalse);
    expect(coordinator.status.requiresReload, isTrue);
  });

  test('uses local data only after keepLocal conflict choice', () async {
    final repository = _Repository([9]);
    final provider = _Provider(
      document: SyncDocument(bytes: Uint8List.fromList([4]), revision: 'v2'),
    );
    final coordinator = SyncCoordinator(
      repository: repository,
      providerFactory: (_) async => provider,
      attachmentRepositoryFactory: (_) => _EmptyAttachments(),
    );

    await coordinator.synchronize(
      const AppSettings(
        syncProvider: SyncProviderType.directory,
        syncRevision: 'v1',
        syncLocalHash: 'old',
      ),
    );
    final resolved = await coordinator.resolveConflict(
      SyncConflictChoice.keepLocal,
    );

    expect(provider.written, [9]);
    expect(provider.expectedRevision, 'v2');
    expect(resolved.syncRevision, 'v2');
    expect(coordinator.hasPendingConflict, isFalse);
    expect(coordinator.status.requiresReload, isFalse);
  });

  test('uploads a local-only change with the expected revision', () async {
    final repository = _Repository([9]);
    final provider = _Provider(
      document: SyncDocument(bytes: Uint8List.fromList([1]), revision: 'v1'),
    );
    final coordinator = SyncCoordinator(
      repository: repository,
      providerFactory: (_) async => provider,
      attachmentRepositoryFactory: (_) => _EmptyAttachments(),
    );

    final settings = await coordinator.synchronize(
      const AppSettings(
        syncProvider: SyncProviderType.directory,
        syncRevision: 'v1',
        syncLocalHash: 'old',
      ),
    );

    expect(provider.written, [9]);
    expect(provider.expectedRevision, 'v1');
    expect(settings.syncRevision, 'v1');
    expect(coordinator.status.phase, SyncPhase.success);
  });

  test('downloads existing remote data on first sync', () async {
    final repository = _Repository([1]);
    final provider = _Provider(
      document: SyncDocument(bytes: Uint8List.fromList([2]), revision: 'v1'),
    );
    final coordinator = SyncCoordinator(
      repository: repository,
      providerFactory: (_) async => provider,
      attachmentRepositoryFactory: (_) => _EmptyAttachments(),
    );

    final original = const AppSettings(
      syncProvider: SyncProviderType.directory,
    );
    final settings = await coordinator.synchronize(original);

    expect(settings.syncRevision, 'v1');
    expect(settings.syncLocalHash, isNotNull);
    expect(repository.container, [2]);
    expect(provider.written, isNull);
    expect(coordinator.status.phase, SyncPhase.success);
    expect(coordinator.status.message, '已下载远端数据');
  });

  test('reports provider failures without changing settings', () async {
    final coordinator = SyncCoordinator(
      repository: _Repository([1]),
      providerFactory: (_) async => _Provider(failure: '连接失败'),
      attachmentRepositoryFactory: (_) => _EmptyAttachments(),
    );
    final original = const AppSettings(
      syncProvider: SyncProviderType.directory,
    );

    final settings = await coordinator.synchronize(original);

    expect(settings, original);
    expect(coordinator.status.phase, SyncPhase.failure);
    expect(coordinator.status.message, '连接失败');
  });

  test('reports a write failure after a remote-empty check', () async {
    final coordinator = SyncCoordinator(
      repository: _Repository([1]),
      providerFactory: (_) async =>
          _Provider(writeFailure: 'WebDAV 请求超时'),
      attachmentRepositoryFactory: (_) => _EmptyAttachments(),
    );
    const settings = AppSettings(syncProvider: SyncProviderType.webdav);

    final result = await coordinator.synchronize(settings);

    expect(result, settings);
    expect(coordinator.status.phase, SyncPhase.failure);
    expect(coordinator.status.message, 'WebDAV 请求超时');
  });

  test('fails when provider initialization does not complete', () async {
    final pendingProvider = Completer<SyncProvider>();
    final coordinator = SyncCoordinator(
      repository: _Repository([1]),
      providerFactory: (_) => pendingProvider.future,
      attachmentRepositoryFactory: (_) => _EmptyAttachments(),
      providerInitializationTimeout: const Duration(milliseconds: 10),
    );
    const settings = AppSettings(syncProvider: SyncProviderType.webdav);

    final result = await coordinator.synchronize(settings);

    expect(result, settings);
    expect(coordinator.status.phase, SyncPhase.failure);
    expect(coordinator.status.message, '同步初始化超时，请检查系统安全存储后重试。');
  });

  test('ignores a concurrent synchronization request', () async {
    final connection = Completer<void>();
    final provider = _Provider(connection: connection.future);
    final coordinator = SyncCoordinator(
      repository: _Repository([1]),
      providerFactory: (_) async => provider,
      attachmentRepositoryFactory: (_) => _EmptyAttachments(),
    );
    final settings = const AppSettings(
      syncProvider: SyncProviderType.directory,
    );

    final first = coordinator.synchronize(settings);
    await Future<void>.delayed(Duration.zero);
    final second = await coordinator.synchronize(settings);
    connection.complete();
    await first;

    expect(second, settings);
    expect(provider.connectionChecks, 1);
    expect(provider.writeCount, 1);
  });
}

AttachmentData _projectAttachment() => AttachmentData(
  id: 'project-file',
  fileName: 'specification.pdf',
  storageKey: 'project-file.cardory-attachment',
  encryptionKey: 'key',
  size: 42,
  sha256: 'hash',
  createdAt: DateTime.utc(2026, 8, 20),
);

CardoryData _dataWithAttachment(AttachmentData attachment) => CardoryData(
  projects: [
    ProjectData(
      id: 'project-1',
      title: '项目',
      description: '',
      priority: ProjectPriority.p1,
      stage: ProjectStage.doing,
      progressEntries: const [],
      attachments: [attachment],
    ),
  ],
  todos: const [],
);

class _Repository implements CardoryRepository {
  _Repository(this.container, {CardoryData? data})
    : data = data ?? CardoryData.seed();

  List<int> container;
  final CardoryData data;
  AppSettings settings = const AppSettings();

  @override
  Future<List<int>> exportContainer() async => container;

  @override
  Future<String> saveSyncConflictSnapshot(
    List<int> bytes, {
    DateTime? timestamp,
  }) async => 'memory.conflict.cardory';

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {}

  @override
  Future<CardoryData> importContainer(
    List<int> bytes,
    AppSettings settings,
  ) async {
    container = List<int>.from(bytes);
    return data;
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    this.settings = settings;
  }

  @override
  Future<CardoryAccessState> accessState() async => CardoryAccessState.unlocked;

  @override
  Future<CardoryLoadResult> load() async =>
      CardoryLoadResult(data: data, settings: settings, path: 'memory');

  @override
  Future<void> save(CardoryData data, AppSettings settings) async {}

  @override
  Future<CardoryLoadResult> setup(String password) => load();

  @override
  Future<CardoryLoadResult> unlockWithPassword(String password) => load();

  @override
  Future<CardoryLoadResult> restoreFromBackup(
    List<int> bytes,
    String password,
  ) => load();
}

class _EmptyAttachments implements AttachmentRepository {
  @override
  Future<void> prune(Set<String> activeStorageKeys) async {}
  @override
  Future<String> createDownloadTarget(AttachmentData attachment) =>
      throw UnimplementedError();

  @override
  Future<void> delete(AttachmentData attachment) async {}

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

  @override
  Future<AttachmentData> migrateLegacy(AttachmentData attachment) async =>
      attachment;

  @override
  Future<bool> contains(AttachmentData attachment) async => false;
}

class _PresentAttachments extends _EmptyAttachments {
  final List<AttachmentData> installed = [];

  @override
  Future<bool> contains(AttachmentData attachment) async => true;

  @override
  String encryptedPath(AttachmentData attachment) =>
      'encrypted/${attachment.storageKey}';

  @override
  Future<String> createDownloadTarget(AttachmentData attachment) async =>
      'download/${attachment.storageKey}';

  @override
  Future<void> installEncrypted(
    AttachmentData attachment,
    String downloadedPath,
  ) async {
    installed.add(attachment);
  }
}

class _Provider implements SyncProvider, AttachmentSyncProvider {
  _Provider({
    this.document,
    this.failure,
    this.writeFailure,
    this.connection,
    this.remoteFilesExist = false,
  });

  SyncDocument? document;
  final String? failure;
  final String? writeFailure;
  final Future<void>? connection;
  final bool remoteFilesExist;
  List<int>? written;
  String? expectedRevision;
  int connectionChecks = 0;
  int writeCount = 0;
  bool disposed = false;
  final List<String> deleted = [];
  final List<(String, String)> uploaded = [];
  final List<(String, String)> downloaded = [];

  @override
  String get displayName => '测试';

  @override
  String get id => 'test';

  @override
  Future<void> checkConnection() async {
    connectionChecks++;
    if (failure != null) throw SyncProviderException(failure!);
    await connection;
  }

  @override
  Future<void> delete(String key, {String? expectedRevision}) async {
    deleted.add(key);
  }

  @override
  Future<void> dispose() async => disposed = true;

  @override
  Future<bool> fileExists(String key) async => remoteFilesExist;

  @override
  Future<void> downloadFile(String key, String targetPath) async {
    downloaded.add((key, targetPath));
  }

  @override
  Future<void> uploadFile(String key, String sourcePath) async {
    uploaded.add((key, sourcePath));
  }

  @override
  Future<SyncDocument?> read(String key) async => document;

  @override
  Future<SyncWriteResult> write(
    String key,
    List<int> bytes, {
    String? expectedRevision,
  }) async {
    writeCount++;
    if (writeFailure != null) throw SyncProviderException(writeFailure!);
    written = List<int>.from(bytes);
    this.expectedRevision = expectedRevision;
    return const SyncWriteResult(revision: 'v1');
  }
}
