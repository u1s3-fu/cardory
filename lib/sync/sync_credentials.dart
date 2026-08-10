import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class WebDavCredentials {
  const WebDavCredentials({required this.password});

  final String password;
}

abstract class SyncCredentialStore {
  Future<WebDavCredentials?> readWebDav();
  Future<void> writeWebDav(WebDavCredentials credentials);
  Future<void> deleteWebDav();
  Future<String?> readSelfHostedToken() async => null;
  Future<void> writeSelfHostedToken(String token) async {}
  Future<void> deleteSelfHostedToken() async {}
}

abstract interface class VaultCredentialStore {
  Future<String?> readPassword();
  Future<void> writePassword(String password);
  Future<void> deletePassword();
}

class SecureSyncCredentialStore implements SyncCredentialStore {
  SecureSyncCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _webDavPasswordKey = 'cardory.current.sync.webdav.password';
  static const _selfHostedTokenKey = 'cardory.current.sync.self_hosted.token';
  final FlutterSecureStorage _storage;

  @override
  Future<WebDavCredentials?> readWebDav() async {
    final password = await _storage.read(key: _webDavPasswordKey);
    return password == null ? null : WebDavCredentials(password: password);
  }

  @override
  Future<void> writeWebDav(WebDavCredentials credentials) =>
      _storage.write(key: _webDavPasswordKey, value: credentials.password);

  @override
  Future<void> deleteWebDav() => _storage.delete(key: _webDavPasswordKey);

  @override
  Future<String?> readSelfHostedToken() =>
      _storage.read(key: _selfHostedTokenKey);

  @override
  Future<void> writeSelfHostedToken(String token) =>
      _storage.write(key: _selfHostedTokenKey, value: token);

  @override
  Future<void> deleteSelfHostedToken() =>
      _storage.delete(key: _selfHostedTokenKey);
}

class SecureVaultCredentialStore implements VaultCredentialStore {
  SecureVaultCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _passwordKey = 'cardory.current.vault.password';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readPassword() => _storage.read(key: _passwordKey);

  @override
  Future<void> writePassword(String password) async {
    await _storage.write(key: _passwordKey, value: password);
    if (await _storage.read(key: _passwordKey) != password) {
      throw StateError('系统安全凭据保存失败。');
    }
  }

  @override
  Future<void> deletePassword() => _storage.delete(key: _passwordKey);
}
