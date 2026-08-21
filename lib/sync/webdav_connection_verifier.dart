import 'package:http/http.dart' as http;

class WebDavConnectionException implements Exception {
  WebDavConnectionException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message: $cause';
}

/// 验证端点是否为可访问的 WebDAV 集合。
Future<void> verifyWebDavConnection({
  required http.Client client,
  required Uri baseUrl,
  required Map<String, String> headers,
}) async {
  final request = http.Request('PROPFIND', baseUrl)
    ..followRedirects = false
    ..headers.addAll(headers)
    ..headers['Depth'] = '0';

  try {
    final response = await client.send(request).timeout(
          const Duration(seconds: 15),
        );
    if (response.statusCode != 207) {
      throw WebDavConnectionException(
        'WebDAV 连接验证失败，服务器返回 HTTP ${response.statusCode}',
      );
    }
    await response.stream.drain<void>().timeout(const Duration(seconds: 15));
  } on WebDavConnectionException {
    rethrow;
  } on Object catch (error) {
    throw WebDavConnectionException('无法连接 WebDAV', cause: error);
  }
}
