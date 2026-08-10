/// 基于 WebDAV 协议的同步提供者。
///
/// 通过 HTTP Basic Auth 连接到 WebDAV 服务器，使用 ETag 和 If-Match 实现
/// 冲突检测，支持标准 WebDAV 操作（OPTIONS / GET / PUT / DELETE）。

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'sync_models.dart';
import 'sync_provider.dart';

class WebDavSyncProvider implements SyncProvider {
  WebDavSyncProvider({
    required Uri baseUrl,
    required this.username,
    required this.password,
    http.Client? client,
  }) : baseUrl = _normalizeBaseUrl(baseUrl),
       _client = client ?? http.Client() {
    if (baseUrl.scheme != 'http' && baseUrl.scheme != 'https') {
      throw ArgumentError.value(baseUrl, 'baseUrl');
    }
  }

  final Uri baseUrl;
  final String username;
  final String password;
  final http.Client _client;

  Map<String, String> get _headers => {
    'authorization':
        'Basic ${base64Encode(utf8.encode('$username:$password'))}',
  };

  @override
  String get id => 'webdav';

  @override
  String get displayName => 'WebDAV';

  @override
  Future<void> checkConnection() async {
    try {
      final response = await _client.send(
        http.Request('OPTIONS', baseUrl)..headers.addAll(_headers),
      );
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw SyncProviderException('WebDAV 返回 HTTP ${response.statusCode}');
      }
    } on SyncProviderException {
      rethrow;
    } catch (error) {
      throw SyncProviderException('无法连接 WebDAV', cause: error);
    }
  }

  @override
  Future<SyncDocument?> read(String key) async {
    try {
      final response = await _client.get(_urlFor(key), headers: _headers);
      if (response.statusCode == 404) return null;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncProviderException('WebDAV 下载失败：HTTP ${response.statusCode}');
      }
      return SyncDocument(
        bytes: response.bodyBytes,
        revision: response.headers['etag'] ?? _fallbackRevision(response),
        modifiedAt: _readHttpDate(response.headers['last-modified']),
      );
    } on SyncProviderException {
      rethrow;
    } catch (error) {
      throw SyncProviderException('无法连接 WebDAV', cause: error);
    }
  }

  @override
  Future<SyncWriteResult> write(
    String key,
    List<int> bytes, {
    String? expectedRevision,
  }) async {
    try {
      final headers = {
        ..._headers,
        'content-type': 'application/octet-stream',
        if (expectedRevision != null) 'if-match': expectedRevision,
      };
      final response = await _client.put(
        _urlFor(key),
        headers: headers,
        body: bytes,
      );
      if (response.statusCode == 409 || response.statusCode == 412) {
        throw const SyncConflictException('WebDAV 文件已被其他设备修改');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncProviderException('WebDAV 上传失败：HTTP ${response.statusCode}');
      }
      return SyncWriteResult(
        revision:
            response.headers['etag'] ??
            '${response.headers['last-modified'] ?? ''}:${bytes.length}',
        modifiedAt: _readHttpDate(response.headers['last-modified']),
      );
    } on SyncConflictException {
      rethrow;
    } on SyncProviderException {
      rethrow;
    } catch (error) {
      throw SyncProviderException('无法连接 WebDAV', cause: error);
    }
  }

  @override
  Future<void> delete(String key, {String? expectedRevision}) async {
    try {
      final request = http.Request('DELETE', _urlFor(key))
        ..headers.addAll({
          ..._headers,
          if (expectedRevision != null) 'if-match': expectedRevision,
        });
      final response = await _client.send(request);
      if (response.statusCode == 404) return;
      if (response.statusCode == 409 || response.statusCode == 412) {
        throw const SyncConflictException('WebDAV 文件已被其他设备修改');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncProviderException('WebDAV 删除失败：HTTP ${response.statusCode}');
      }
    } on SyncConflictException {
      rethrow;
    } on SyncProviderException {
      rethrow;
    } catch (error) {
      throw SyncProviderException('无法连接 WebDAV', cause: error);
    }
  }

  static Uri _normalizeBaseUrl(Uri value) {
    final normalizedPath = value.path.endsWith('/')
        ? value.path
        : '${value.path}/';
    return value.replace(path: normalizedPath, query: null, fragment: null);
  }

  Uri _urlFor(String key) {
    final segments = key.split('/');
    if (key.isEmpty || segments.any((item) => item.isEmpty || item == '..')) {
      throw ArgumentError.value(key, 'key');
    }
    return baseUrl.resolveUri(Uri(pathSegments: segments));
  }

  String _fallbackRevision(http.Response response) =>
      '${response.headers['last-modified'] ?? ''}:${response.bodyBytes.length}';

  DateTime? _readHttpDate(String? value) =>
      value == null ? null : HttpDate.parse(value).toUtc();
}
