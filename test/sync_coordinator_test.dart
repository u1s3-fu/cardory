import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:cardory/data/cardory_store.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/sync/sync_coordinator.dart';
import 'package:cardory/sync/sync_credentials.dart';
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
      credentialStore: _Credentials(),
      providerFactory: (_) async => provider,
    );

    final settings = await coordinator.synchronize(
      const AppSettings(syncProvider: SyncProviderType.directory),
    );

    expect(provider.written, [1, 2, 3]);
    expect(settings.syncRevision, 'v1');
    expect(settings.syncLocalHash, isNotNull);
    expect(coordinator.status.phase, SyncPhase.success);
  });

  test('downloads a remote-only change', () async {
    final repository = _Repository([1, 2, 3]);
    final provider = _Provider(
      document: SyncDocument(bytes: Uint8List.fromList([4, 5]), revision: 'v2'),
    );
    final hash = await Sha256().hash([1, 2, 3]);
    final coordinator = SyncCoordinator(
      repository: repository,
      credentialStore: _Credentials(),
      providerFactory: (_) async => provider,
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

  test('keeps both sides untouched when both changed', () async {
    final repository = _Repository([9]);
    final provider = _Provider(
      document: SyncDocument(bytes: Uint8List.fromList([4]), revision: 'v2'),
    );
    final coordinator = SyncCoordinator(
      repository: repository,
      credentialStore: _Credentials(),
      providerFactory: (_) async => provider,
    );

    await coordinator.synchronize(
      const AppSettings(
        syncProvider: SyncProviderType.directory,
        syncRevision: 'v1',
        syncLocalHash: 'old',
      ),
    );

    expect(repository.container, [9]);
    expect(provider.written, isNull);
    expect(coordinator.status.phase, SyncPhase.conflict);
  });

  test('uploads a local-only change with the expected revision', () async {
    final repository = _Repository([9]);
    final provider = _Provider(
      document: SyncDocument(bytes: Uint8List.fromList([1]), revision: 'v1'),
    );
    final coordinator = SyncCoordinator(
      repository: repository,
      credentialStore: _Credentials(),
      providerFactory: (_) async => provider,
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

  test('reports a conflict on first sync when remote data exists', () async {
    final repository = _Repository([1]);
    final provider = _Provider(
      document: SyncDocument(bytes: Uint8List.fromList([2]), revision: 'v1'),
    );
    final coordinator = SyncCoordinator(
      repository: repository,
      credentialStore: _Credentials(),
      providerFactory: (_) async => provider,
    );

    final original = const AppSettings(
      syncProvider: SyncProviderType.directory,
    );
    final settings = await coordinator.synchronize(original);

    expect(settings, original);
    expect(repository.container, [1]);
    expect(provider.written, isNull);
    expect(coordinator.status.phase, SyncPhase.conflict);
  });

  test('reports provider failures without changing settings', () async {
    final coordinator = SyncCoordinator(
      repository: _Repository([1]),
      credentialStore: _Credentials(),
      providerFactory: (_) async => _Provider(failure: '连接失败'),
    );
    final original = const AppSettings(
      syncProvider: SyncProviderType.directory,
    );

    final settings = await coordinator.synchronize(original);

    expect(settings, original);
    expect(coordinator.status.phase, SyncPhase.failure);
    expect(coordinator.status.message, '连接失败');
  });

  test('ignores a concurrent synchronization request', () async {
    final connection = Completer<void>();
    final provider = _Provider(connection: connection.future);
    final coordinator = SyncCoordinator(
      repository: _Repository([1]),
      credentialStore: _Credentials(),
      providerFactory: (_) async => provider,
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

class _Repository implements CardoryRepository {
  _Repository(this.container);

  List<int> container;
  AppSettings settings = const AppSettings();

  @override
  Future<List<int>> exportContainer() async => container;

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
    return CardoryData.seed();
  }

  @override
  Future<void> saveSettings(AppSettings settings) async {
    this.settings = settings;
  }

  @override
  Future<CardoryAccessState> accessState() async => CardoryAccessState.unlocked;

  @override
  Future<String> exportRecoveryFile(String path, String recoveryKey) async =>
      path;

  @override
  Future<CardoryLoadResult> load() async => CardoryLoadResult(
    data: CardoryData.seed(),
    settings: settings,
    path: 'memory',
  );

  @override
  Future<void> save(CardoryData data, AppSettings settings) async {}

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
}

class _Provider implements SyncProvider {
  _Provider({this.document, this.failure, this.connection});

  SyncDocument? document;
  final String? failure;
  final Future<void>? connection;
  List<int>? written;
  String? expectedRevision;
  int connectionChecks = 0;
  int writeCount = 0;

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
  Future<void> delete(String key, {String? expectedRevision}) async {}

  @override
  Future<SyncDocument?> read(String key) async => document;

  @override
  Future<SyncWriteResult> write(
    String key,
    List<int> bytes, {
    String? expectedRevision,
  }) async {
    writeCount++;
    written = List<int>.from(bytes);
    this.expectedRevision = expectedRevision;
    return const SyncWriteResult(revision: 'v1');
  }
}

class _Credentials implements SyncCredentialStore {
  @override
  Future<void> deleteSelfHostedToken() async {}

  @override
  Future<void> deleteWebDav() async {}

  @override
  Future<String?> readSelfHostedToken() async => null;

  @override
  Future<WebDavCredentials?> readWebDav() async => null;

  @override
  Future<void> writeSelfHostedToken(String token) async {}

  @override
  Future<void> writeWebDav(WebDavCredentials credentials) async {}
}
