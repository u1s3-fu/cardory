// 云端恢复服务。
//
// 首次启动时用于从 WebDAV / S3 云端存储恢复数据。
// 该服务在内存中构造同步提供者，验证连接、读取云端备份，
// 并复用 VaultRepository.restoreFromBackup 执行恢复，不污染本地配置。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/cardory_models.dart';
import '../domain/cardory_repository.dart';
import 'sync_coordinator.dart' show SyncCoordinator;
import 'sync_credentials.dart'
    show S3Credentials, SyncCredentials, WebDavCredentials;
import 'sync_models.dart' show SyncDocument, SyncProviderException;
import 'sync_provider.dart' show SyncProvider;
import 'sync_provider_registry.dart' show createSyncProvider;

/// 云端存储服务类型。
enum CloudRestoreServiceType { webDav, s3 }

/// 一条可恢复的云端备份。
class CloudBackupEntry {
  const CloudBackupEntry({
    required this.serviceType,
    required this.name,
    required this.size,
    this.modifiedAt,
  });

  final CloudRestoreServiceType serviceType;
  final String name;
  final int size;
  final DateTime? modifiedAt;

  String get sizeLabel => formatFileSize(size);
}

/// 云存储连接配置（供恢复向导现场填写，不会持久化）。
class CloudRestoreConfig {
  const CloudRestoreConfig({
    required this.serviceType,
    this.webDavUrl = '',
    this.webDavUsername = '',
    this.webDavPassword = '',
    this.s3Endpoint = '',
    this.s3Region = 'us-east-1',
    this.s3Bucket = '',
    this.s3Prefix = 'cardory',
    this.s3AccessKey = '',
    this.s3SecretKey = '',
  });

  final CloudRestoreServiceType serviceType;
  final String webDavUrl;
  final String webDavUsername;
  final String webDavPassword;
  final String s3Endpoint;
  final String s3Region;
  final String s3Bucket;
  final String s3Prefix;
  final String s3AccessKey;
  final String s3SecretKey;

  /// 将连接配置映射为同步类型对应的 [AppSettings]（不持久化）。
  AppSettings toSettings({AppSettings? base}) {
    final settings = base ?? const AppSettings();
    switch (serviceType) {
      case CloudRestoreServiceType.webDav:
        return settings.copyWith(
          syncProvider: SyncProviderType.webdav,
          webDavUrl: webDavUrl.trim(),
          webDavUsername: webDavUsername.trim(),
        );
      case CloudRestoreServiceType.s3:
        return settings.copyWith(
          syncProvider: SyncProviderType.s3,
          s3Endpoint: s3Endpoint.trim(),
          s3Region: s3Region.trim(),
          s3Bucket: s3Bucket.trim(),
          s3Prefix: s3Prefix.trim().isEmpty ? 'cardory' : s3Prefix.trim(),
        );
    }
  }

  SyncCredentials toCredentials() {
    switch (serviceType) {
      case CloudRestoreServiceType.webDav:
        return SyncCredentials(
          webDav: WebDavCredentials(password: webDavPassword),
        );
      case CloudRestoreServiceType.s3:
        return SyncCredentials(
          s3: S3Credentials(
            accessKey: s3AccessKey.trim(),
            secretKey: s3SecretKey.trim(),
          ),
        );
    }
  }
}

/// 云端恢复的结果：已下载的备份字节、配置与恢复后的工作区。
class CloudRestoreResult {
  const CloudRestoreResult({
    required this.backup,
    required this.settings,
    required this.workspace,
  });

  final SyncDocument backup;
  final AppSettings settings;
  final CardoryLoadResult workspace;
}

/// 云端恢复过程中出现的可恢复错误。
class CloudRestoreException implements Exception {
  const CloudRestoreException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// 云端数据恢复服务。
///
/// 在内存中创建同步提供者（不持久化）、验证连接、读取云端备份，
/// 并复用 [VaultRepository.restoreFromBackup] 执行恢复。
class CloudRestoreService {
  const CloudRestoreService({required this.vaultRepository});

  /// 云端数据文档的固定 key，与同步模块保持一致。
  static const documentKey = 'cardory-current-data.cardory';

  final VaultRepository vaultRepository;

  /// 检测本地是否已配置 WebDAV / S3 云存储。
  ///
  /// 返回已配置的服务类型列表（本地 settings 中存在非空配置即视为已配置）。
  Future<List<CloudRestoreServiceType>> detectConfiguredServices(
    AppSettings settings,
  ) async {
    final result = <CloudRestoreServiceType>[];
    if (settings.webDavUrl.trim().isNotEmpty) {
      result.add(CloudRestoreServiceType.webDav);
    }
    if (settings.s3Endpoint.trim().isNotEmpty &&
        settings.s3Bucket.trim().isNotEmpty) {
      result.add(CloudRestoreServiceType.s3);
    }
    return result;
  }

  /// 验证连接凭据并加载云端备份与配置。
  ///
  /// 在内存中构造同步提供者，先检查连接，再读取数据文档与配置文档。
  /// [existingSettings] 用于在 WebDAV / S3 已配置时继承既有地址等信息。
  Future<SyncDocument?> loadBackup(
    CloudRestoreConfig config, {
    AppSettings? existingSettings,
  }) async {
    final provider = await _createProvider(config, existingSettings);
    try {
      await _checkConnection(provider);
      try {
        return await provider.read(documentKey);
      } on SocketException catch (error) {
        throw CloudRestoreException('网络不可用，请检查网络连接。', error);
      } on TimeoutException catch (error) {
        throw CloudRestoreException('连接超时，请检查网络后重试。', error);
      } on SyncProviderException catch (error) {
        throw CloudRestoreException('读取备份失败：${error.message}', error);
      }
    } finally {
      await provider.dispose();
    }
  }

  /// 读取云端配置文档，返回其配置子集；云端不存在或解析失败时返回 null。
  ///
  /// 需在连接验证成功后的恢复流程中调用。
  Future<Map<String, dynamic>?> loadCloudConfig(
    CloudRestoreConfig config, {
    AppSettings? existingSettings,
  }) async {
    final provider = await _createProvider(config, existingSettings);
    try {
      final doc = await provider.read(SyncCoordinator.configKey);
      if (doc == null) return null;
      final json = jsonDecode(utf8.decode(doc.bytes)) as Map<String, dynamic>;
      final settings = json['settings'];
      if (settings is Map<String, dynamic>) return settings;
      return null;
    } on SocketException {
      return null;
    } on TimeoutException {
      return null;
    } on SyncProviderException {
      return null;
    } catch (_) {
      return null;
    } finally {
      await provider.dispose();
    }
  }

  /// 执行云端数据恢复。
  ///
  /// [backup] 为从云端下载的备份文档，[password] 为创建该备份时使用的密码，
  /// [config] 为本次恢复所选择的云存储连接配置，
  /// [cloudConfig] 为云端配置文档中的配置子集（可空）。
  /// 恢复成功后把云端配置与本次连接的 WebDAV / S3 配置合并回工作区设置，
  /// 便于后续继续同步并保持本地与云端配置一致。
  Future<CloudRestoreResult> restore(
    SyncDocument backup,
    String password, {
    required CloudRestoreConfig config,
    Map<String, dynamic>? cloudConfig,
  }) async {
    final workspace = await vaultRepository.restoreFromBackup(
      backup.bytes,
      password,
    );
    var base = workspace.settings;
    // 优先应用云端完整配置，再补齐本次连接所需的同步凭据配置。
    if (cloudConfig != null) {
      base = base.applySyncConfig(cloudConfig);
    }
    final mergedSettings = _mergeCloudConfig(base, config);
    return CloudRestoreResult(
      backup: backup,
      settings: mergedSettings,
      workspace: workspace,
    );
  }

  Future<SyncProvider> _createProvider(
    CloudRestoreConfig config,
    AppSettings? existingSettings,
  ) async {
    final settings = config.toSettings(base: existingSettings);
    final credentials = config.toCredentials();
    try {
      return createSyncProvider(settings, credentials);
    } on SyncProviderException catch (error) {
      throw CloudRestoreException(error.message, error.cause);
    }
  }

  Future<void> _checkConnection(SyncProvider provider) async {
    try {
      await provider.checkConnection();
    } on CloudRestoreException {
      rethrow;
    } on SocketException catch (error) {
      throw CloudRestoreException('网络不可用，请检查网络连接。', error);
    } on TimeoutException catch (error) {
      throw CloudRestoreException('连接超时，请检查网络后重试。', error);
    } on SyncProviderException catch (error) {
      throw CloudRestoreException('凭据无效或连接失败：${error.message}', error);
    } catch (error) {
      throw CloudRestoreException('无法连接到云存储：$error', error);
    }
  }

  AppSettings _mergeCloudConfig(
    AppSettings workspaceSettings,
    CloudRestoreConfig config,
  ) {
    // 用本次恢复所选择的云存储连接配置覆盖连接字段，其余配置（主题、行为等）
    // 保留工作区（可能来自云端配置）的既有值，便于后续继续同步。
    return config.toSettings(base: workspaceSettings);
  }
}
