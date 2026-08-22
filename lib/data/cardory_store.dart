// 数据持久化层：仓库接口与文件系统实现。
//
// 定义 [CardoryRepository] 抽象接口（setup / unlock / save / export /
// import / lock 等方法）、[VaultSessionRepository] 会话接口、
// [CardoryLoadResult] 加载结果、[CardoryAccessState] 访问状态枚举，
// 以及基于 `path_provider` 的文件系统实现 [CardoryStore]。
//
// 仅采用密码保存与密码加盐加密存储方案，不包含恢复码机制。

import 'dart:async';

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/cardory_repository.dart';
import 'cardory_container_codec.dart';
import '../domain/cardory_models.dart';

export '../domain/cardory_repository.dart';

typedef DirectoryProvider = Future<Directory> Function();

class CardoryStore implements CardoryRepository, VaultSessionRepository, SyncContainerInspector {
  CardoryStore({
    DirectoryProvider? directoryProvider,
    CardoryContainerCodec? codec,
  }) : _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory,
       _codec = codec ?? CardoryContainerCodec();

  final DirectoryProvider _directoryProvider;
  final CardoryContainerCodec _codec;
  File? _file;
  List<int>? _container;
  String? _password;
  Future<void> _writeQueue = Future<void>.value();

  @override
  Future<CardoryAccessState> accessState() async {
    if (_container != null) return CardoryAccessState.unlocked;
    final file = await _dataFile();
    return await file.exists()
        ? CardoryAccessState.locked
        : CardoryAccessState.setupRequired;
  }

  @override
  Future<void> lock() async {
    await _writeQueue;
    _container = null;
    _password = null;
  }

  @override
  Future<CardoryLoadResult> setup(String password) async {
    try {
      final settings = await _loadSettings();
      final file = await _dataFile();
      if (await file.exists()) {
        throw const CardoryStorageException('加密数据文件已存在，请直接解锁。');
      }
      const data = CardoryData.empty();
      final creation = await _codec.createFromData(
        data: data,
        password: password,
      );
      await _atomicWriteBytes(file, creation.bytes, preserveBackup: false);
      _container = creation.bytes;
      _password = password;
      return CardoryLoadResult(
        data: data,
        settings: settings,
        path: file.path,
      );
    } catch (error) {
      if (error is CardoryStorageException) rethrow;
      throw CardoryStorageException('无法创建加密数据文件：$error', error);
    }
  }

  @override
  Future<CardoryLoadResult> unlockWithPassword(String password) => _unlock(
    (bytes) => _codec.openDataWithPassword(bytes, password),
    password: password,
  );

  @override
  Future<CardoryLoadResult> restoreFromBackup(
    List<int> bytes,
    String password,
  ) => _enqueueWrite(() async {
    try {
      final settings = await _loadSettings();
      final data = await _codec.openDataWithPassword(bytes, password);
      final recovered = await _codec.createFromData(
        data: data,
        password: password,
      );
      final file = await _dataFile();
      await _atomicWriteBytes(file, recovered.bytes);
      _container = recovered.bytes;
      _password = password;
      return CardoryLoadResult(data: data, settings: settings, path: file.path);
    } catch (error) {
      if (error is CardoryStorageException) rethrow;
      throw CardoryStorageException('备份恢复失败，原数据文件已保留。', error);
    }
  });

  Future<CardoryLoadResult> _unlock(
    Future<CardoryData> Function(List<int>) decrypt, {
    required String password,
  }) async {
    try {
      final settings = await _loadSettings();
      final file = await _dataFile();
      var dataFile = file;
      if (!await dataFile.exists()) {
        final backup = File('${file.path}.bak');
        if (!await backup.exists()) {
          throw const CardoryStorageException('加密数据文件不存在。');
        }
        dataFile = backup;
      }
      if (!await dataFile.exists()) {
        throw const CardoryStorageException('加密数据文件不存在。');
      }
      final bytes = await dataFile.readAsBytes();
      try {
        _codec.inspect(bytes);
      } catch (_) {
        final backup = File('${file.path}.bak');
        if (!await backup.exists()) rethrow;
        final backupBytes = await backup.readAsBytes();
        final data = await decrypt(backupBytes);
        await _atomicWriteBytes(file, backupBytes, preserveBackup: false);
        _container = backupBytes;
        _password = password;
        return CardoryLoadResult(
          data: data,
          settings: settings,
          path: file.path,
          recoveredFromBackup: true,
        );
      }
      final data = await decrypt(bytes);
      if (dataFile.path != file.path) {
        await _atomicWriteBytes(file, bytes, preserveBackup: false);
      }
      _container = bytes;
      _password = password;
      return CardoryLoadResult(data: data, settings: settings, path: file.path);
    } catch (error) {
      if (error is CardoryStorageException) rethrow;
      throw CardoryStorageException(error.toString(), error);
    }
  }

  @override
  Future<CardoryLoadResult> load() async {
    if (_container == null) {
      throw const CardoryStorageException('数据保险库尚未解锁。');
    }
    if (_password == null) {
      throw const CardoryStorageException('数据保险库缺少密码，请重新解锁。');
    }
    return unlockWithPassword(_password!);
  }

  @override
  Future<void> save(CardoryData data, AppSettings settings) =>
      _enqueueWrite(() async {
        try {
          final file = await _dataFile();
          final container = _container;
          if (container == null) {
            throw const CardoryStorageException('数据保险库尚未解锁。');
          }
          final bytes = await _codec.updateDataWithPassword(
            container,
            data,
            _password!,
          );
          _codec.inspect(bytes);
          await _atomicWriteBytes(file, bytes);
          _container = bytes;
        } catch (error) {
          throw CardoryStorageException('保存失败，原数据文件已保留。', error);
        }
      });

  @override
  Future<void> saveSettings(AppSettings settings) => _enqueueWrite(() async {
    try {
      final file = await _settingsFile();
      await _atomicWrite(
        file,
        const JsonEncoder.withIndent('  ').convert(settings.toJson()),
        validate: (content) =>
            AppSettings.fromJson(jsonDecode(content) as Map<String, dynamic>),
      );
      _file = null;
    } catch (error) {
      throw CardoryStorageException('设置保存失败，原设置已保留。', error);
    }
  });

  @override
  Future<List<int>> exportContainer() async {
    final container = _container;
    if (container == null) {
      throw const CardoryStorageException('数据保险库尚未解锁。');
    }
    return List<int>.unmodifiable(container);
  }

  @override
  Future<String> saveSyncConflictSnapshot(
    List<int> bytes, {
    DateTime? timestamp,
  }) => _enqueueWrite(() async {
    try {
      _codec.inspect(bytes);
      final dataFile = await _dataFile();
      final instant = (timestamp ?? DateTime.now()).toUtc();
      final stamp = instant.toIso8601String().replaceAll(':', '-');
      final snapshot = File('${dataFile.path}.conflict-$stamp.cardory');
      await snapshot.writeAsBytes(bytes, flush: true);
      return snapshot.path;
    } catch (error) {
      throw CardoryStorageException('无法保存同步冲突快照：$error', error);
    }
  });

  @override
  Future<CardoryData> inspectContainer(List<int> bytes) async {
    try {
      _codec.inspect(bytes);
      return await _codec.openDataWithPassword(bytes, _password!);
    } catch (error) {
      throw CardoryStorageException('同步数据无法验证。', error);
    }
  }

  @override
  Future<CardoryData> importContainer(List<int> bytes, AppSettings settings) =>
      _enqueueWrite(() async {
        try {
          _codec.inspect(bytes);
          final data = await _codec.openDataWithPassword(bytes, _password!);
          await _atomicWriteBytes(await _dataFile(), bytes);
          _container = List<int>.from(bytes);
          return data;
        } catch (error) {
          throw CardoryStorageException('同步数据无法验证，原数据文件已保留。', error);
        }
      });

  @override
  Future<void> changePassword(String currentPassword, String newPassword) =>
      _enqueueWrite(() async {
        final container = _container;
        if (container == null) {
          throw const CardoryStorageException('数据保险库尚未解锁。');
        }
        try {
          final bytes = await _codec.changePassword(
            container,
            currentPassword: currentPassword,
            newPassword: newPassword,
          );
          await _atomicWriteCredentialRotation(await _dataFile(), bytes);
          _container = bytes;
          _password = newPassword;
        } catch (error) {
          throw CardoryStorageException('密码修改失败，原数据文件已保留。', error);
        }
      });

  Future<T> _enqueueWrite<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<AppSettings> _loadSettings() async {
    final file = await _settingsFile();
    if (!await file.exists()) return const AppSettings();
    try {
      return AppSettings.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } catch (_) {
      final backup = File('${file.path}.bak');
      if (!await backup.exists()) rethrow;
      return AppSettings.fromJson(
        jsonDecode(await backup.readAsString()) as Map<String, dynamic>,
      );
    }
  }

  Future<void> _atomicWrite(
    File target,
    String content, {
    bool preserveBackup = true,
    Object? Function(String content)? validate,
  }) async {
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    if (await temporary.exists()) await temporary.delete();
    await temporary.writeAsString(content, flush: true);
    final writtenContent = await temporary.readAsString();
    validate?.call(writtenContent);
    if (preserveBackup && await target.exists()) {
      if (await backup.exists()) await backup.delete();
      await target.rename(backup.path);
    } else if (await target.exists()) {
      await target.delete();
    }
    try {
      await temporary.rename(target.path);
    } catch (_) {
      if (preserveBackup && await backup.exists() && !await target.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
  }

  Future<void> _atomicWriteBytes(
    File target,
    List<int> content, {
    bool preserveBackup = true,
  }) async {
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    if (await temporary.exists()) await temporary.delete();
    await temporary.writeAsBytes(content, flush: true);
    _codec.inspect(await temporary.readAsBytes());
    if (preserveBackup && await target.exists()) {
      if (await backup.exists()) await backup.delete();
      await target.rename(backup.path);
    } else if (await target.exists()) {
      await target.delete();
    }
    try {
      await temporary.rename(target.path);
    } catch (_) {
      if (preserveBackup && await backup.exists() && !await target.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
  }

  Future<void> _atomicWriteCredentialRotation(
    File target,
    List<int> content,
  ) async {
    await _atomicWriteBytes(target, content);
    final backup = File('${target.path}.bak');
    try {
      await _atomicWriteBytes(backup, content, preserveBackup: false);
    } catch (_) {
      if (await backup.exists()) await backup.delete();
    }
  }

  Future<File> _settingsFile() async {
    final directory = await _directoryProvider();
    final appDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}Cardory',
    );
    await appDirectory.create(recursive: true);
    return File(
      '${appDirectory.path}${Platform.pathSeparator}cardory-current-settings.json',
    );
  }

  Future<File> _dataFile() async {
    if (_file != null) return _file!;
    final directory = await _directoryProvider();
    final appDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}Cardory',
    );
    await appDirectory.create(recursive: true);
    _file = File(
      '${appDirectory.path}${Platform.pathSeparator}cardory-current-data.cardory',
    );
    await _file!.parent.create(recursive: true);
    return _file!;
  }
}
