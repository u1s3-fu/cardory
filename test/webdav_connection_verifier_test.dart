import 'package:cardory/sync/webdav_connection_verifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('rejects a normal HTTP 200 page as a WebDAV connection', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PROPFIND');
      expect(request.headers['depth'], '0');
      expect(request.followRedirects, isFalse);
      return http.Response('normal page', 200);
    });

    await expectLater(
      verifyWebDavConnection(
        client: client,
        baseUrl: Uri.parse('https://example.com/storage/'),
        headers: const <String, String>{},
      ),
      throwsA(isA<WebDavConnectionException>()),
    );
  });
}
