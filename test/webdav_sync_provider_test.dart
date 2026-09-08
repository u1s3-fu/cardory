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

  test('reports the exact request and server reason on an HTTP 403', () async {
    final provider = WebDavSyncProvider(
      baseUrl: Uri.parse('https://dav.example.com/cardory/'),
      username: 'user',
      password: 'secret',
      client: MockClient((request) async {
        expect(request.method, 'GET');
        return http.Response('<h1>403 Forbidden by policy</h1>', 403);
      }),
    );

    await expectLater(
      provider.read('cardory-data.json'),
      throwsA(
        isA<SyncProviderException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('下载'),
            contains('GET'),
            contains('cardory-data.json'),
            contains('403'),
            contains('拒绝访问'),
            contains('Forbidden by policy'),
          ),
        ),
      ),
    );
  });

  test('reports a forbidden upload with the PUT target', () async {
    final provider = WebDavSyncProvider(
      baseUrl: Uri.parse('https://dav.example.com/cardory/'),
      username: 'user',
      password: 'secret',
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        return http.Response('Forbidden', 403);
      }),
    );

    await expectLater(
      provider.write('cardory-data.json', utf8.encode('{}')),
      throwsA(
        isA<SyncProviderException>().having(
          (error) => error.message,
          'message',
          allOf(
            contains('PUT'),
            contains('cardory-data.json'),
            contains('403'),
            contains('拒绝访问'),
          ),
        ),
      ),
    );
  });
}
