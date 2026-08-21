import 'package:cardory/application/cardory_repository.dart';
import 'package:cardory/application/sync_credentials.dart';
import 'package:cardory/application/workspace_settings_service.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restores credentials when saving settings fails', () async {
    final credentials = _MemoryCredentials(
      const SyncCredentials(webDav: WebDavCredentials(password: 'old-password')),
    );
    final service = WorkspaceSettingsService(
      repository: _FailingSettingsRepository(),
      credentialStore: credentials,
    );

    await expectLater(
      service.apply(
        const AppSettings(syncProvider: SyncProviderType.s3),
        credentials: const SyncCredentialUpdate(
          s3: S3Credentials(accessKey: 'next-access', secretKey: 'next-secret'),
        ),
      ),
      throwsStateError,
    );

    expect((await credentials.read()).webDav?.password, 'old-password');
    expect((await credentials.read()).s3, isNull);
  });

  test('replaces the complete S3 key pair through one write', () async {
    final credentials = _MemoryCredentials(const SyncCredentials());
    final service = WorkspaceSettingsService(
      repository: _MemorySettingsRepository(),
      credentialStore: credentials,
    );

    await service.apply(
      const AppSettings(syncProvider: SyncProviderType.s3),
      credentials: const SyncCredentialUpdate(
        s3: S3Credentials(accessKey: 'access', secretKey: 'secret'),
      ),
    );

    expect((await credentials.read()).s3?.accessKey, 'access');
    expect((await credentials.read()).s3?.secretKey, 'secret');
    expect(credentials.writeCount, 1);
  });
}

class _MemoryCredentials implements SyncCredentialStore {
  _MemoryCredentials(this._value);

  SyncCredentials _value;
  int writeCount = 0;

  @override
  Future<SyncCredentials> read() async => _value;

  @override
  Future<void> write(SyncCredentials credentials) async {
    writeCount++;
    _value = credentials;
  }
}

class _MemorySettingsRepository implements WorkspaceRepository {
  @override
  Future<CardoryLoadResult> load() => throw UnimplementedError();

  @override
  Future<void> save(CardoryData data, AppSettings settings) async {}

  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

class _FailingSettingsRepository extends _MemorySettingsRepository {
  @override
  Future<void> saveSettings(AppSettings settings) =>
      Future<void>.error(StateError('disk unavailable'));
}
