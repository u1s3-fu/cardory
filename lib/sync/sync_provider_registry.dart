// 默认同步提供者工厂。
//
// 将具体的同步提供者创建逻辑从 [SyncCoordinator] 中分离出来，
// 通过工厂函数注入，实现依赖倒置。

import 'dart:io';

import '../domain/cardory_models.dart';
import 'directory_sync_provider.dart';
import 'self_hosted_api_sync_provider.dart';
import 's3_sync_provider.dart';
import 'sync_credentials.dart';
import 'sync_models.dart';
import 'sync_provider.dart';
import 'webdav_sync_provider.dart';

/// 创建一个默认的 [SyncProviderFactory]，根据 [AppSettings] 生成对应的同步提供者。
///
/// [credentialStore] 通过闭包捕获，由调用方在初始化时注入。
SyncProviderFactory defaultSyncProviderFactory(
  SyncCredentialStore credentialStore,
) {
  return (settings) async =>
      createSyncProvider(settings, await credentialStore.read());
}

/// 根据内存中的设置与凭据构造同步提供者，不持久化任何值。
/// 用于设置页的连接测试与常规工厂。
SyncProvider createSyncProvider(
  AppSettings settings,
  SyncCredentials credentials,
) {
  switch (settings.syncProvider) {
    case SyncProviderType.none:
      throw const SyncUnavailableException('尚未配置同步');
    case SyncProviderType.directory:
      if (settings.syncDirectoryPath.trim().isEmpty) {
        throw const SyncProviderException('请选择同步目录');
      }
      return DirectorySyncProvider(
        directory: Directory(settings.syncDirectoryPath.trim()),
      );
    case SyncProviderType.webdav:
      final uri = Uri.tryParse(settings.webDavUrl.trim());
      if (uri == null || !uri.hasScheme) {
        throw const SyncProviderException('WebDAV 地址无效');
      }
      if (credentials.webDav == null) {
        throw const SyncProviderException('WebDAV 密码尚未保存');
      }
      return WebDavSyncProvider(
        baseUrl: uri,
        username: settings.webDavUsername,
        password: credentials.webDav!.password,
      );
    case SyncProviderType.selfHosted:
      final uri = Uri.tryParse(settings.selfHostedUrl.trim());
      if (uri == null || !uri.hasScheme) {
        throw const SyncProviderException('自建服务地址无效');
      }
      return SelfHostedApiSyncProvider(
        endpoint: uri,
        credentialStore: _StaticCredentialStore(credentials),
      );
    case SyncProviderType.s3:
      final endpoint = Uri.tryParse(settings.s3Endpoint.trim());
      if (endpoint == null || !endpoint.hasScheme || endpoint.host.isEmpty) {
        throw const SyncProviderException('S3 Endpoint 地址无效');
      }
      if (settings.s3Bucket.trim().isEmpty) {
        throw const SyncProviderException('S3 存储桶不能为空');
      }
      if (settings.s3Region.trim().isEmpty) {
        throw const SyncProviderException('S3 区域不能为空');
      }
      if (credentials.s3 == null) {
        throw const SyncProviderException(
          'S3 Access Key / Secret Key 尚未保存',
        );
      }
      return S3SyncProvider(
        endpoint: endpoint,
        bucket: settings.s3Bucket.trim(),
        region: settings.s3Region.trim(),
        prefix: settings.s3Prefix,
        credentials: credentials.s3!,
      );
  }
}

/// 验证同步提供者能否认证并访问其远端端点。
/// 该验证刻意避免读取或写入 Cardory 文档。
Future<void> testSyncConnection(
  AppSettings settings,
  SyncCredentials credentials,
) async {
  final provider = createSyncProvider(settings, credentials);
    try {
      if (provider is WebDavSyncProvider) {
        await provider.checkConnectionStrict();
      } else {
        await provider.checkConnection();
      }
  } finally {
    await provider.dispose();
  }
}

class _StaticCredentialStore implements SyncCredentialStore {
  const _StaticCredentialStore(this.credentials);

  final SyncCredentials credentials;

  @override
  Future<SyncCredentials> read() async => credentials;

  @override
  Future<void> write(SyncCredentials credentials) async {}
}
