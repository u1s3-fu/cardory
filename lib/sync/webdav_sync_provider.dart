// 基于 WebDAV 协议的同步提供者。
//
// 通过 HTTP Basic Auth 连接到 WebDAV 服务器，使用 ETag 和 If-Match 实现
// 冲突检测，支持标准 WebDAV 操作（OPTIONS / GET / PUT / DELETE）。

import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'sync_models.dart';
import 'sync_provider.dart';
import 'webdav_connection_verifier.dart';

class WebDavSyncProvider implements SyncProvider, AttachmentSyncProvider {
  static const defaultRequestTimeout = Duration(seconds: 20);

  WebDavSyncProvider({
    required Uri baseUrl,
    required this.username,
    required this.password,
    http.Client? client,
    this.requestTimeout = defaultRequestTimeout,
  }) : baseUrl = _normalizeBaseUrl(baseUrl),
       _client = client ?? http.Client(),
       _ownsClient = client == null {
    if (baseUrl.scheme != 'http' && baseUrl.scheme != 'https') {
      throw ArgumentError.value(baseUrl, 'baseUrl');
    }
  }

  final Uri baseUrl;
  final String username;
  final String password;
  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;

  Map<String, String> get _headers => {
    'authorization':
        'Basic ${base64Encode(utf8.encode('$username:$password'))}',
  };

  @override
  String get id => 'webdav';

  @override
  String get displayName => 'WebDAV';

  Future<void> checkConnectionStrict() {
    return verifyWebDavConnection(
      client: _client,
      baseUrl: baseUrl,
      headers: _headers,
    );
  }

  @override
  Future<void> checkConnection() async {
    try {
      final response = await _withTimeout(
        _client.send(
          http.Request('OPTIONS', baseUrl)..headers.addAll(_headers),
        ),
      );
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw SyncProviderException(
          _describe(
            '连接检查',
            'OPTIONS',
            baseUrl,
            response.statusCode,
            serverDetail: await _streamSnippet(response),
          ),
        );
      }
      await _withTimeout(response.stream.drain<void>());
    } on WebDavConnectionException catch (error) {
      throw SyncProviderException(error.message, cause: error.cause);
    } on SyncProviderException {
      rethrow;
    } catch (error) {
      throw SyncProviderException('无法连接 WebDAV', cause: error);
    }
  }

  @override
  Future<SyncDocument?> read(String key) async {
    try {
      final response = await _withTimeout(
        _client.get(_urlFor(key), headers: _headers),
      );
      if (response.statusCode == 404) return null;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncProviderException(
          _describe(
            '下载',
            'GET',
            _urlFor(key),
            response.statusCode,
            serverDetail: _snippet(response.bodyBytes),
          ),
        );
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
      final response = await _withTimeout(
        _client.put(_urlFor(key), headers: headers, body: bytes),
      );
      if (response.statusCode == 409 || response.statusCode == 412) {
        throw const SyncConflictException('WebDAV 文件已被其他设备修改');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncProviderException(
          _describe(
            '上传',
            'PUT',
            _urlFor(key),
            response.statusCode,
            serverDetail: _snippet(response.bodyBytes),
          ),
        );
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
      final response = await _withTimeout(_client.send(request));
      if (response.statusCode == 404) return;
      if (response.statusCode == 409 || response.statusCode == 412) {
        throw const SyncConflictException('WebDAV 文件已被其他设备修改');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncProviderException(
          _describe(
            '删除',
            'DELETE',
            _urlFor(key),
            response.statusCode,
            serverDetail: await _streamSnippet(response),
          ),
        );
      }
      await _withTimeout(response.stream.drain<void>());
    } on SyncConflictException {
      rethrow;
    } on SyncProviderException {
      rethrow;
    } catch (error) {
      throw SyncProviderException('无法连接 WebDAV', cause: error);
    }
  }

  @override
  Future<bool> fileExists(String key) async {
    final response = await _withTimeout(
      _client.send(
        http.Request('HEAD', _urlFor(key))..headers.addAll(_headers),
      ),
    );
    if (response.statusCode == 404) return false;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncProviderException(
        _describe(
          '检查附件',
          'HEAD',
          _urlFor(key),
          response.statusCode,
          serverDetail: await _streamSnippet(response),
        ),
      );
    }
    await _withTimeout(response.stream.drain<void>());
    return true;
  }

  @override
  Future<void> downloadFile(String key, String targetPath) async {
    final target = File(targetPath);
    final response = await _withTimeout(
      _client.send(http.Request('GET', _urlFor(key))..headers.addAll(_headers)),
    );
    if (response.statusCode == 404) {
      throw const SyncProviderException('远端附件不存在');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncProviderException(
        _describe(
          '下载附件',
          'GET',
          _urlFor(key),
          response.statusCode,
          serverDetail: await _streamSnippet(response),
        ),
      );
    }
    await target.parent.create(recursive: true);
    await _withTimeout(response.stream.pipe(target.openWrite()));
  }

  @override
  Future<void> uploadFile(String key, String sourcePath) async {
    final source = File(sourcePath);
    await _ensureParentCollections(key);
    final request = http.StreamedRequest('PUT', _urlFor(key))
      ..headers.addAll({
        ..._headers,
        'content-type': 'application/octet-stream',
      })
      ..contentLength = await source.length();
    final responseFuture = _withTimeout(_client.send(request));
    await _withTimeout(request.sink.addStream(source.openRead()));
    await _withTimeout(request.sink.close());
    final response = await responseFuture;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncProviderException(
        _describe(
          '上传附件',
          'PUT',
          _urlFor(key),
          response.statusCode,
          serverDetail: await _streamSnippet(response),
        ),
      );
    }
  }

  Future<void> _ensureParentCollections(String key) async {
    final segments = key.split('/');
    for (var count = 1; count < segments.length; count++) {
      final request = http.Request(
        'MKCOL',
        _urlFor(segments.take(count).join('/')),
      )..headers.addAll(_headers);
      final response = await _withTimeout(_client.send(request));
      if (response.statusCode != 201 &&
          response.statusCode != 200 &&
          response.statusCode != 204 &&
          response.statusCode != 405) {
        final collectionPath = segments.take(count).join('/');
        throw SyncProviderException(
          _describe(
            '创建附件目录',
            'MKCOL',
            _urlFor(collectionPath),
            response.statusCode,
            serverDetail: await _streamSnippet(response),
          ),
        );
      }
      await _withTimeout(response.stream.drain<void>());
    }
  }

  Future<T> _withTimeout<T>(Future<T> operation) async {
    try {
      return await operation.timeout(requestTimeout);
    } on TimeoutException catch (error) {
      throw SyncProviderException('WebDAV 请求超时', cause: error);
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

  /// 构造携带 HTTP 方法、目标地址与可选服务器响应片段的失败信息，
  /// 便于用户报告 4xx/5xx 时定位到被拒绝的具体请求。
  String _describe(
    String action,
    String method,
    Uri url,
    int statusCode, {
    String? serverDetail,
  }) {
    final detail = (serverDetail == null || serverDetail.isEmpty)
        ? ''
        : '，服务器返回：$serverDetail';
    return 'WebDAV $action失败：$method $url 返回 HTTP $statusCode'
        '${webDavStatusHint(statusCode)}$detail';
  }

  /// 从响应体字节中提取可读摘要（错误页 / DAV XML 等），服务器常在其中
  /// 写明拒绝原因（配额、只读、目录不存在等）；为空时返回 null。
  String? _snippet(List<int> bodyBytes) {
    if (bodyBytes.isEmpty) return null;
    final text = utf8
        .decode(bodyBytes, allowMalformed: true)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) return null;
    return text.length > 200 ? '${text.substring(0, 200)}…' : text;
  }

  /// 读取流式失败响应的响应体摘要；读取失败返回 null，不阻断报错。
  Future<String?> _streamSnippet(http.StreamedResponse response) async {
    try {
      final bytes = await response.stream.toBytes().timeout(
        const Duration(seconds: 3),
      );
      return _snippet(bytes);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    if (_ownsClient) _client.close();
  }
}
