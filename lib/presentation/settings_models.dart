import '../domain/cardory_models.dart';
import '../application/sync_credentials.dart';

enum SettingsCategoryType { workspace, security, sync, localData }

class SettingsResult {
  const SettingsResult({
    required this.settings,
    required this.credentials,
    required this.selfHostedToken,
    required this.s3,
  });

  final AppSettings settings;
  final WebDavCredentials credentials;
  final String selfHostedToken;
  final S3Credentials? s3;
}

class AssetDialogResult {
  const AssetDialogResult({required this.asset});

  final AssetData asset;
}

class PasswordChangeResult {
  const PasswordChangeResult({
    required this.currentPassword,
    required this.newPassword,
  });

  final String currentPassword;
  final String newPassword;
}
