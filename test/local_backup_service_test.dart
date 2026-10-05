// LocalBackupService 的测试：备份包结构（数据库快照 + 附件密文）、
// 导出缺失统计、恢复密码校验与附件 fail-closed 安装。

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:cardory/data/attachment_store.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/domain/cardory_repository.dart';
import 'package:cardory/sync/local_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

const _correctPassword = 'vault-pass-123';

class _FakeVaultRepository implements VaultRepository {
  _FakeVaultRepository({required this.restored});

  static const fakeDatabaseBytes = 'fake-sqlcipher-snapshot-bytes';

  final CardoryLoadResult restored;
  List<int>? lastRestoreBytes;
  String? lastRestorePassword;

  @override
  Future<List<int>> exportContainer() async => utf8.encode(fakeDatabaseBytes);

  @override
  Future<CardoryLoadResult> restoreFromBackup(
    List<int> bytes,
    String password,
  ) async {
    if (password != _correctPassword) {
      throw const CardoryStorageException('恢复失败：密码不正确或备份文件已损坏。');
    }
    lastRestoreBytes = bytes;
    lastRestorePassword = password;
    return restored;
  }

  @override
  Future<CardoryAccessState> accessState() async => CardoryAccessState.unlocked;

  @override
  Future<CardoryLoadResult> setup(String password) =>
      throw UnimplementedError();

  @override
  Future<CardoryLoadResult> unlockWithPassword(String password) =>
      throw UnimplementedError();

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {}
}

void main() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('cardory-backup-test');
  });
  tearDown(() async {
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  // 在临时目录导入一个真实附件（经 AttachmentStore 独立加密）。
  Future<({AttachmentData attachment, AttachmentStore store})> importAttachment(
    String id,
  ) async {
    final store = AttachmentStore(
      rootDirectory: Directory(path.join(workspace.path, 'attachments-$id')),
    );
    final source = File(path.join(workspace.path, '$id-source.txt'));
    await source.writeAsString('attachment-content-$id');
    final attachment = await store.importFile(
      sourcePath: source.path,
      id: id,
      fileName: '$id.txt',
    );
    return (attachment: attachment, store: store);
  }

  CardoryLoadResult resultWith(AttachmentData attachment) => CardoryLoadResult(
    data: CardoryData(
      projects: [
        ProjectData(
          id: 'p1',
          title: '项目一',
          description: '',
          priority: ProjectPriority.p1,
          stage: ProjectStage.planned,
          progressEntries: const [],
          attachments: [attachment],
        ),
      ],
      todos: const [],
    ),
    settings: const AppSettings(),
    path: path.join(workspace.path, 'restored', 'cardory-runtime-v1.db'),
  );

  test('导出：包内包含数据库快照条目与附件密文条目', () async {
    final (:attachment, :store) = await importAttachment('a1');
    final vault = _FakeVaultRepository(restored: resultWith(attachment));
    final service = LocalBackupService(vaultRepository: vault);
    final targetDir = path.join(workspace.path, 'out');

    final result = await service.exportToDirectory(
      directoryPath: targetDir,
      attachmentStore: store,
      attachments: [attachment],
    );

    expect(result.hasMissingAttachments, isFalse);
    expect(result.attachmentCount, 1);
    expect(result.fileName, endsWith(LocalBackupService.fileExtension));

    final zipPath = path.join(targetDir, result.fileName);
    final archive = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
    final databaseEntry = archive.findFile(
      LocalBackupService.databaseEntryName,
    );
    expect(
      utf8.decode(databaseEntry!.content as List<int>),
      _FakeVaultRepository.fakeDatabaseBytes,
    );
    final attachmentEntry = archive.findFile(
      '${LocalBackupService.attachmentsPrefix}${attachment.storageKey}',
    );
    expect(attachmentEntry, isNotNull);
    // 附件密文与本地存储的密文文件逐字节一致（原样打包，不重复加密）。
    final stored = File(store.encryptedPath(attachment));
    expect(attachmentEntry!.content as List<int>, stored.readAsBytesSync());
  });

  test('导出：文件缺失的附件计入缺失且不中止导出', () async {
    final (:attachment, :store) = await importAttachment('a1');
    await File(store.encryptedPath(attachment)).delete();
    final vault = _FakeVaultRepository(restored: resultWith(attachment));
    final service = LocalBackupService(vaultRepository: vault);
    final targetDir = path.join(workspace.path, 'out');

    final result = await service.exportToDirectory(
      directoryPath: targetDir,
      attachmentStore: store,
      attachments: [attachment],
    );

    expect(result.attachmentCount, 0);
    expect(result.missingAttachmentNames, ['a1.txt']);
    final archive = ZipDecoder().decodeBytes(
      File(path.join(targetDir, result.fileName)).readAsBytesSync(),
    );
    expect(archive.findFile(LocalBackupService.databaseEntryName), isNotNull);
  });

  test('恢复：密码错误被包装为本地备份异常', () async {
    final vault = _FakeVaultRepository(restored: resultWith(_bareAttachment()));
    final service = LocalBackupService(vaultRepository: vault);
    final zipPath = await _writeArchive(workspace, {
      LocalBackupService.databaseEntryName: utf8.encode(
        _FakeVaultRepository.fakeDatabaseBytes,
      ),
    });

    await expectLater(
      service.restore(archivePath: zipPath, password: 'wrong-pass'),
      throwsA(
        isA<LocalBackupException>().having(
          (error) => error.message,
          'message',
          contains('密码不正确'),
        ),
      ),
    );
  });

  test('恢复：数据库快照写入 restoreFromBackup，附件密文安装到本地目录', () async {
    final (:attachment, :store) = await importAttachment('a1');
    final vault = _FakeVaultRepository(restored: resultWith(attachment));
    final service = LocalBackupService(
      vaultRepository: vault,
      attachmentRepositoryFactory: (_) => AttachmentStore(
        rootDirectory: Directory(path.join(workspace.path, 'restore-target')),
      ),
    );
    final zipPath = await _writeArchive(workspace, {
      LocalBackupService.databaseEntryName: utf8.encode(
        _FakeVaultRepository.fakeDatabaseBytes,
      ),
      '${LocalBackupService.attachmentsPrefix}${attachment.storageKey}': File(
        store.encryptedPath(attachment),
      ).readAsBytesSync(),
    });

    final restored = await service.restore(
      archivePath: zipPath,
      password: _correctPassword,
    );

    expect(vault.lastRestorePassword, _correctPassword);
    expect(
      utf8.decode(vault.lastRestoreBytes!),
      _FakeVaultRepository.fakeDatabaseBytes,
    );
    final targetStore = AttachmentStore(
      rootDirectory: Directory(path.join(workspace.path, 'restore-target')),
    );
    expect(await targetStore.contains(attachment), isTrue);
    // 安装后的附件可解密导出回原文内容。
    final exported = File(path.join(workspace.path, 'exported-a1.txt'));
    await targetStore.exportFile(attachment, exported.path);
    expect(exported.readAsStringSync(), 'attachment-content-a1');
    expect(restored.path, isNotEmpty);
  });

  test('恢复：包内缺少附件时如实报告恢复不完整', () async {
    final (:attachment, :store) = await importAttachment('a1');
    final vault = _FakeVaultRepository(restored: resultWith(attachment));
    final service = LocalBackupService(
      vaultRepository: vault,
      attachmentRepositoryFactory: (_) => AttachmentStore(
        rootDirectory: Directory(path.join(workspace.path, 'restore-target')),
      ),
    );
    // 只包含数据库条目，故意缺失附件条目。
    final zipPath = await _writeArchive(workspace, {
      LocalBackupService.databaseEntryName: utf8.encode(
        _FakeVaultRepository.fakeDatabaseBytes,
      ),
    });
    expect(File(store.encryptedPath(attachment)).existsSync(), isTrue);

    await expectLater(
      service.restore(archivePath: zipPath, password: _correctPassword),
      throwsA(
        isA<LocalBackupException>().having(
          (error) => error.message,
          'message',
          contains('恢复不完整'),
        ),
      ),
    );
  });

  test('恢复：无效 zip 被拒绝', () async {
    final vault = _FakeVaultRepository(restored: resultWith(_bareAttachment()));
    final service = LocalBackupService(vaultRepository: vault);
    final invalidPath = path.join(workspace.path, 'invalid.cardorybackup');
    await File(invalidPath).writeAsBytes([1, 2, 3]);

    await expectLater(
      service.restore(archivePath: invalidPath, password: _correctPassword),
      throwsA(isA<LocalBackupException>()),
    );
  });
}

AttachmentData _bareAttachment() => AttachmentData(
  id: 'bare',
  fileName: 'bare.txt',
  storageKey: 'bare.cardory-attachment',
  encryptionKey: 'key',
  size: 1,
  sha256: 'hash',
  createdAt: DateTime.utc(2026),
);

/// 用给定条目写一个 zip 备份包，返回文件路径。
Future<String> _writeArchive(
  Directory workspace,
  Map<String, List<int>> entries,
) async {
  final zipPath = path.join(
    workspace.path,
    'cardory-backup-test${LocalBackupService.fileExtension}',
  );
  final encoder = ZipFileEncoder();
  encoder.create(zipPath);
  var index = 0;
  for (final entry in entries.entries) {
    final temporary = File(path.join(workspace.path, '.entry-${index++}'));
    await temporary.writeAsBytes(entry.value);
    await encoder.addFile(temporary, entry.key);
    if (await temporary.exists()) await temporary.delete();
  }
  await encoder.close();
  return zipPath;
}
