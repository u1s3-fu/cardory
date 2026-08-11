// 默认同步提供者工厂。
//
// 将具体的同步提供者创建逻辑从 [SyncCoordinator] 中分离出来，
// 通过工厂函数注入，实现依赖倒置。

import 'dart:io';

import '../domain/cardory_models.dart';
import 'directory_sync_provider.dart';
import 'self_hosted_api_sync_provider.dart';
import 'sync_coordinator.dart';
import 'sync_credentials.dart';
import 'sync_models.dart';
import 'webdav_sync_provider.dart';

/// 创建一个默认的 [SyncProviderFactory]，根据 [AppSettings] 生成对应的同步提供者。
///
/// [credentialStore] 通过闭包捕获，由调用方在初始化时注入。
SyncProviderFactory defaultSyncProviderFactory(SyncCredentialStore credentialStore) {
  return (AppSettings settings) async {
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
        final credentials = await credentialStore.readWebDav();
        if (credentials == null) {
          throw const SyncProviderException('WebDAV 密码尚未保存');
        }
        return WebDavSyncProvider(
          baseUrl: uri,
          username: settings.webDavUsername,
          password: credentials.password,
        );
      case SyncProviderType.selfHosted:
        final uri = Uri.tryParse(settings.selfHostedUrl.trim());
        if (uri == null || !uri.hasScheme) {
          throw const SyncProviderException('自建服务地址无效');
        }
        return SelfHostedApiSyncProvider(
          endpoint: uri,
          credentialStore: credentialStore,
        );
    }
  };
}
