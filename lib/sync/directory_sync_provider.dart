// 基于本地文件系统的同步提供者。
//
// 将加密容器读写到用户指定的本地目录，通过文件时间戳和大小构成的修订版本号
// 实现冲突检测。常用于 NAS 挂载目录或 USB 设备上的离线同步。

import 'dart:io';

import 'package:path/path.dart' as path;

import 'sync_models.dart';
import 'sync_provider.dart';

class DirectorySyncProvider implements SyncProvider, AttachmentSyncProvider {
  DirectorySyncProvider({required this.directory});

  final Directory directory;

  @override
  String get id => 'directory';

  @override
  String get displayName => '同步目录';

  @override
  Future<void> checkConnection() async {
    try {
      await directory.create(recursive: true);
      final probe = File(
        path.join(
          directory.path,
          '.cardory-sync-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await probe.writeAsString('', flush: true);
      await probe.delete();
    } on FileSystemException catch (error) {
      throw SyncProviderException('同步目录不可写', cause: error);
    }
  }

  @override
  Future<SyncDocument?> read(String key) async {
    final file = _fileFor(key);
    await _recoverTemporary(file);
    if (!await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      final stat = await file.stat();
      return SyncDocument(
        bytes: bytes,
        revision: _revision(stat),
        modifiedAt: stat.modified.toUtc(),
      );
    } on FileSystemException catch (error) {
      throw SyncProviderException('无法读取同步目录数据', cause: error);
    }
  }

  @override
  Future<SyncWriteResult> write(
    String key,
    List<int> bytes, {
    String? expectedRevision,
  }) async {
    try {
      await directory.create(recursive: true);
      final file = _fileFor(key);
      await file.parent.create(recursive: true);
      if (expectedRevision != null) {
        if (!await file.exists()) {
          throw const SyncConflictException('同步文件已被移除');
        }
        final currentRevision = _revision(await file.stat());
        if (currentRevision != expectedRevision) {
          throw const SyncConflictException('同步文件已被其他设备修改');
        }
      }
      final temporary = File('${file.path}.syncing');
      await temporary.writeAsBytes(bytes, flush: true);
      await _replaceFromTemporary(file, temporary);
      final stat = await file.stat();
      return SyncWriteResult(
        revision: _revision(stat),
        modifiedAt: stat.modified.toUtc(),
      );
    } on SyncConflictException {
      rethrow;
    } on FileSystemException catch (error) {
      throw SyncProviderException('无法写入同步目录数据', cause: error);
    }
  }

  @override
  Future<void> delete(String key, {String? expectedRevision}) async {
    final file = _fileFor(key);
    if (!await file.exists()) return;
    if (expectedRevision != null &&
        _revision(await file.stat()) != expectedRevision) {
      throw const SyncConflictException('同步文件已被其他设备修改');
    }
    try {
      await file.delete();
    } on FileSystemException catch (error) {
      throw SyncProviderException('无法删除同步目录数据', cause: error);
    }
  }

  @override
  Future<bool> fileExists(String key) async {
    final file = _fileFor(key);
    await _recoverTemporary(file);
    return file.exists();
  }

  @override
  Future<void> downloadFile(String key, String targetPath) async {
    final target = File(targetPath);
    final source = _fileFor(key);
    if (!await source.exists()) {
      throw const SyncProviderException('远端附件不存在');
    }
    await target.parent.create(recursive: true);
    await source.openRead().pipe(target.openWrite());
  }

  @override
  Future<void> uploadFile(String key, String sourcePath) async {
    final source = File(sourcePath);
    final target = _fileFor(key);
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.syncing');
    if (await temporary.exists()) await temporary.delete();
    await source.openRead().pipe(temporary.openWrite());
    await _replaceFromTemporary(target, temporary);
  }

  File _fileFor(String key) {
    final normalized = path.normalize(key);
    if (key.isEmpty ||
        path.isAbsolute(key) ||
        normalized == '..' ||
        normalized.startsWith('..${path.separator}')) {
      throw ArgumentError.value(key, 'key');
    }
    return File(path.join(directory.path, normalized));
  }

  Future<void> _replaceFromTemporary(File target, File temporary) async {
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      // Windows 无法覆盖重命名已有文件。临时文件保持持久化，
      // 该回退方案仅用于绕开此平台限制。
      if (!await target.exists()) rethrow;
      final backup = File('${target.path}.replace-backup');
      if (await backup.exists()) await backup.delete();
      await target.rename(backup.path);
      try {
        await temporary.rename(target.path);
        if (await backup.exists()) await backup.delete();
      } catch (_) {
        if (!await target.exists() && await backup.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }
    }
  }

  Future<void> _recoverTemporary(File target) async {
    if (await target.exists()) return;
    final temporary = File('${target.path}.syncing');
    if (await temporary.exists()) await _replaceFromTemporary(target, temporary);
  }

  String _revision(FileStat stat) =>
      '${stat.modified.toUtc().microsecondsSinceEpoch}:${stat.size}';

  @override
  Future<void> dispose() async {}
}
