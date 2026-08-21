import '../domain/cardory_models.dart';

typedef AttachmentRepositoryFactory =
    AttachmentRepository Function(String dataFilePath);

/// 面向应用的附件存储边界。
///
/// 调用方只需处理附件元数据并传输文件，
/// 无需依赖 `data/` 中加密文件系统的实现。
abstract interface class AttachmentRepository {
  Future<AttachmentData> importFile({
    required String sourcePath,
    required String id,
    required String fileName,
    String mimeType,
    String note,
    DateTime? createdAt,
  });

  Future<AttachmentData> migrateLegacy(AttachmentData attachment);

  Future<void> exportFile(AttachmentData attachment, String targetPath);

  Future<void> delete(AttachmentData attachment);

  Future<bool> contains(AttachmentData attachment);

  String encryptedPath(AttachmentData attachment);

  Future<void> installEncrypted(AttachmentData attachment, String downloadedPath);

  Future<String> createDownloadTarget(AttachmentData attachment);

  Future<void> prune(Set<String> activeStorageKeys);
}
