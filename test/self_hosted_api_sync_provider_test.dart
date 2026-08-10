import 'package:cardory/sync/self_hosted_api_sync_provider.dart';
import 'package:cardory/sync/sync_credentials.dart';
import 'package:cardory/sync/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('reads encrypted container with bearer token and ETag', () async {
    http.Request? request;
    final provider = SelfHostedApiSyncProvider(
      endpoint: Uri.parse('https://sync.example.com/v1/cardory/container'),
      credentialStore: _Credentials('secret-token'),
      client: MockClient((value) async {
        request = value;
        return http.Response(
          'encrypted',
          200,
          headers: {
            'etag': 'v1',
            'last-modified': 'Wed, 21 Oct 2015 07:28:00 GMT',
          },
        );
      }),
    );

    final document = await provider.read('cardory-data.json');

    expect(request?.headers['authorization'], 'Bearer secret-token');
    expect(document?.bytes, 'encrypted'.codeUnits);
    expect(document?.revision, 'v1');
  });

  test(
    'writes conditionally and maps precondition failures to conflicts',
    () async {
      http.Request? request;
      final provider = SelfHostedApiSyncProvider(
        endpoint: Uri.parse('https://sync.example.com/v1/cardory/container'),
        credentialStore: _Credentials('secret-token'),
        client: MockClient((value) async {
          request = value;
          return http.Response('', 204, headers: {'etag': 'v2'});
        }),
      );

      final result = await provider.write('cardory-data.json', [
        1,
        2,
      ], expectedRevision: 'v1');

      expect(request?.method, 'PUT');
      expect(request?.headers['if-match'], 'v1');
      expect(result.revision, 'v2');

      final conflicting = SelfHostedApiSyncProvider(
        endpoint: Uri.parse('https://sync.example.com/v1/cardory/container'),
        credentialStore: _Credentials('secret-token'),
        client: MockClient((_) async => http.Response('', 412)),
      );
      expect(
        conflicting.write('cardory-data.json', [1], expectedRevision: 'v1'),
        throwsA(isA<SyncConflictException>()),
      );
    },
  );
}

class _Credentials implements SyncCredentialStore {
  const _Credentials(this.token);

  final String? token;

  @override
  Future<void> deleteSelfHostedToken() async {}

  @override
  Future<void> deleteWebDav() async {}

  @override
  Future<String?> readSelfHostedToken() async => token;

  @override
  Future<WebDavCredentials?> readWebDav() async => null;

  @override
  Future<void> writeSelfHostedToken(String token) async {}

  @override
  Future<void> writeWebDav(WebDavCredentials credentials) async {}
}
