// WebDAV 连接验证的轻量封装。
//
// 仅发起只读的 PROPFIND Depth: 0 请求，验证远端地址确实是一个可访问的
// WebDAV 集合，不读写任何 Cardory 文档。

import 'dart:convert';

import 'package:http/http.dart' as http;

class WebDavConnectionException implements Exception {
  WebDavConnectionException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message: $cause';
}

/// 为常见 WebDAV 错误状态附加一句中文行动指引，供连接验证与读写失败共用。
String webDavStatusHint(int statusCode) => switch (statusCode) {
  401 => '，请检查用户名与密码是否正确',
  403 =>
    '，服务器拒绝访问：请确认该账号对目标目录有读写权限，'
        '且 WebDAV 地址指向已存在、允许写入的目录',
  _ => '',
};

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
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 207) {
      final detail = await _readReasonSnippet(response);
      throw WebDavConnectionException(
        'WebDAV 连接验证失败：PROPFIND $baseUrl 返回 HTTP ${response.statusCode}'
        '${webDavStatusHint(response.statusCode)}'
        '${detail == null ? '' : '，服务器返回：$detail'}',
      );
    }
    await response.stream.drain<void>().timeout(const Duration(seconds: 15));
  } on WebDavConnectionException {
    rethrow;
  } on Object catch (error) {
    throw WebDavConnectionException('无法连接 WebDAV', cause: error);
  }
}

/// 读取失败响应的响应体前若干字节并整理为可读摘要（错误页 / DAV XML 等），
/// 服务器常在其中写明拒绝原因（配额、只读、目录不存在等）。
Future<String?> _readReasonSnippet(http.StreamedResponse response) async {
  try {
    final bytes = await response.stream.toBytes().timeout(
      const Duration(seconds: 5),
    );
    if (bytes.isEmpty) return null;
    final text = utf8
        .decode(bytes, allowMalformed: true)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return null;
    return text.length > 200 ? '${text.substring(0, 200)}…' : text;
  } catch (_) {
    return null;
  }
}
