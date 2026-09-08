import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../domain/cardory_models.dart';
import '../../domain/cardory_repository.dart';
import '../db/app_database.dart';
import '../db/database_session.dart';
import 'database_snapshot_applier.dart';
import 'sqlcipher_data_mapper.dart';

typedef RuntimeDirectoryProvider = Future<Directory> Function();

/// Runtime persistence for the breaking SQLCipher storage format.
///
/// This repository never reads or writes the legacy `.cardory` container. The
/// database file is the only source of truth; byte snapshots are encrypted
/// SQLCipher database copies used by the new sync/backup protocol.
class SqlCipherVaultStore
    implements
        CardoryRepository,
        VaultSessionRepository,
        SyncContainerInspector {
  SqlCipherVaultStore({
    RuntimeDirectoryProvider? directoryProvider,
    DatabaseSession? session,
  }) : _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory,
       _session = session ?? DatabaseSession();

  final RuntimeDirectoryProvider _directoryProvider;
  final DatabaseSession _session;
  String? _key;
  String? _databasePath;
  AppSettings _settings = const AppSettings();
  Future<void> _writes = Future<void>.value();

  AppDatabase? get database => _session.database;
  bool get isOpen => _session.isOpen;

  Future<File> _databaseFile() async {
    final directory = await _directoryProvider();
    final root = Directory(path.join(directory.path, 'Cardory'));
    await root.create(recursive: true);
    return File(path.join(root.path, 'cardory-runtime-v1.db'));
  }

  Future<CardoryData> _readData() async {
    final db = database;
    if (db == null) throw const CardoryStorageException('数据保险库尚未解锁。');
    return SqlCipherDataMapper(db).loadProjects().then((projects) async {
      final mapper = SqlCipherDataMapper(db);
      return CardoryData(
        projects: projects,
        todos: await mapper.loadTodos(),
        assets: await mapper.loadAssets(),
        assetTags: await mapper.loadAssetTags(),
      );
    });
  }

  Future<void> _replaceData(CardoryData data) async {
    final db = database;
    if (db == null) throw const CardoryStorageException('数据保险库尚未解锁。');
    // 行级增量对齐（单事务）：只写入与快照期望不一致的行，并对消失的可见行
    // 追加 tombstone；全部变更都会 append 完整 payload 的 sync_changes 审计。
    // 不再“物理全删 + 全量重插”，因此不会抹掉行级 Repository 已写入的
    // tombstone/时间语义，也不会为未变化的行刷 updatedAt。
    await DatabaseSnapshotApplier(db).apply(data);
  }

  Future<void> _writeSettings(AppSettings settings) async {
    final db = database;
    if (db == null) throw const CardoryStorageException('数据保险库尚未解锁。');
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.transaction(() async {
      for (final entry in settings.toJson().entries) {
        await db
            .into(db.settings)
            .insertOnConflictUpdate(
              SettingsCompanion.insert(
                key: entry.key,
                value: jsonEncode(entry.value),
                updatedAt: now,
              ),
            );
      }
    });
    _settings = settings;
  }

  Future<AppSettings> _readSettings() async {
    final db = database;
    if (db == null) throw const CardoryStorageException('数据保险库尚未解锁。');
    final rows = await db.select(db.settings).get();
    final values = <String, dynamic>{};
    for (final row in rows) {
      try {
        values[row.key] = jsonDecode(row.value);
      } catch (_) {
        values[row.key] = row.value;
      }
    }
    if (values.isEmpty) return _settings;
    return AppSettings.fromJson(values);
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _writes = _writes.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  Future<CardoryAccessState> accessState() async {
    if (isOpen) return CardoryAccessState.unlocked;
    final file = await _databaseFile();
    return await file.exists()
        ? CardoryAccessState.locked
        : CardoryAccessState.setupRequired;
  }

  @override
  Future<CardoryLoadResult> setup(String password) => _serialized(() async {
    if (password.isEmpty) {
      throw const CardoryStorageException('密码不能为空。');
    }
    final file = await _databaseFile();
    if (await file.exists()) {
      throw const CardoryStorageException('数据库已存在，请直接解锁。');
    }
    await _session.open(file, key: password);
    _key = password;
    _databasePath = file.path;
    _settings = const AppSettings();
    await _writeSettings(_settings);
    return CardoryLoadResult(
      data: const CardoryData.empty(),
      settings: _settings,
      path: file.path,
    );
  });

  @override
  Future<CardoryLoadResult> unlockWithPassword(String password) =>
      _serialized(() async {
        if (password.isEmpty) {
          throw const CardoryStorageException('密码不能为空。');
        }
        final file = await _databaseFile();
        if (!await file.exists()) {
          throw const CardoryStorageException('SQLCipher 数据库不存在。');
        }
        try {
          await _session.open(file, key: password);
        } catch (error) {
          // SQLCipher 打开失败统一归为「密码不正确或数据已损坏」，
          // 避免把底层异常直接抛给界面；保险库门禁据此清除已保存的密码。
          throw CardoryStorageException('解锁失败：密码不正确或数据文件已损坏。', error);
        }
        _key = password;
        _databasePath = file.path;
        _settings = await _readSettings();
        return CardoryLoadResult(
          data: await _readData(),
          settings: _settings,
          path: file.path,
        );
      });

  @override
  Future<CardoryLoadResult> load() async {
    final file = await _databaseFile();
    if (!isOpen) {
      throw const CardoryStorageException('数据保险库尚未解锁。');
    }
    _settings = await _readSettings();
    return CardoryLoadResult(
      data: await _readData(),
      settings: _settings,
      path: file.path,
    );
  }

  @override
  Future<void> save(CardoryData data, AppSettings settings) =>
      _serialized(() async {
        await _replaceData(data);
        await _writeSettings(settings);
      });

  @override
  Future<void> saveSettings(AppSettings settings) =>
      _serialized(() => _writeSettings(settings));

  @override
  Future<void> lock() => _serialized(() async {
    await _session.close();
    _key = null;
    _databasePath = null;
  });

  @override
  Future<void> changePassword(String currentPassword, String newPassword) =>
      _serialized(() async {
        final db = database;
        if (db == null || _key != currentPassword) {
          throw const CardoryStorageException('当前密码不正确。');
        }
        if (newPassword.isEmpty) {
          throw const CardoryStorageException('新密码不能为空。');
        }
        final escaped = newPassword.replaceAll("'", "''");
        await db.customStatement("PRAGMA rekey = '$escaped'");
        _key = newPassword;
      });

  @override
  Future<List<int>> exportContainer() => _serialized(() async {
    final db = database;
    final source = _databasePath;
    if (db == null || source == null) {
      throw const CardoryStorageException('数据保险库尚未解锁。');
    }
    final temporary = File('$source.snapshot.tmp');
    if (await temporary.exists()) await temporary.delete();
    final escaped = temporary.path.replaceAll("'", "''");
    await db.customStatement("VACUUM INTO '$escaped'");
    try {
      return await temporary.readAsBytes();
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  });

  @override
  Future<CardoryData> inspectContainer(List<int> bytes) async {
    final key = _key;
    if (key == null) throw const CardoryStorageException('数据保险库尚未解锁。');
    final directory = await _directoryProvider();
    final temporary = File(
      path.join(
        directory.path,
        'Cardory',
        '.snapshot-${DateTime.now().microsecondsSinceEpoch}.db',
      ),
    );
    await temporary.parent.create(recursive: true);
    await temporary.writeAsBytes(bytes, flush: true);
    final candidate = AppDatabase.encrypted(temporary, key: key);
    try {
      await candidate
          .customSelect('SELECT count(*) AS value FROM sqlite_master')
          .get();
      final mapper = SqlCipherDataMapper(candidate);
      return CardoryData(
        projects: await mapper.loadProjects(),
        todos: await mapper.loadTodos(),
        assets: await mapper.loadAssets(),
        assetTags: await mapper.loadAssetTags(),
      );
    } finally {
      await candidate.close();
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<String> saveSyncConflictSnapshot(
    List<int> bytes, {
    DateTime? timestamp,
  }) async {
    final directory = await _directoryProvider();
    final root = Directory(path.join(directory.path, 'Cardory', 'conflicts'));
    await root.create(recursive: true);
    final stamp = (timestamp ?? DateTime.now().toUtc())
        .toIso8601String()
        .replaceAll(':', '-');
    final file = File(path.join(root.path, 'snapshot-$stamp.db'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<CardoryData> importContainer(List<int> bytes, AppSettings settings) =>
      _serialized(() async {
        final key = _key;
        final source = _databasePath;
        if (key == null || source == null) {
          throw const CardoryStorageException('数据保险库尚未解锁。');
        }
        final directory = await _directoryProvider();
        final staging = File(
          path.join(
            directory.path,
            'Cardory',
            '.incoming-${DateTime.now().microsecondsSinceEpoch}.db',
          ),
        );
        await staging.writeAsBytes(bytes, flush: true);
        final candidate = AppDatabase.encrypted(staging, key: key);
        try {
          await candidate
              .customSelect('SELECT count(*) AS value FROM sqlite_master')
              .get();
        } finally {
          await candidate.close();
        }
        await _session.close();
        final target = File(source);
        final backup = File('$source.bak');
        if (await backup.exists()) await backup.delete();
        if (await target.exists()) await target.rename(backup.path);
        try {
          await staging.rename(target.path);
        } catch (_) {
          if (await backup.exists() && !await target.exists()) {
            await backup.rename(target.path);
          }
          rethrow;
        }
        await _session.open(target, key: key);
        _settings = settings;
        return await _readData();
      });

  @override
  Future<CardoryLoadResult> restoreFromBackup(
    List<int> bytes,
    String password,
  ) => _serialized(() async {
    final directory = await _directoryProvider();
    final staging = File(
      path.join(
        directory.path,
        'Cardory',
        '.restore-${DateTime.now().microsecondsSinceEpoch}.db',
      ),
    );
    await staging.writeAsBytes(bytes, flush: true);
    final candidate = AppDatabase.encrypted(staging, key: password);
    try {
      try {
        await candidate
            .customSelect('SELECT count(*) AS value FROM sqlite_master')
            .get();
      } catch (error) {
        throw CardoryStorageException('恢复失败：密码不正确或备份文件已损坏。', error);
      }
    } finally {
      await candidate.close();
    }
    final target = await _databaseFile();
    await _session.close();
    if (await target.exists()) {
      final backup = File('${target.path}.bak');
      if (await backup.exists()) await backup.delete();
      await target.rename(backup.path);
    }
    await staging.rename(target.path);
    await _session.open(target, key: password);
    _key = password;
    _databasePath = target.path;
    _settings = await _readSettings();
    return CardoryLoadResult(
      data: await _readData(),
      settings: _settings,
      path: target.path,
    );
  });
}
