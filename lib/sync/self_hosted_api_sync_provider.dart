import 'dart:io';

import 'package:http/http.dart' as http;

import 'sync_credentials.dart';
import 'sync_models.dart';
import 'sync_provider.dart';

/// 基于自建 HTTP 服务的同步提供者。
///
/// 通过配置的容器资源 URL 与自建服务通信，支持 `GET` / `HEAD` / `PUT` / `DELETE`
/// 操作，鉴权方式为 Bearer Token。
class SelfHostedApiSyncProvider implements SyncProvider {
  SelfHostedApiSyncProvider({
    required Uri endpoint,
    required this.credentialStore,
    http.Client? client,
  }) : endpoint = _validateEndpoint(endpoint),
       _client = client ?? http.Client();

  final Uri endpoint;
  final SyncCredentialStore credentialStore;
  final http.Client _client;

  @override
  String get id => 'selfHosted';

  @override
  String get displayName => '自托管 API';

  Future<Map<String, String>> _headers({
    bool contentType = false,
    String? expectedRevision,
  }) async {
    final token = await credentialStore.readSelfHostedToken();
    if (token == null || token.trim().isEmpty) {
      throw const SyncProviderException('请先设置自托管 API 访问令牌');
    }
    return {
      'authorization': 'Bearer ${token.trim()}',
      'accept': 'application/octet-stream',
      if (contentType) 'content-type': 'application/octet-stream',
      if (expectedRevision != null) 'if-match': expectedRevision,
    };
  }

  @override
  Future<void> checkConnection() async {
    try {
      final response = await _client.head(endpoint, headers: await _headers());
      if (response.statusCode == 404 ||
          (response.statusCode >= 200 && response.statusCode < 300)) {
        return;
      }
      throw SyncProviderException('自托管 API 返回 HTTP ${response.statusCode}');
    } on SyncProviderException {
      rethrow;
    } catch (error) {
      throw SyncProviderException('无法连接自托管 API', cause: error);
    }
  }

  @override
  Future<SyncDocument?> read(String key) async {
    _assertDocumentKey(key);
    try {
      final response = await _client.get(endpoint, headers: await _headers());
      if (response.statusCode == 404) return null;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncProviderException('自托管下载失败：HTTP ${response.statusCode}');
      }
      return SyncDocument(
        bytes: response.bodyBytes,
        revision: response.headers['etag'] ?? _fallbackRevision(response),
        modifiedAt: _readHttpDate(response.headers['last-modified']),
      );
    } on SyncProviderException {
      rethrow;
    } catch (error) {
      throw SyncProviderException('无法连接自托管 API', cause: error);
    }
  }

  @override
  Future<SyncWriteResult> write(
    String key,
    List<int> bytes, {
    String? expectedRevision,
  }) async {
    _assertDocumentKey(key);
    try {
      final response = await _client.put(
        endpoint,
        headers: await _headers(
          contentType: true,
          expectedRevision: expectedRevision,
        ),
        body: bytes,
      );
      if (response.statusCode == 409 || response.statusCode == 412) {
        throw const SyncConflictException('自托管备份已被其他设备修改');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncProviderException('自托管上传失败：HTTP ${response.statusCode}');
      }
      return SyncWriteResult(
        revision: response.headers['etag'] ?? _fallbackRevision(response),
        modifiedAt: _readHttpDate(response.headers['last-modified']),
      );
    } on SyncConflictException {
      rethrow;
    } on SyncProviderException {
      rethrow;
    } catch (error) {
      throw SyncProviderException('无法连接自托管 API', cause: error);
    }
  }

  @override
  Future<void> delete(String key, {String? expectedRevision}) async {
    _assertDocumentKey(key);
    try {
      final request = http.Request('DELETE', endpoint)
        ..headers.addAll(await _headers(expectedRevision: expectedRevision));
      final response = await _client.send(request);
      if (response.statusCode == 404) return;
      if (response.statusCode == 409 || response.statusCode == 412) {
        throw const SyncConflictException('自托管备份已被其他设备修改');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SyncProviderException('删除自托管备份失败：HTTP ${response.statusCode}');
      }
    } on SyncConflictException {
      rethrow;
    } on SyncProviderException {
      rethrow;
    } catch (error) {
      throw SyncProviderException('无法连接自托管 API', cause: error);
    }
  }

  static Uri _validateEndpoint(Uri value) {
    if ((value.scheme != 'http' && value.scheme != 'https') ||
        value.host.isEmpty) {
      throw ArgumentError.value(value, 'endpoint');
    }
    return value.replace(fragment: null);
  }

  void _assertDocumentKey(String key) {
    if (key.isEmpty) throw ArgumentError.value(key, 'key');
  }

  String _fallbackRevision(http.Response response) =>
      '${response.headers['last-modified'] ?? ''}:${response.bodyBytes.length}';

  DateTime? _readHttpDate(String? value) =>
      value == null ? null : HttpDate.parse(value).toUtc();

  void dispose() => _client.close();
}
