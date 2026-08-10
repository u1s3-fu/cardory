import 'dart:convert';
import 'dart:io';

import 'package:cardory/sync/directory_sync_provider.dart';

import 'package:cardory/sync/sync_models.dart';
import 'package:cardory/sync/webdav_sync_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('SyncStatus', () {
    test('round-trips JSON and reports running phases', () {
      final status = SyncStatus(
        phase: SyncPhase.pushing,
        providerId: 'webdav',
        lastSyncedAt: DateTime.utc(2026, 7, 29),
      );

      expect(SyncStatus.fromJson(status.toJson()), status);
      expect(status.isRunning, isTrue);
      expect(status.copyWith(phase: SyncPhase.success).isRunning, isFalse);
    });
  });

  group('DirectorySyncProvider', () {
    late Directory directory;
    late DirectorySyncProvider provider;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('cardory-sync-');
      provider = DirectorySyncProvider(directory: directory);
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('writes, reads and deletes a document', () async {
      await provider.checkConnection();
      final write = await provider.write(
        'data/cardory.json',
        utf8.encode('{}'),
      );
      final document = await provider.read('data/cardory.json');

      expect(utf8.decode(document!.bytes), '{}');
      expect(document.revision, write.revision);
      await provider.delete(
        'data/cardory.json',
        expectedRevision: write.revision,
      );
      expect(await provider.read('data/cardory.json'), isNull);
    });

    test('rejects traversal and stale revisions', () async {
      expect(() => provider.read('../secret'), throwsArgumentError);
      await provider.write('cardory.json', [1]);
      expect(
        provider.write('cardory.json', [2], expectedRevision: 'stale'),
        throwsA(isA<SyncConflictException>()),
      );
    });
  });

  group('WebDavSyncProvider', () {
    test('uses authentication and revision preconditions', () async {
      late http.Request request;
      final provider = WebDavSyncProvider(
        baseUrl: Uri.parse('https://dav.example/cardory/'),
        username: 'user',
        password: 'pass',
        client: MockClient((value) async {
          request = value;
          return http.Response('', 204, headers: {'etag': 'v2'});
        }),
      );

      final result = await provider.write('cardory.json', [
        1,
        2,
      ], expectedRevision: 'v1');

      expect(
        request.url.toString(),
        'https://dav.example/cardory/cardory.json',
      );
      expect(request.headers['If-Match'], 'v1');
      expect(request.headers['Authorization'], startsWith('Basic '));
      expect(result.revision, 'v2');
    });

    test('maps precondition failures to conflicts', () async {
      final provider = WebDavSyncProvider(
        baseUrl: Uri.parse('https://dav.example/'),
        username: '',
        password: '',
        client: MockClient((_) async => http.Response('', 412)),
      );

      expect(
        provider.write('cardory.json', [1], expectedRevision: 'v1'),
        throwsA(isA<SyncConflictException>()),
      );
    });
  });
}
