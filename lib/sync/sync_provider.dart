// 同步提供者的抽象接口定义。
//
// 所有同步后端（目录、WebDAV、自建服务、S3）均需实现 [SyncProvider] 接口，
// 支持连接检查、读取、写入和删除远端文档。

import '../domain/cardory_models.dart';
import 'sync_models.dart';

typedef SyncProviderFactory = Future<SyncProvider> Function(
  AppSettings settings,
);

abstract interface class SyncProvider {
  String get id;

  String get displayName;

  Future<void> checkConnection();

  Future<SyncDocument?> read(String key);

  Future<SyncWriteResult> write(
    String key,
    List<int> bytes, {
    String? expectedRevision,
  });

  Future<void> delete(String key, {String? expectedRevision});

  Future<void> dispose();
}

abstract interface class AttachmentSyncProvider {
  Future<bool> fileExists(String key);

  Future<void> downloadFile(String key, String targetPath);

  Future<void> uploadFile(String key, String sourcePath);
}
