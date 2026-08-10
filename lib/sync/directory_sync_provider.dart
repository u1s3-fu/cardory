/// 基于本地文件系统的同步提供者。
///
/// 将加密容器读写到用户指定的本地目录，通过文件时间戳和大小构成的修订版本号
/// 实现冲突检测。常用于 NAS 挂载目录或 USB 设备上的离线同步。

import 'dart:io';

import 'package:path/path.dart' as path;

import 'sync_models.dart';
import 'sync_provider.dart';

class DirectorySyncProvider implements SyncProvider {
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
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
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

  String _revision(FileStat stat) =>
      '${stat.modified.toUtc().microsecondsSinceEpoch}:${stat.size}';
}
