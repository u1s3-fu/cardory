// Secure-storage adapters for synchronization and vault credentials.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../application/sync_credentials.dart';

export '../application/sync_credentials.dart';

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
  static const _s3AccessKey = 'cardory.current.sync.s3.access_key';
  static const _s3SecretKey = 'cardory.current.sync.s3.secret_key';
  static const _credentialsKey = 'cardory.current.sync.credentials.v1';
  final FlutterSecureStorage _storage;

  @override
  Future<SyncCredentials> read() async {
    final encoded = await _storage.read(key: _credentialsKey);
    if (encoded != null) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map) {
          return SyncCredentials.fromJson(Map<String, dynamic>.from(decoded));
        }
      } on FormatException {
        // Treat malformed secure storage as an empty aggregate. The next
        // successful settings save replaces it with valid JSON.
      }
      return const SyncCredentials();
    }
    final password = await _storage.read(key: _webDavPasswordKey);
    final token = await _storage.read(key: _selfHostedTokenKey);
    final access = await _storage.read(key: _s3AccessKey);
    final secret = await _storage.read(key: _s3SecretKey);
    return SyncCredentials(
      webDav: password == null ? null : WebDavCredentials(password: password),
      selfHostedToken: token,
      s3: access == null || secret == null
          ? null
          : S3Credentials(accessKey: access, secretKey: secret),
    );
  }

  @override
  Future<void> write(SyncCredentials credentials) async {
    await _storage.write(
      key: _credentialsKey,
      value: jsonEncode(credentials.toJson()),
    );
    await _storage.delete(key: _webDavPasswordKey);
    await _storage.delete(key: _selfHostedTokenKey);
    await _storage.delete(key: _s3AccessKey);
    await _storage.delete(key: _s3SecretKey);
  }
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
