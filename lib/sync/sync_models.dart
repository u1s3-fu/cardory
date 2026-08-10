/// 同步功能的数据模型定义。
///
/// 包含同步状态 [SyncStatus]、远端的 [SyncDocument] 与 [SyncWriteResult]、
/// 以及同步冲突异常 [SyncConflictException] 等同步流程核心结构。

import 'dart:typed_data';

enum SyncPhase { idle, checking, pulling, pushing, success, conflict, failure }

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.providerId,
    this.message,
    this.lastSyncedAt,
  });

  final SyncPhase phase;
  final String? providerId;
  final String? message;
  final DateTime? lastSyncedAt;

  bool get isRunning =>
      phase == SyncPhase.checking ||
      phase == SyncPhase.pulling ||
      phase == SyncPhase.pushing;

  SyncStatus copyWith({
    SyncPhase? phase,
    String? providerId,
    String? message,
    DateTime? lastSyncedAt,
    bool clearMessage = false,
  }) => SyncStatus(
    phase: phase ?? this.phase,
    providerId: providerId ?? this.providerId,
    message: clearMessage ? null : message ?? this.message,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
  );

  factory SyncStatus.fromJson(Map<String, dynamic> json) => SyncStatus(
    phase:
        SyncPhase.values
            .where((item) => item.name == json['phase'])
            .firstOrNull ??
        SyncPhase.idle,
    providerId: json['providerId'] as String?,
    message: json['message'] as String?,
    lastSyncedAt: DateTime.tryParse(json['lastSyncedAt'] as String? ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'phase': phase.name,
    'providerId': providerId,
    'message': message,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.phase == phase &&
      other.providerId == providerId &&
      other.message == message &&
      other.lastSyncedAt == lastSyncedAt;

  @override
  int get hashCode => Object.hash(phase, providerId, message, lastSyncedAt);
}

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
