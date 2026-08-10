/// 数据持久化层：仓库接口与文件系统实现。
///
/// 定义 [CardoryRepository] 抽象接口（14 个方法：setup / unlock / save /
/// export / import / lock 等）、[VaultSessionRepository] 会话接口、
/// [CardoryLoadResult] 加载结果、[CardoryAccessState] 访问状态枚举，
/// 以及基于 `path_provider` 的文件系统实现 [CardoryStore]。

import 'dart:async';

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'cardory_container_codec.dart';
import '../domain/cardory_models.dart';

typedef DirectoryProvider = Future<Directory> Function();

class CardoryLoadResult {
  const CardoryLoadResult({
    required this.data,
    required this.settings,
    required this.path,
    this.recoveredFromBackup = false,
    this.recoveryKey,
  });
  final CardoryData data;
  final AppSettings settings;
  final String path;
  final bool recoveredFromBackup;
  final String? recoveryKey;
}

enum CardoryAccessState { setupRequired, locked, unlocked }

abstract interface class CardoryRepository {
  Future<CardoryAccessState> accessState();
  Future<CardoryLoadResult> setup(String password);
  Future<CardoryLoadResult> unlockWithPassword(String password);
  Future<CardoryLoadResult> unlockWithRecoveryKey(String recoveryKey);
  Future<CardoryLoadResult> resetPasswordWithRecoveryKey(
    String recoveryKey,
    String newPassword,
  );
  Future<CardoryLoadResult> restoreFromBackup(
    List<int> bytes,
    String recoveryKey,
    String newPassword,
  );
  Future<CardoryLoadResult> load();
  Future<void> save(CardoryData data, AppSettings settings);
  Future<void> saveSettings(AppSettings settings);
  Future<List<int>> exportContainer();
  Future<CardoryData> importContainer(List<int> bytes, AppSettings settings);
  Future<void> changePassword(String currentPassword, String newPassword);
  Future<String> exportRecoveryFile(String path, String recoveryKey);
}

class CardoryStorageException implements Exception {
  const CardoryStorageException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => message;
}

abstract interface class VaultSessionRepository {
  Future<void> lock();
}

class CardoryStore implements CardoryRepository, VaultSessionRepository {
  CardoryStore({
    DirectoryProvider? directoryProvider,
    CardoryContainerCodec? codec,
  }) : _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory,
       _codec = codec ?? CardoryContainerCodec();

  final DirectoryProvider _directoryProvider;
  final CardoryContainerCodec _codec;
  File? _file;
  AppSettings? _fileSettings;
  List<int>? _container;
  String? _password;
  String? _recoveryKey;
  Future<void> _writeQueue = Future<void>.value();

  @override
  Future<CardoryAccessState> accessState() async {
    if (_container != null) return CardoryAccessState.unlocked;
    final file = await _dataFile(await _loadSettings());
    return await file.exists()
        ? CardoryAccessState.locked
        : CardoryAccessState.setupRequired;
  }

  @override
  Future<void> lock() async {
    await _writeQueue;
    _container = null;
    _password = null;
    _recoveryKey = null;
  }

  @override
  Future<CardoryLoadResult> setup(String password) async {
    try {
      final settings = await _loadSettings();
      final file = await _dataFile(settings);
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
      _recoveryKey = null;
      return CardoryLoadResult(
        data: data,
        settings: settings,
        path: file.path,
        recoveryKey: creation.recoveryKey,
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
  Future<CardoryLoadResult> unlockWithRecoveryKey(String recoveryKey) =>
      _unlock(
        (bytes) => _codec.openDataWithRecoveryKey(bytes, recoveryKey),
        recoveryKey: recoveryKey,
      );

  @override
  Future<CardoryLoadResult> resetPasswordWithRecoveryKey(
    String recoveryKey,
    String newPassword,
  ) => _enqueueWrite(() async {
    try {
      final settings = await _loadSettings();
      final file = await _dataFile(settings);
      if (!await file.exists()) {
        throw const CardoryStorageException('加密数据文件不存在，请从备份恢复。');
      }
      final bytes = await file.readAsBytes();
      final recovered = await _codec.changePasswordWithRecoveryKey(
        bytes,
        recoveryKey: recoveryKey,
        newPassword: newPassword,
      );
      final data = await _codec.openDataWithPassword(recovered, newPassword);
      await _atomicWriteCredentialRotation(file, recovered);
      _container = recovered;
      _password = newPassword;
      _recoveryKey = null;
      return CardoryLoadResult(data: data, settings: settings, path: file.path);
    } catch (error) {
      if (error is CardoryStorageException) rethrow;
      throw CardoryStorageException('使用恢复码重设密码失败，原数据文件已保留。', error);
    }
  });

  @override
  Future<CardoryLoadResult> restoreFromBackup(
    List<int> bytes,
    String recoveryKey,
    String newPassword,
  ) => _enqueueWrite(() async {
    try {
      final settings = await _loadSettings();
      final recovered = await _codec.changePasswordWithRecoveryKey(
        bytes,
        recoveryKey: recoveryKey,
        newPassword: newPassword,
      );
      final data = await _codec.openDataWithPassword(recovered, newPassword);
      final file = await _dataFile(settings);
      await _atomicWriteBytes(file, recovered);
      _container = recovered;
      _password = newPassword;
      _recoveryKey = null;
      return CardoryLoadResult(data: data, settings: settings, path: file.path);
    } catch (error) {
      if (error is CardoryStorageException) rethrow;
      throw CardoryStorageException('备份恢复失败，原数据文件已保留。', error);
    }
  });

  Future<CardoryLoadResult> _unlock(
    Future<CardoryData> Function(List<int>) decrypt, {
    String? password,
    String? recoveryKey,
  }) async {
    try {
      final settings = await _loadSettings();
      final file = await _dataFile(settings);
      if (!await file.exists()) {
        throw const CardoryStorageException('加密数据文件不存在。');
      }
      final bytes = await file.readAsBytes();
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
        _recoveryKey = recoveryKey;
        return CardoryLoadResult(
          data: data,
          settings: settings,
          path: file.path,
          recoveredFromBackup: true,
        );
      }
      final data = await decrypt(bytes);
      _container = bytes;
      _password = password;
      _recoveryKey = recoveryKey;
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
    if (_password != null) return unlockWithPassword(_password!);
    return unlockWithRecoveryKey(_recoveryKey!);
  }

  @override
  Future<void> save(CardoryData data, AppSettings settings) =>
      _enqueueWrite(() async {
        try {
          final file = await _dataFile(settings);
          final container = _container;
          if (container == null) {
            throw const CardoryStorageException('数据保险库尚未解锁。');
          }
          final bytes = _password != null
              ? await _codec.updateDataWithPassword(container, data, _password!)
              : await _codec.updateDataWithRecoveryKey(
                  container,
                  data,
                  _recoveryKey!,
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
      _fileSettings = null;
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
  Future<CardoryData> importContainer(List<int> bytes, AppSettings settings) =>
      _enqueueWrite(() async {
        try {
          _codec.inspect(bytes);
          final data = _password != null
              ? await _codec.openDataWithPassword(bytes, _password!)
              : await _codec.openDataWithRecoveryKey(bytes, _recoveryKey!);
          await _atomicWriteBytes(await _dataFile(settings), bytes);
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
          await _atomicWriteCredentialRotation(
            await _dataFile(await _loadSettings()),
            bytes,
          );
          _container = bytes;
          _password = newPassword;
          _recoveryKey = null;
        } catch (error) {
          throw CardoryStorageException('密码修改失败，原数据文件已保留。', error);
        }
      });

  @override
  Future<String> exportRecoveryFile(String path, String recoveryKey) async {
    final container = _container;
    if (container == null) {
      throw const CardoryStorageException('数据保险库尚未解锁。');
    }
    await _codec.openDataWithRecoveryKey(container, recoveryKey);
    final target = File(
      path.toLowerCase().endsWith('.txt') ? path : '$path.txt',
    );
    await _atomicWrite(
      target,
      'Cardory 恢复码\n\n$recoveryKey\n\n请离线妥善保管。任何获得此恢复码的人都可以解锁或恢复你的数据。\n',
      preserveBackup: false,
      validate: (content) {
        if (!content.contains(recoveryKey)) {
          throw const FormatException('恢复文件校验失败');
        }
        return null;
      },
    );
    return target.path;
  }

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

  Future<File> _dataFile(AppSettings settings) async {
    if (_file != null && _fileSettings == settings) return _file!;
    final path = settings.dataPath.trim();
    if (path.isNotEmpty) {
      _file = File(path);
    } else {
      final directory = await _directoryProvider();
      final appDirectory = Directory(
        '${directory.path}${Platform.pathSeparator}Cardory',
      );
      await appDirectory.create(recursive: true);
      _file = File(
        '${appDirectory.path}${Platform.pathSeparator}cardory-current-data.cardory',
      );
    }
    await _file!.parent.create(recursive: true);
    _fileSettings = settings;
    return _file!;
  }
}
