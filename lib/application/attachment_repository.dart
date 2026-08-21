import '../domain/cardory_models.dart';

typedef AttachmentRepositoryFactory =
    AttachmentRepository Function(String dataFilePath);

/// Application-facing attachment storage boundary.
///
/// Callers work with attachment metadata and transfer files without depending
/// on the encrypted filesystem implementation in `data/`.
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
