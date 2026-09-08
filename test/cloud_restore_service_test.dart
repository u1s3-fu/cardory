import 'dart:typed_data';

import 'package:cardory/domain/attachment_repository.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/domain/cardory_repository.dart';
import 'package:cardory/sync/attachment_manifest.dart';
import 'package:cardory/sync/cloud_restore_service.dart';
import 'package:cardory/sync/sync_models.dart';
import 'package:cardory/sync/sync_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('skips attachment download when references are already local', () async {
    final key = 'file.cardory-attachment';
    final repository = _RecordingAttachmentRepository(present: {key});
    final provider = _FakeProvider();
    final service = _service(repository: repository, provider: provider);

    await service.restore(_backup(), 'password', config: _webDavConfig());

    expect(provider.downloadedKeys, isEmpty);
    expect(repository.installedKeys, isEmpty);
  });

  test('downloads cloud attachments into the restored store', () async {
    final repository = _RecordingAttachmentRepository(present: const {});
    final key = 'file.cardory-attachment';
    final provider = _FakeProvider(files: {attachmentFileKey(key): true});
    final service = _service(repository: repository, provider: provider);

    await service.restore(_backup(), 'password', config: _webDavConfig());

    expect(provider.downloadedKeys, [attachmentFileKey(key)]);
    expect(repository.installedKeys, [key]);
  });

  test(
    'fails closed when a referenced attachment is missing everywhere',
    () async {
      final repository = _RecordingAttachmentRepository(present: const {});
      final service = _service(
        repository: repository,
        provider: _FakeProvider(files: const {}),
      );

      await expectLater(
        service.restore(_backup(), 'password', config: _webDavConfig()),
        throwsA(
          isA<CloudRestoreException>().having(
            (error) => error.message,
            'message',
            contains('云端缺少附件'),
          ),
        ),
      );
    },
  );

  test('calls out references absent from the cloud manifest when the file is '
      'also missing', () async {
    final repository = _RecordingAttachmentRepository(present: const {});
    final service = _service(
      repository: repository,
      provider: _FakeProvider(
        files: const {},
        remoteManifest: AttachmentManifest.build(const []),
      ),
    );

    await expectLater(
      service.restore(_backup(), 'password', config: _webDavConfig()),
      throwsA(
        isA<CloudRestoreException>().having(
          (error) => error.message,
          'message',
          contains('不在云端附件清单中'),
        ),
      ),
    );
  });
}

CloudRestoreService _service({
  required _RecordingAttachmentRepository repository,
  required _FakeProvider provider,
}) => CloudRestoreService(
  vaultRepository: _FakeVaultRepository(_resultWithAttachment()),
  attachmentRepositoryFactory: (_) => repository,
  providerFactory: (_, _) => provider,
);

SyncDocument _backup() =>
    SyncDocument(bytes: Uint8List.fromList([1, 2, 3]), revision: 'v1');

CloudRestoreConfig _webDavConfig() => const CloudRestoreConfig(
  serviceType: CloudRestoreServiceType.webDav,
  webDavUrl: 'https://example.com/webdav',
  webDavPassword: 'password',
);

CardoryLoadResult _resultWithAttachment() => CardoryLoadResult(
  data: CardoryData(
    projects: [
      ProjectData(
        id: 'project-1',
        title: '项目',
        description: '',
        priority: ProjectPriority.p1,
        stage: ProjectStage.doing,
        progressEntries: const [],
        attachments: [_attachment()],
      ),
    ],
    todos: const [],
  ),
  settings: const AppSettings(),
  path: 'memory',
);

AttachmentData _attachment() => AttachmentData(
  id: 'file',
  fileName: 'specification.pdf',
  storageKey: 'file.cardory-attachment',
  encryptionKey: 'key',
  size: 42,
  sha256: 'hash',
  createdAt: DateTime.utc(2026, 8, 20),
);

class _FakeVaultRepository implements VaultRepository {
  _FakeVaultRepository(this.result);

  final CardoryLoadResult result;

  @override
  Future<CardoryAccessState> accessState() async => CardoryAccessState.unlocked;

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {}

  @override
  Future<CardoryLoadResult> restoreFromBackup(
    List<int> bytes,
    String password,
  ) async => result;

  @override
  Future<CardoryLoadResult> setup(String password) async => result;

  @override
  Future<CardoryLoadResult> unlockWithPassword(String password) async => result;
}

class _FakeProvider implements SyncProvider, AttachmentSyncProvider {
  _FakeProvider({this.files = const {}, this.remoteManifest});

  final Map<String, bool> files;
  final AttachmentManifest? remoteManifest;
  final List<String> downloadedKeys = [];
  bool disposed = false;

  @override
  Future<void> checkConnection() async {}

  @override
  Future<void> delete(String key, {String? expectedRevision}) async {}

  @override
  Future<void> dispose() async => disposed = true;

  @override
  Future<void> downloadFile(String key, String targetPath) async {
    downloadedKeys.add(key);
  }

  @override
  Future<void> uploadFile(String key, String sourcePath) async {}

  @override
  Future<bool> fileExists(String key) async => files[key] ?? false;

  @override
  String get id => 'test';

  @override
  String get displayName => '测试';

  @override
  Future<SyncDocument?> read(String key) async {
    final manifest = remoteManifest;
    if (key == attachmentManifestKey && manifest != null) {
      return SyncDocument(
        bytes: Uint8List.fromList(manifest.toBytes()),
        revision: 'v1',
      );
    }
    return null;
  }

  @override
  Future<SyncWriteResult> write(
    String key,
    List<int> bytes, {
    String? expectedRevision,
  }) async => SyncWriteResult(revision: 'v1');
}

class _RecordingAttachmentRepository implements AttachmentRepository {
  _RecordingAttachmentRepository({Iterable<String> present = const []})
    : present = {...present};

  final Set<String> present;
  final List<String> installedKeys = [];

  @override
  Future<bool> contains(AttachmentData attachment) async =>
      present.contains(attachment.storageKey);

  @override
  Future<String> createDownloadTarget(AttachmentData attachment) async =>
      'download/${attachment.storageKey}';

  @override
  Future<void> installEncrypted(
    AttachmentData attachment,
    String downloadedPath,
  ) async {
    installedKeys.add(attachment.storageKey);
    present.add(attachment.storageKey);
  }

  @override
  Future<void> delete(AttachmentData attachment) async {}

  @override
  Future<void> prune(Set<String> activeStorageKeys) async {}

  @override
  String encryptedPath(AttachmentData attachment) =>
      'encrypted/${attachment.storageKey}';

  @override
  Future<void> exportFile(AttachmentData attachment, String targetPath) async {}

  @override
  Future<Uint8List> readAttachmentBytes(AttachmentData attachment) async =>
      Uint8List(0);

  @override
  Future<AttachmentData> importFile({
    required String sourcePath,
    required String id,
    required String fileName,
    String mimeType = '',
    String note = '',
    DateTime? createdAt,
  }) => throw UnimplementedError();
}
