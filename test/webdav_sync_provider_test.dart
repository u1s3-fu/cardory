import 'dart:convert';
import 'dart:async';

import 'package:cardory/sync/sync_models.dart';
import 'package:cardory/sync/webdav_sync_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'fails a stalled WebDAV connection request within the configured timeout',
    () async {
      final pendingResponse = Completer<http.Response>();
      final provider = WebDavSyncProvider(
        baseUrl: Uri.parse('https://dav.example.com/cardory/'),
        username: 'user',
        password: 'secret',
        requestTimeout: const Duration(milliseconds: 10),
        client: MockClient((_) => pendingResponse.future),
      );

      await expectLater(
        provider.checkConnection(),
        throwsA(isA<SyncProviderException>()),
      );
    },
  );

  test('reads a WebDAV document with basic authentication', () async {
    late http.Request captured;
    final provider = WebDavSyncProvider(
      baseUrl: Uri.parse('https://dav.example.com/cardory'),
      username: 'user',
      password: 'secret',
      client: MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode('{"ok":true}'),
          200,
          headers: {'etag': '"revision-1"'},
        );
      }),
    );

    final document = await provider.read('cardory-data.json');

    expect(
      captured.url.toString(),
      'https://dav.example.com/cardory/cardory-data.json',
    );
    expect(captured.headers['authorization'], startsWith('Basic '));
    expect(utf8.decode(document!.bytes), '{"ok":true}');
    expect(document.revision, '"revision-1"');
  });

  test('sends If-Match and reports a WebDAV conflict', () async {
    late http.Request captured;
    final provider = WebDavSyncProvider(
      baseUrl: Uri.parse('https://dav.example.com/cardory/'),
      username: 'user',
      password: 'secret',
      client: MockClient((request) async {
        captured = request;
        return http.Response('', 412);
      }),
    );

    await expectLater(
      provider.write(
        'cardory-data.json',
        utf8.encode('{}'),
        expectedRevision: '"old"',
      ),
      throwsA(isA<SyncConflictException>()),
    );
    expect(captured.headers['if-match'], '"old"');
  });
}
