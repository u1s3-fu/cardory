import 'dart:io';

import 'package:cardory/sync/directory_sync_provider.dart';
import 'package:cardory/sync/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late DirectorySyncProvider provider;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cardory-sync-test-');
    provider = DirectorySyncProvider(directory: directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('writes, reads and deletes a document', () async {
    await provider.checkConnection();
    final written = await provider.write('data/cardory.json', [1, 2, 3]);
    final document = await provider.read('data/cardory.json');

    expect(document?.bytes, [1, 2, 3]);
    expect(document?.revision, written.revision);

    await provider.delete(
      'data/cardory.json',
      expectedRevision: document?.revision,
    );
    expect(await provider.read('data/cardory.json'), isNull);
  });

  test('detects a stale revision and rejects path traversal', () async {
    await provider.write('cardory.json', [1]);

    await expectLater(
      provider.write('cardory.json', [2], expectedRevision: 'stale'),
      throwsA(isA<SyncConflictException>()),
    );
    expect(
      () => provider.read('../outside.json'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('streams attachment files without loading them as a document', () async {
    final source = File(
      '${directory.parent.path}${Platform.pathSeparator}attachment-source.bin',
    );
    final target = File(
      '${directory.parent.path}${Platform.pathSeparator}attachment-target.bin',
    );
    addTearDown(() async {
      if (await source.exists()) await source.delete();
      if (await target.exists()) await target.delete();
    });
    final bytes = List<int>.generate(
      1024 * 1024 + 17,
      (index) => index % 239,
      growable: false,
    );
    await source.writeAsBytes(bytes);

    await provider.uploadFile('attachments/v1/file.blob', source.path);
    expect(await provider.fileExists('attachments/v1/file.blob'), isTrue);
    await provider.downloadFile('attachments/v1/file.blob', target.path);

    expect(await target.readAsBytes(), bytes);
  });
}
