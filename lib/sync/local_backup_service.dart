// 本地加密备份服务。
//
// 备份包（.cardorybackup）是一个 zip 容器，内容全部为密文：
// - `cardory-backup-v1.db`：整库 SQLCipher 加密快照（exportContainer，
//   由保险库密码加密）；
// - `attachments/<storageKey>`：附件独立加密的密文文件原样拷贝（密钥
//   存于数据库内）。
// zip 本身不承担加密职责，只是把已加密内容打包成单文件便于保存与迁移。
//
// 恢复复用 [VaultRepository.restoreFromBackup]（先用备份创建时的密码
// 校验可解密性，校验通过才替换本地库），随后按恢复出的附件清单从包内
// 逐个安装密文（installEncrypted 校验摘要/长度），附件缺失时如实报
// 「恢复不完整」——与云端恢复同一 fail-closed 语义。
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;

import '../domain/attachment_repository.dart';
import '../domain/cardory_models.dart';
import '../domain/cardory_repository.dart';

/// 本地备份过程中出现的可恢复错误。
class LocalBackupException implements Exception {
  const LocalBackupException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// 导出结果：包文件名、纳入的附件数与缺失（未纳入）的附件名。
class LocalBackupExportResult {
  const LocalBackupExportResult({
    required this.fileName,
    required this.attachmentCount,
    required this.missingAttachmentNames,
  });

  final String fileName;
  final int attachmentCount;
  final List<String> missingAttachmentNames;

  bool get hasMissingAttachments => missingAttachmentNames.isNotEmpty;
}

/// 本地加密备份的导出与恢复。
class LocalBackupService {
  const LocalBackupService({
    required this.vaultRepository,
    this.attachmentRepositoryFactory,
  });

  /// 备份包内整库快照的固定条目名。
  static const databaseEntryName = 'cardory-backup-v1.db';

  /// 备份包内附件密文的条目前缀。
  static const attachmentsPrefix = 'attachments/';

  /// 备份包文件扩展名。
  static const fileExtension = '.cardorybackup';

  final VaultRepository vaultRepository;

  /// 附件仓库工厂（恢复时按恢复出的数据路径构造）。为空时不安装附件。
  final AttachmentRepositoryFactory? attachmentRepositoryFactory;

  static String backupFileName(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return 'cardory-backup-'
        '${at.year}${two(at.month)}${two(at.day)}'
        '-${two(at.hour)}${two(at.minute)}${two(at.second)}'
        '$fileExtension';
  }

  /// 导出到 [directoryPath]，返回包文件名与附件统计。
  ///
  /// 整库快照与全部附件密文打包为单个 zip；文件已不存在的附件跳过并
  /// 如实计入缺失（数据库是主体，不因个别附件缺失而中止导出）。
  /// [attachmentStore] 为 null 时仅打包数据库。
  Future<LocalBackupExportResult> exportToDirectory({
    required String directoryPath,
    AttachmentRepository? attachmentStore,
    List<AttachmentData> attachments = const [],
  }) async {
    final temporary = File(
      '${Directory.systemTemp.path}/cardory-backup-'
      '${DateTime.now().microsecondsSinceEpoch}.db',
    );
    final fileName = backupFileName(DateTime.now());
    final zipPath = path.join(directoryPath, fileName);
    final encoder = ZipFileEncoder();
    var opened = false;
    try {
      await temporary.writeAsBytes(await vaultRepository.exportContainer());
      await Directory(directoryPath).create(recursive: true);
      encoder.create(zipPath);
      opened = true;
      await encoder.addFile(temporary, databaseEntryName);
      final missing = <String>[];
      var included = 0;
      if (attachmentStore != null) {
        for (final attachment in attachments) {
          if (attachment.storageKey.isEmpty) continue;
          final source = File(attachmentStore.encryptedPath(attachment));
          if (!await source.exists()) {
            missing.add(attachment.fileName);
            continue;
          }
          await encoder.addFile(
            source,
            '$attachmentsPrefix${attachment.storageKey}',
          );
          included++;
        }
      }
      return LocalBackupExportResult(
        fileName: fileName,
        attachmentCount: included,
        missingAttachmentNames: missing,
      );
    } on LocalBackupException {
      rethrow;
    } catch (error) {
      if (await File(zipPath).exists()) {
        try {
          await File(zipPath).delete();
        } catch (_) {
          // 清理失败不掩盖原始错误。
        }
      }
      throw LocalBackupException('备份导出失败：$error', error);
    } finally {
      if (opened) {
        try {
          await encoder.close();
        } catch (_) {
          // 关闭失败不影响已写入内容。
        }
      }
      if (await temporary.exists()) {
        try {
          await temporary.delete();
        } catch (_) {
          // 临时快照清理失败不影响导出结果。
        }
      }
    }
  }

  /// 从备份包恢复。
  ///
  /// [password] 为创建该备份时使用的保险库密码。校验通过后整库替换本地
  /// 数据库，再按恢复出的附件清单从包内安装缺失的附件密文；包内缺少
  /// 附件时抛出「恢复不完整」（数据库已完成切换，可重试补齐）。
  Future<CardoryLoadResult> restore({
    required String archivePath,
    required String password,
  }) async {
    final inputStream = InputFileStream(archivePath);
    Archive archive;
    try {
      archive = ZipDecoder().decodeBuffer(inputStream);
    } catch (error) {
      await inputStream.close();
      throw LocalBackupException('无法读取备份文件，可能不是有效的备份包。', error);
    }
    try {
      final databaseEntry = archive.files
          .where((file) => file.isFile && file.name == databaseEntryName)
          .toList();
      if (databaseEntry.isEmpty) {
        throw const LocalBackupException('备份文件缺少数据库快照，可能不完整或已损坏。');
      }
      final CardoryLoadResult workspace;
      try {
        workspace = await vaultRepository.restoreFromBackup(
          databaseEntry.single.content as List<int>,
          password,
        );
      } catch (error) {
        throw LocalBackupException(
          error is CardoryStorageException ? error.message : '恢复失败：$error',
          error,
        );
      }
      final factory = attachmentRepositoryFactory;
      if (factory != null) {
        await _installAttachments(archive, workspace, factory);
      }
      return workspace;
    } finally {
      await inputStream.close();
    }
  }

  Future<void> _installAttachments(
    Archive archive,
    CardoryLoadResult workspace,
    AttachmentRepositoryFactory factory,
  ) async {
    final attachments = workspace.data.projects
        .expand((project) => project.attachments)
        .where((attachment) => attachment.storageKey.isNotEmpty)
        .toList();
    if (attachments.isEmpty) return;
    final store = factory(workspace.path);
    final entriesByName = {
      for (final file in archive.files)
        if (file.isFile && file.name.startsWith(attachmentsPrefix))
          file.name.substring(attachmentsPrefix.length): file,
    };
    final missing = <String>[];
    for (final attachment in attachments) {
      if (await store.contains(attachment)) continue;
      final entry = entriesByName[attachment.storageKey];
      if (entry == null) {
        missing.add(attachment.fileName);
        continue;
      }
      final temporary = File(
        '${Directory.systemTemp.path}/cardory-restore-'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        await temporary.writeAsBytes(entry.content as Uint8List);
        await store.installEncrypted(attachment, temporary.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }
    if (missing.isNotEmpty) {
      throw LocalBackupException(
        '备份缺少附件：${missing.join('、')}，恢复不完整。'
        '数据库已恢复；请改用包含完整附件的备份后重试。',
      );
    }
  }
}
