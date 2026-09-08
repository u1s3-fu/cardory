// 设置（Settings）仓库。
//
// Settings 采用 KV 存储，同步走独立的配置文档协议（CloudConfigSync），因此
// 这里只负责本地持久化与 updatedAt，不生成 sync_changes 日志。
import '../db/app_database.dart';
import 'repository_support.dart';

class SettingsRepository {
  SettingsRepository(this._db, {Clock? clock}) : _clock = clock ?? nowUtcMillis;

  final AppDatabase _db;
  final Clock _clock;

  Future<Map<String, String>> readAll() async {
    final rows = await _db.select(_db.settings).get();
    return {for (final row in rows) row.key: row.value};
  }

  Future<String?> read(String key) async {
    final row = await (_db.select(
      _db.settings,
    )..where((row) => row.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// 单键 upsert。
  Future<void> write(String key, String value) => writeMany({key: value});

  /// 批量 upsert；键值均参与单次事务。
  Future<void> writeMany(Map<String, String> entries) async {
    if (entries.isEmpty) return;
    final now = _clock();
    await _db.transaction(() async {
      for (final entry in entries.entries) {
        await _db
            .into(_db.settings)
            .insertOnConflictUpdate(
              SettingsCompanion.insert(
                key: entry.key,
                value: entry.value,
                updatedAt: now,
              ),
            );
      }
    });
  }

  Future<void> delete(String key) async {
    await (_db.delete(_db.settings)..where((row) => row.key.equals(key))).go();
  }
}
