import '../domain/cardory_models.dart';
import '../domain/cardory_repository.dart';
import '../domain/sync_credentials.dart';

class SyncCredentialUpdate {
  const SyncCredentialUpdate({
    this.webDavPassword = '',
    this.selfHostedToken = '',
    this.s3,
  });

  final String webDavPassword;
  final String selfHostedToken;
  final S3Credentials? s3;
}

/// 将设置与凭据作为单个应用事务边界持久化。
class WorkspaceSettingsService {
  const WorkspaceSettingsService({
    required this.repository,
    required this.credentialStore,
  });

  final WorkspaceRepository repository;
  final SyncCredentialStore credentialStore;

  Future<void> apply(
    AppSettings settings, {
    SyncCredentialUpdate credentials = const SyncCredentialUpdate(),
  }) async {
    final previous = await credentialStore.read();
    final replacement = _replacementCredentials(previous, settings, credentials);
    await credentialStore.write(replacement);
    try {
      await repository.saveSettings(settings);
    } catch (_) {
      await credentialStore.write(previous);
      rethrow;
    }
  }

  SyncCredentials _replacementCredentials(
    SyncCredentials previous,
    AppSettings settings,
    SyncCredentialUpdate update,
  ) => switch (settings.syncProvider) {
    SyncProviderType.webdav => SyncCredentials(
      webDav: update.webDavPassword.isNotEmpty
          ? WebDavCredentials(password: update.webDavPassword)
          : previous.webDav,
    ),
    SyncProviderType.selfHosted => SyncCredentials(
      selfHostedToken: update.selfHostedToken.isNotEmpty
          ? update.selfHostedToken
          : previous.selfHostedToken,
    ),
    SyncProviderType.s3 => SyncCredentials(s3: update.s3 ?? previous.s3),
    SyncProviderType.none || SyncProviderType.directory => const SyncCredentials(),
  };
}
