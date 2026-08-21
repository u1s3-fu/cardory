import 'dart:convert';
import 'dart:io';

import 'package:cardory/data/attachment_store.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late AttachmentStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cardory-attachments-');
    store = AttachmentStore(
      rootDirectory: Directory(
        '${directory.path}${Platform.pathSeparator}data',
      ),
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('encrypts and exports a file larger than one chunk', () async {
    final plaintext = List<int>.generate(
      AttachmentStore.chunkSize * 2 + 137,
      (index) => index % 251,
      growable: false,
    );
    final source = File('${directory.path}${Platform.pathSeparator}source.bin');
    await source.writeAsBytes(plaintext);

    final attachment = await store.importFile(
      sourcePath: source.path,
      id: 'attachment-1',
      fileName: 'source.bin',
    );

    expect(attachment.size, plaintext.length);
    expect(attachment.storageKey, startsWith('attachment-1-'));
    expect(attachment.storageKey, endsWith('.cardory-attachment'));
    expect(attachment.encryptionKey, isNotEmpty);
    expect(attachment.sha256, isNotEmpty);
    expect(attachment.toJson(), isNot(contains('fileBytes')));

    final output = File('${directory.path}${Platform.pathSeparator}output.bin');
    await store.exportFile(attachment, output.path);
    expect(await output.readAsBytes(), plaintext);
  });

  test('uses an immutable storage key for each imported file', () async {
    final source = File('${directory.path}${Platform.pathSeparator}source.txt');
    await source.writeAsString('content');

    final first = await store.importFile(
      sourcePath: source.path,
      id: 'same-id',
      fileName: 'source.txt',
    );
    final second = await store.importFile(
      sourcePath: source.path,
      id: 'same-id',
      fileName: 'source.txt',
    );

    expect(second.storageKey, isNot(first.storageKey));
    expect(await store.contains(first), isTrue);
    expect(await store.contains(second), isTrue);
  });

  test('rejects a modified encrypted attachment', () async {
    final source = File('${directory.path}${Platform.pathSeparator}source.txt');
    await source.writeAsString('sensitive attachment');
    final attachment = await store.importFile(
      sourcePath: source.path,
      id: 'attachment-2',
      fileName: 'source.txt',
    );
    final encrypted = File(
      '${directory.path}${Platform.pathSeparator}data${Platform.pathSeparator}${attachment.storageKey}',
    );
    final bytes = await encrypted.readAsBytes();
    bytes[bytes.length - 1] ^= 1;
    await encrypted.writeAsBytes(bytes);

    expect(
      () => store.exportFile(
        attachment,
        '${directory.path}${Platform.pathSeparator}tampered.txt',
      ),
      throwsA(isA<AttachmentStorageException>()),
    );
  });

  test('prunes unreferenced encrypted files but keeps active files', () async {
    final source = File('${directory.path}${Platform.pathSeparator}source.txt');
    await source.writeAsString('content');
    final active = await store.importFile(
      sourcePath: source.path,
      id: 'active',
      fileName: 'source.txt',
    );
    final orphan = await store.importFile(
      sourcePath: source.path,
      id: 'orphan',
      fileName: 'source.txt',
    );
    final orphanPath = store.encryptedPath(orphan);

    await store.prune({active.storageKey});

    expect(await store.contains(active), isTrue);
    expect(await File(orphanPath).exists(), isFalse);
  });

  test(
    'migrates legacy base64 content without retaining it in metadata',
    () async {
      final legacy = AttachmentData(
        id: 'legacy-1',
        fileName: 'legacy.txt',
        createdAt: DateTime.utc(2026, 8, 19),
        legacyFileBytes: base64Encode(utf8.encode('legacy content')),
      );

      final migrated = await store.migrateLegacy(legacy);

      expect(migrated.needsMigration, isFalse);
      expect(migrated.legacyFileBytes, isNull);
      expect(migrated.toJson(), isNot(contains('fileBytes')));
      final output = File(
        '${directory.path}${Platform.pathSeparator}legacy.txt',
      );
      await store.exportFile(migrated, output.path);
      expect(await output.readAsString(), 'legacy content');
    },
  );
}
