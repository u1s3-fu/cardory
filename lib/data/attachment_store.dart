import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;

import '../application/attachment_repository.dart';
import '../domain/cardory_models.dart';

class AttachmentStorageException implements Exception {
  const AttachmentStorageException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class AttachmentStore implements AttachmentRepository {
  AttachmentStore({required Directory rootDirectory, Random? random})
    : _rootDirectory = rootDirectory,
      _random = random ?? Random.secure();

  factory AttachmentStore.forDataFile(String dataFilePath) => AttachmentStore(
    rootDirectory: Directory(
      path.join(path.dirname(dataFilePath), 'attachments', 'v1'),
    ),
  );

  static const int chunkSize = 1024 * 1024;
  static const _version = 1;
  static const _magic = <int>[67, 65, 82, 68, 65, 84, 84, 0];

  final Directory _rootDirectory;
  final Random _random;
  final AesGcm _aes = AesGcm.with256bits();

  @override
  Future<AttachmentData> importFile({
    required String sourcePath,
    required String id,
    required String fileName,
    String mimeType = '',
    String note = '',
    DateTime? createdAt,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const AttachmentStorageException('所选附件不存在或已被移动。');
    }
    final key = _randomBytes(32);
    final storageVersion = base64UrlEncode(_randomBytes(12));
    final storageKey = '$id-$storageVersion.cardory-attachment';
    final target = _fileFor(storageKey);
    final temporary = File('${target.path}.tmp');
    try {
      await target.parent.create(recursive: true);
      if (await temporary.exists()) await temporary.delete();
      final encrypted = await _encrypt(source, temporary, key);
      await _replaceFromTemporary(target, temporary);
      return AttachmentData(
        id: id,
        fileName: fileName,
        storageKey: storageKey,
        encryptionKey: base64UrlEncode(key),
        size: encrypted.length,
        sha256: encrypted.digest,
        mimeType: mimeType,
        note: note,
        createdAt: createdAt ?? DateTime.now(),
      );
    } catch (error) {
      if (await temporary.exists()) await temporary.delete();
      if (error is AttachmentStorageException) rethrow;
      throw AttachmentStorageException('无法加密保存附件：$fileName', error);
    }
  }

  @override
  Future<AttachmentData> migrateLegacy(AttachmentData attachment) async {
    final legacy = attachment.legacyFileBytes;
    if (legacy == null) return attachment;
    final temporarySource = File(
      path.join(
        _rootDirectory.path,
        '.legacy-${attachment.id}-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      await temporarySource.parent.create(recursive: true);
      await temporarySource.writeAsBytes(base64Decode(legacy), flush: true);
      return await importFile(
        sourcePath: temporarySource.path,
        id: attachment.id,
        fileName: attachment.fileName,
        mimeType: attachment.mimeType,
        note: attachment.note,
        createdAt: attachment.createdAt,
      );
    } on FormatException catch (error) {
      throw AttachmentStorageException(
        '旧附件 ${attachment.fileName} 的内容格式无效。',
        error,
      );
    } finally {
      if (await temporarySource.exists()) await temporarySource.delete();
    }
  }

  @override
  Future<void> exportFile(AttachmentData attachment, String targetPath) async {
    _validateStoredAttachment(attachment);
    final source = _fileFor(attachment.storageKey);
    if (!await source.exists()) {
      throw AttachmentStorageException('附件文件不存在：${attachment.fileName}');
    }
    final target = File(targetPath);
    final temporary = File('${target.path}.tmp');
    try {
      await target.parent.create(recursive: true);
      if (await temporary.exists()) await temporary.delete();
      await _decrypt(
        source,
        temporary,
        base64Url.decode(base64Url.normalize(attachment.encryptionKey)),
      );
      final digest = await crypto.sha256.bind(temporary.openRead()).first;
      if (digest.toString() != attachment.sha256 ||
          await temporary.length() != attachment.size) {
        throw const AttachmentStorageException('附件完整性校验失败。');
      }
      await _replaceFromTemporary(target, temporary);
    } catch (error) {
      if (await temporary.exists()) await temporary.delete();
      if (error is AttachmentStorageException) rethrow;
      throw AttachmentStorageException('无法导出附件：${attachment.fileName}', error);
    }
  }

  @override
  Future<void> delete(AttachmentData attachment) async {
    if (attachment.storageKey.isEmpty) return;
    final file = _fileFor(attachment.storageKey);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<bool> contains(AttachmentData attachment) async =>
      attachment.storageKey.isNotEmpty &&
      await _fileFor(attachment.storageKey).exists();

  @override
  String encryptedPath(AttachmentData attachment) {
    _validateStoredAttachment(attachment);
    return _fileFor(attachment.storageKey).path;
  }

  @override
  Future<void> installEncrypted(
    AttachmentData attachment,
    String downloadedPath,
  ) async {
    final downloaded = File(downloadedPath);
    _validateStoredAttachment(attachment);
    final target = _fileFor(attachment.storageKey);
    try {
      final verified = await _verifyEncrypted(
        downloaded,
        base64Url.decode(base64Url.normalize(attachment.encryptionKey)),
      );
      if (verified.digest != attachment.sha256 ||
          verified.length != attachment.size) {
        throw const AttachmentStorageException('同步附件完整性校验失败。');
      }
      await target.parent.create(recursive: true);
      await _replaceFromTemporary(target, downloaded);
    } finally {
      if (await downloaded.exists()) await downloaded.delete();
    }
  }

  @override
  Future<String> createDownloadTarget(AttachmentData attachment) async {
    _validateStoredAttachment(attachment);
    await _rootDirectory.create(recursive: true);
    final file = File('${_fileFor(attachment.storageKey).path}.downloading');
    if (await file.exists()) await file.delete();
    return file.path;
  }

  @override
  Future<void> prune(Set<String> activeStorageKeys) async {
    if (!await _rootDirectory.exists()) return;
    await for (final entity in _rootDirectory.list()) {
      if (entity is! File) continue;
      final name = path.basename(entity.path);
      if (name.endsWith('.tmp') ||
          name.endsWith('.downloading') ||
          name.startsWith('.legacy-')) {
        continue;
      }
      if (!activeStorageKeys.contains(name)) await entity.delete();
    }
  }

  Future<void> _replaceFromTemporary(File target, File temporary) async {
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
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

  Future<_AttachmentVerification> _encrypt(
    File source,
    File target,
    List<int> keyBytes,
  ) async {
    final input = await source.open();
    final output = await target.open(mode: FileMode.write);
    final digestSink = _DigestSink();
    final bytesSink = crypto.sha256.startChunkedConversion(digestSink);
    var length = 0;
    try {
      await output.writeFrom([..._magic, _version]);
      final key = SecretKey(keyBytes);
      while (true) {
        final chunk = await input.read(chunkSize);
        if (chunk.isEmpty) break;
        length += chunk.length;
        bytesSink.add(chunk);
        final nonce = _randomBytes(12);
        final box = await _aes.encrypt(chunk, secretKey: key, nonce: nonce);
        await output.writeFrom(_uint32(chunk.length));
        await output.writeFrom(nonce);
        await output.writeFrom(box.mac.bytes);
        await output.writeFrom(box.cipherText);
      }
      bytesSink.close();
      await output.flush();
      return _AttachmentVerification(
        digest: digestSink.value.toString(),
        length: length,
      );
    } finally {
      await input.close();
      await output.close();
    }
  }

  Future<void> _decrypt(File source, File target, List<int> keyBytes) async {
    final output = await target.open(mode: FileMode.write);
    try {
      await _readEncrypted(
        source,
        keyBytes,
        (plaintext) => output.writeFrom(plaintext),
      );
      await output.flush();
    } finally {
      await output.close();
    }
  }

  Future<_AttachmentVerification> _verifyEncrypted(
    File source,
    List<int> keyBytes,
  ) async {
    final digestSink = _DigestSink();
    final bytesSink = crypto.sha256.startChunkedConversion(digestSink);
    var length = 0;
    await _readEncrypted(source, keyBytes, (plaintext) {
      length += plaintext.length;
      bytesSink.add(plaintext);
    });
    bytesSink.close();
    return _AttachmentVerification(
      digest: digestSink.value.toString(),
      length: length,
    );
  }

  Future<void> _readEncrypted(
    File source,
    List<int> keyBytes,
    FutureOr<void> Function(List<int> plaintext) onChunk,
  ) async {
    final input = await source.open();
    try {
      final prefix = await _readExact(input, _magic.length + 1);
      if (prefix.length != _magic.length + 1 ||
          !_sameBytes(prefix.sublist(0, _magic.length), _magic) ||
          prefix.last != _version) {
        throw const AttachmentStorageException('附件加密格式无效。');
      }
      final key = SecretKey(keyBytes);
      while (await input.position() < await input.length()) {
        final lengthBytes = await _readExact(input, 4);
        if (lengthBytes.length != 4) {
          throw const AttachmentStorageException('附件数据已截断。');
        }
        final length = ByteData.sublistView(
          Uint8List.fromList(lengthBytes),
        ).getUint32(0, Endian.big);
        if (length <= 0 || length > chunkSize) {
          throw const AttachmentStorageException('附件分块长度无效。');
        }
        final nonce = await _readExact(input, 12);
        final mac = await _readExact(input, 16);
        final cipherText = await _readExact(input, length);
        if (nonce.length != 12 ||
            mac.length != 16 ||
            cipherText.length != length) {
          throw const AttachmentStorageException('附件数据已截断。');
        }
        final plaintext = await _aes.decrypt(
          SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
          secretKey: key,
        );
        await onChunk(plaintext);
      }
    } on SecretBoxAuthenticationError catch (error) {
      throw AttachmentStorageException('附件解密或完整性校验失败。', error);
    } finally {
      await input.close();
    }
  }

  Future<List<int>> _readExact(RandomAccessFile input, int length) async {
    final result = BytesBuilder(copy: false);
    while (result.length < length) {
      final bytes = await input.read(length - result.length);
      if (bytes.isEmpty) break;
      result.add(bytes);
    }
    return result.takeBytes();
  }

  File _fileFor(String storageKey) {
    if (storageKey.isEmpty ||
        path.isAbsolute(storageKey) ||
        path.basename(storageKey) != storageKey) {
      throw ArgumentError.value(storageKey, 'storageKey');
    }
    return File(path.join(_rootDirectory.path, storageKey));
  }

  void _validateStoredAttachment(AttachmentData attachment) {
    if (attachment.storageKey.isEmpty ||
        attachment.encryptionKey.isEmpty ||
        attachment.sha256.isEmpty) {
      throw const AttachmentStorageException('附件尚未完成独立加密迁移。');
    }
  }

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256), growable: false);

  Uint8List _uint32(int value) =>
      (ByteData(4)..setUint32(0, value, Endian.big)).buffer.asUint8List();

  bool _sameBytes(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }
}

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? _value;

  crypto.Digest get value => _value ?? (throw StateError('附件摘要尚未计算完成'));

  @override
  void add(crypto.Digest data) => _value = data;

  @override
  void close() {}
}

class _AttachmentVerification {
  const _AttachmentVerification({required this.digest, required this.length});

  final String digest;
  final int length;
}
