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
}
