// 同步功能的数据模型定义。
//
// 包含远端文档、写入结果和同步基础设施异常。
// [SyncStatus] 作为应用层契约从这里重新导出，以保持现有调用兼容。

import 'dart:typed_data';

export '../domain/sync_status.dart';

class SyncDocument {
  const SyncDocument({required this.bytes, this.revision, this.modifiedAt});

  final Uint8List bytes;
  final String? revision;
  final DateTime? modifiedAt;
}

class SyncWriteResult {
  const SyncWriteResult({this.revision, this.modifiedAt});

  final String? revision;
  final DateTime? modifiedAt;
}

class SyncConflictException implements Exception {
  const SyncConflictException(this.message);

  final String message;

  @override
  String toString() => 'SyncConflictException: $message';
}

/// 同步提供者异常的可选机器可读错误码，供上层结构化判断，
/// 避免依赖中文字面量做字符串匹配。
enum SyncProviderErrorCode {
  webDavCredentialsMissing,
  s3CredentialsMissing,
}

class SyncProviderException implements Exception {
  const SyncProviderException(this.message, {this.cause, this.code});

  final String message;
  final Object? cause;
  final SyncProviderErrorCode? code;

  @override
  String toString() => 'SyncProviderException: $message';
}

class SyncUnavailableException extends SyncProviderException {
  const SyncUnavailableException(super.message);
}
