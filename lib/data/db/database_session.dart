import 'dart:io';

import 'app_database.dart';

/// Owns the single SQLCipher database connection for an unlocked vault session.
///
/// The caller must provide an unlock-derived key and close the session before
/// clearing that key. It intentionally does not open a database on creation.
class DatabaseSession {
  AppDatabase? _database;

  AppDatabase? get database => _database;
  bool get isOpen => _database != null;

  Future<AppDatabase> open(File file, {required String key}) async {
    if (key.isEmpty) {
      throw ArgumentError.value(
        key,
        'key',
        'SQLCipher database key is required',
      );
    }
    final existing = _database;
    if (existing != null) return existing;

    await file.parent.create(recursive: true);
    final opened = AppDatabase.encrypted(file, key: key);
    try {
      await opened
          .customSelect('SELECT count(*) AS value FROM sqlite_master')
          .get();
      _database = opened;
      return opened;
    } catch (_) {
      await opened.close();
      rethrow;
    }
  }

  Future<void> close() async {
    final open = _database;
    _database = null;
    await open?.close();
  }
}
