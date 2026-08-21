// AWS Signature V4 签名、兼容 S3 的同步提供者。
// 通过自定义端点，可对接 AWS S3 以及 MinIO、R2、Backblaze B2 等
// 路径风格（path-style）的 S3 兼容服务。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'sync_credentials.dart';
import 'sync_models.dart';
import 'sync_provider.dart';

class S3SyncProvider implements SyncProvider, AttachmentSyncProvider {
  S3SyncProvider({
    required Uri endpoint,
    required this.bucket,
    required this.region,
    required this.prefix,
    required S3Credentials credentials,
    http.Client? client,
    DateTime Function()? clock,
  }) : endpoint = _validateEndpoint(endpoint),
       _credentials = credentials,
       _client = client ?? http.Client(),
       _ownsClient = client == null,
       _clock = clock ?? (() => DateTime.now().toUtc());

  final Uri endpoint;
  final String bucket;
  final String region;
  final String prefix;
  final S3Credentials _credentials;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _clock;

  @override
  String get id => 's3';

  @override
  String get displayName => 'S3 兼容存储';

  @override
  Future<void> checkConnection() async {
    try {
      final response = await _send('HEAD', _objectUrl(_documentKey), const []);
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const SyncProviderException('S3 凭据无效或没有存储桶权限');
      }
      if (response.statusCode != 404 &&
          (response.statusCode < 200 || response.statusCode >= 300)) {
        throw SyncProviderException('S3 返回 HTTP ${response.statusCode}');
      }
    } on SyncProviderException {
      rethrow;
    } catch (error) {
      throw SyncProviderException('无法连接 S3 兼容存储', cause: error);
    }
  }

  @override
  Future<SyncDocument?> read(String key) async {
    try {
      final response = await _send('GET', _objectUrl(key), const []);
      if (response.statusCode == 404) return null;
      _checkResponse(response, 'S3 下载失败');
      return SyncDocument(
        bytes: response.bodyBytes,
        revision: response.headers['etag'] ?? _fallbackRevision(response),
        modifiedAt: _readHttpDate(response.headers['last-modified']),
      );
    } on SyncProviderException {
      rethrow;
    } catch (error) {
      throw SyncProviderException('无法连接 S3 兼容存储', cause: error);
    }
  }

  @override
  Future<SyncWriteResult> write(
    String key,
    List<int> bytes, {
    String? expectedRevision,
  }) async {
    try {
      final headers = <String, String>{
        'content-type': 'application/octet-stream',
        if (expectedRevision != null) 'if-match': expectedRevision,
      };
      final response = await _send(
        'PUT',
        _objectUrl(key),
        bytes,
        headers: headers,
      );
      if (response.statusCode == 409 || response.statusCode == 412) {
        throw const SyncConflictException('S3 文件已被其他设备修改');
      }
      _checkResponse(response, 'S3 上传失败');
      return SyncWriteResult(
        revision: response.headers['etag'] ?? _fallbackRevision(response),
        modifiedAt: _readHttpDate(response.headers['last-modified']),
      );
    } on SyncConflictException {
      rethrow;
    } on SyncProviderException {
      rethrow;
    } catch (error) {
      throw SyncProviderException('无法连接 S3 兼容存储', cause: error);
    }
  }

  @override
  Future<void> delete(String key, {String? expectedRevision}) async {
    final response = await _send(
      'DELETE',
      _objectUrl(key),
      const [],
      headers: {if (expectedRevision != null) 'if-match': expectedRevision},
    );
    if (response.statusCode == 404) return;
    if (response.statusCode == 409 || response.statusCode == 412) {
      throw const SyncConflictException('S3 文件已被其他设备修改');
    }
    _checkResponse(response, 'S3 删除失败');
  }

  @override
  Future<bool> fileExists(String key) async {
    final response = await _send('HEAD', _objectUrl(key), const []);
    if (response.statusCode == 404) return false;
    _checkResponse(response, 'S3 检查附件失败');
    return true;
  }

  @override
  Future<void> downloadFile(String key, String targetPath) async {
    final target = File(targetPath);
    final uri = _objectUrl(key);
    final headers = await _signedHeaders(
      'GET',
      uri,
      _hex((await Sha256().hash(const [])).bytes),
      const {},
    );
    final response = await _client.send(
      http.Request('GET', uri)..headers.addAll(headers),
    );
    if (response.statusCode == 404) {
      throw const SyncProviderException('远端附件不存在');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncProviderException('S3 下载附件失败：HTTP ${response.statusCode}');
    }
    await target.parent.create(recursive: true);
    await response.stream.pipe(target.openWrite());
  }

  @override
  Future<void> uploadFile(String key, String sourcePath) async {
    final source = File(sourcePath);
    final uri = _objectUrl(key);
    final digest = await dart_crypto.sha256.bind(source.openRead()).first;
    final headers = await _signedHeaders('PUT', uri, digest.toString(), const {
      'content-type': 'application/octet-stream',
    });
    final request = http.StreamedRequest('PUT', uri)
      ..headers.addAll(headers)
      ..contentLength = await source.length();
    final responseFuture = _client.send(request);
    await request.sink.addStream(source.openRead());
    await request.sink.close();
    final response = await responseFuture;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncProviderException('S3 上传附件失败：HTTP ${response.statusCode}');
    }
  }

  Future<http.Response> _send(
    String method,
    Uri uri,
    List<int> body, {
    Map<String, String> headers = const {},
  }) async {
    final payloadHash = _hex((await Sha256().hash(body)).bytes);
    final requestHeaders = await _signedHeaders(
      method,
      uri,
      payloadHash,
      headers,
    );
    return _client
        .send(
          http.Request(method, uri)
            ..headers.addAll(requestHeaders)
            ..bodyBytes = body,
        )
        .then(http.Response.fromStream);
  }

  Future<Map<String, String>> _signedHeaders(
    String method,
    Uri uri,
    String payloadHash,
    Map<String, String> headers,
  ) async {
    final now = _clock().toUtc();
    final amzDate = _amzDate(now);
    final host = uri.host + (uri.hasPort ? ':${uri.port}' : '');
    final signedHeaders = <String, String>{
      'host': host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': amzDate,
      ...headers.map((key, value) => MapEntry(key.toLowerCase(), value)),
    };
    final canonicalHeaders = (signedHeaders.keys.toList()..sort())
        .map((key) => '$key:${signedHeaders[key]!.trim()}\n')
        .join();
    final signed = (signedHeaders.keys.toList()..sort()).join(';');
    final canonicalRequest = [
      method,
      _canonicalPath(uri.path),
      _canonicalQuery(uri.queryParameters),
      canonicalHeaders,
      signed,
      payloadHash,
    ].join('\n');
    final scope = '${_dateStamp(now)}/$region/s3/aws4_request';
    final stringToSign =
        'AWS4-HMAC-SHA256\n$amzDate\n$scope\n${_hex((await Sha256().hash(utf8.encode(canonicalRequest))).bytes)}';
    final signingKey = await _signingKey(
      _credentials.secretKey,
      _dateStamp(now),
    );
    final signature = _hex(
      (await Hmac.sha256().calculateMac(
        utf8.encode(stringToSign),
        secretKey: SecretKey(signingKey),
      )).bytes,
    );
    return <String, String>{
      ...signedHeaders,
      'authorization':
          'AWS4-HMAC-SHA256 Credential=${_credentials.accessKey}/$scope, SignedHeaders=$signed, Signature=$signature',
    };
  }

  Uri _objectUrl(String key) {
    if (bucket.trim().isEmpty ||
        key.isEmpty ||
        key.split('/').any((part) => part.isEmpty || part == '..')) {
      throw ArgumentError.value(key, 'key');
    }
    final objectKey = prefix.trim().isEmpty
        ? key
        : '${prefix.trim().replaceAll(RegExp(r'^/+|/+$'), '')}/$key';
    final path =
        '${endpoint.path.replaceFirst(RegExp(r'/$'), '')}/${_encodePath(bucket)}/${_encodePath(objectKey)}';
    return endpoint.replace(path: path, query: null, fragment: null);
  }

  static String _encodePath(String value) =>
      value.split('/').map(Uri.encodeComponent).join('/');
  static Uri _validateEndpoint(Uri value) {
    if ((value.scheme != 'http' && value.scheme != 'https') ||
        value.host.isEmpty) {
      throw ArgumentError.value(value, 'endpoint');
    }
    return value.replace(fragment: null, query: null);
  }

  static String _canonicalPath(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');
  static String _canonicalQuery(
    Map<String, String> query,
  ) => (query.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
      .map(
        (e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
      )
      .join('&');
  static String _amzDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}T${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}${d.second.toString().padLeft(2, '0')}Z';
  static String _dateStamp(DateTime d) => _amzDate(d).substring(0, 8);
  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  Future<List<int>> _signingKey(String secret, String date) async {
    final h = Hmac.sha256();
    final kDate = await h.calculateMac(
      utf8.encode(date),
      secretKey: SecretKey(utf8.encode('AWS4$secret')),
    );
    final kRegion = await h.calculateMac(
      utf8.encode(region),
      secretKey: SecretKey(kDate.bytes),
    );
    final kService = await h.calculateMac(
      utf8.encode('s3'),
      secretKey: SecretKey(kRegion.bytes),
    );
    final kSigning = await h.calculateMac(
      utf8.encode('aws4_request'),
      secretKey: SecretKey(kService.bytes),
    );
    return kSigning.bytes;
  }

  static void _checkResponse(http.Response response, String message) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SyncProviderException('$message：HTTP ${response.statusCode}');
    }
  }

  static String _fallbackRevision(http.Response response) =>
      '${response.headers['last-modified'] ?? ''}:${response.bodyBytes.length}';
  static DateTime? _readHttpDate(String? value) =>
      value == null ? null : HttpDate.parse(value).toUtc();
  @override
  Future<void> dispose() async {
    if (_ownsClient) _client.close();
  }
}

const _documentKey = 'cardory-current-data.cardory';
