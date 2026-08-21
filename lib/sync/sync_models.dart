// 同步功能的数据模型定义。
//
// 包含远端文档、写入结果和同步基础设施异常。
// [SyncStatus] 作为应用层契约从这里重新导出，以保持现有调用兼容。

import 'dart:typed_data';

export '../application/sync_status.dart';

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

class SyncProviderException implements Exception {
  const SyncProviderException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'SyncProviderException: $message';
}

class SyncUnavailableException extends SyncProviderException {
  const SyncUnavailableException(super.message);
}
