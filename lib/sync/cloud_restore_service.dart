// 云端恢复服务。
//
// 首次启动时用于从 WebDAV / S3 云端存储恢复数据。
// 该服务在内存中构造同步提供者，验证连接、读取云端备份，
// 并复用 VaultRepository.restoreFromBackup 执行恢复，不污染本地配置。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/attachment_repository.dart';
import '../domain/cardory_models.dart';
import '../domain/cardory_repository.dart';
import 'attachment_manifest.dart';
import 'sync_coordinator.dart' show SyncCoordinator;
import 'sync_credentials.dart'
    show S3Credentials, SyncCredentials, WebDavCredentials;
import 'sync_models.dart' show SyncDocument, SyncProviderException;
import 'sync_provider.dart' show AttachmentSyncProvider, SyncProvider;
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
  const CloudRestoreService({
    required this.vaultRepository,
    this.attachmentRepositoryFactory,
    this.providerFactory,
  });

  /// 云端数据文档的固定 key，与同步模块保持一致。
  static const documentKey = 'cardory-snapshot-v2.db';

  final VaultRepository vaultRepository;

  /// 附件仓库工厂（与同步会话一致）。为空时恢复只重建数据库，不拉取附件。
  final AttachmentRepositoryFactory? attachmentRepositoryFactory;

  /// 同步提供者工厂。默认使用注册表的 [createSyncProvider]；测试可注入替身。
  final SyncProvider Function(
    AppSettings settings,
    SyncCredentials credentials,
  )?
  providerFactory;

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
  ///
  /// 数据库恢复后，会按恢复出的快照引用附件集合从云端拉取附件密文到
  /// 本地附件目录（`installEncrypted` 逐一做完整性校验）。附件缺失或校验
  /// 失败时抛出 [CloudRestoreException]——此时数据库已完成切换，可重试
  /// 恢复，或进入应用后触发一次同步补齐。
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
    final attachments = _attachmentsOf(workspace.data);
    final factory = attachmentRepositoryFactory;
    if (attachments.isNotEmpty && factory != null) {
      await _downloadAttachments(attachments, factory(workspace.path), config);
    }
    return CloudRestoreResult(
      backup: backup,
      settings: mergedSettings,
      workspace: workspace,
    );
  }

  List<AttachmentData> _attachmentsOf(CardoryData data) => data.projects
      .expand((project) => project.attachments)
      .where((attachment) => attachment.storageKey.isNotEmpty)
      .toList();

  /// 按快照引用附件集合把云端密文拉取到本地附件目录（单向、只下载不上传）。
  ///
  /// 云端附件清单（manifest）缺失或格式不支持时（更老版本云端），退化为按
  /// 快照引用逐一探测远端对象；读取到清单时，以清单为准做缺失判定。
  /// [store] 的 `installEncrypted` 会校验摘要/长度，失败即视为附件不完整。
  Future<void> _downloadAttachments(
    List<AttachmentData> attachments,
    AttachmentRepository store,
    CloudRestoreConfig config,
  ) async {
    final provider = await _createProvider(config, null);
    try {
      if (provider is! AttachmentSyncProvider) {
        throw const CloudRestoreException('当前云存储不支持恢复附件，请用支持的 WebDAV / S3 服务。');
      }
      final attachmentProvider = provider as AttachmentSyncProvider;
      // 尽力而为读取清单：仅当确实读到清单时才做清单级缺失判定。
      AttachmentManifest? manifest;
      try {
        final doc = await provider.read(attachmentManifestKey);
        manifest = doc == null ? null : AttachmentManifest.fromBytes(doc.bytes);
      } catch (_) {
        manifest = null;
      }
      final missing = <String>[];
      for (final attachment in attachments) {
        if (await store.contains(attachment)) continue;
        final key = attachmentFileKey(attachment.storageKey);
        if (!await attachmentProvider.fileExists(key)) {
          missing.add(
            manifest != null && !manifest.contains(attachment.storageKey)
                ? '${attachment.fileName}（不在云端附件清单中）'
                : attachment.fileName,
          );
          continue;
        }
        final target = await store.createDownloadTarget(attachment);
        await attachmentProvider.downloadFile(key, target);
        await store.installEncrypted(attachment, target);
      }
      if (missing.isNotEmpty) {
        throw CloudRestoreException(
          '云端缺少附件：${missing.join('、')}，恢复不完整。'
          '请确认该备份上传完整后重试，或进入应用后触发一次同步补齐。',
        );
      }
    } on CloudRestoreException {
      rethrow;
    } on SocketException catch (error) {
      throw CloudRestoreException('下载附件失败：网络不可用。', error);
    } on TimeoutException catch (error) {
      throw CloudRestoreException('下载附件失败：连接超时。', error);
    } on SyncProviderException catch (error) {
      throw CloudRestoreException('下载附件失败：${error.message}', error);
    } catch (error) {
      throw CloudRestoreException('下载附件失败：$error', error);
    } finally {
      await provider.dispose();
    }
  }

  Future<SyncProvider> _createProvider(
    CloudRestoreConfig config,
    AppSettings? existingSettings,
  ) async {
    final settings = config.toSettings(base: existingSettings);
    final credentials = config.toCredentials();
    try {
      final factory = providerFactory ?? createSyncProvider;
      return factory(settings, credentials);
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
