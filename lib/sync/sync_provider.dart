import 'sync_models.dart';

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
}
