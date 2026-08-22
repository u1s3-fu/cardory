import '../domain/cardory_models.dart';
import '../domain/sync_credentials.dart';

enum SettingsCategoryType { workspace, security, sync }

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
