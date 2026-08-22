/// 向应用与表现层暴露的同步进度状态。
library;

enum SyncPhase { idle, checking, pulling, pushing, success, conflict, failure }

enum SyncConflictChoice { keepLocal, keepRemote, manualMerge, cancel }

enum SyncConflictSide { local, remote }

class SyncConflictItem {
  const SyncConflictItem({
    required this.id,
    required this.category,
    required this.title,
    required this.side,
  });

  final String id;
  final String category;
  final String title;
  final SyncConflictSide side;

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'title': title,
    'side': side.name,
  };
}

class SyncResultSummary {
  const SyncResultSummary({
    this.localItems = 0,
    this.remoteItems = 0,
    this.mergedItems = 0,
    this.skippedItems = 0,
  });

  final int localItems;
  final int remoteItems;
  final int mergedItems;
  final int skippedItems;

  String get displayText =>
      '本地保留 $localItems 项，使用远端 $remoteItems 项，手动合并 $mergedItems 项，跳过 $skippedItems 项';
}

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.providerId,
    this.message,
    this.lastSyncedAt,
    this.requiresReload = false,
    this.conflicts = const [],
    this.summary,
  });

  final SyncPhase phase;
  final String? providerId;
  final String? message;
  final DateTime? lastSyncedAt;
  final bool requiresReload;
  final List<SyncConflictItem> conflicts;
  final SyncResultSummary? summary;

  bool get isRunning =>
      phase == SyncPhase.checking ||
      phase == SyncPhase.pulling ||
      phase == SyncPhase.pushing;

  SyncStatus copyWith({
    SyncPhase? phase,
    String? providerId,
    String? message,
    DateTime? lastSyncedAt,
    bool? requiresReload,
    List<SyncConflictItem>? conflicts,
    SyncResultSummary? summary,
    bool clearMessage = false,
  }) => SyncStatus(
    phase: phase ?? this.phase,
    providerId: providerId ?? this.providerId,
    message: clearMessage ? null : message ?? this.message,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    requiresReload: requiresReload ?? this.requiresReload,
    conflicts: conflicts ?? this.conflicts,
    summary: summary ?? this.summary,
  );

  factory SyncStatus.fromJson(Map<String, dynamic> json) => SyncStatus(
    phase: SyncPhase.values.where((item) => item.name == json['phase']).firstOrNull ?? SyncPhase.idle,
    providerId: json['providerId'] as String?,
    message: json['message'] as String?,
    lastSyncedAt: DateTime.tryParse(json['lastSyncedAt'] as String? ?? ''),
    requiresReload: json['requiresReload'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'phase': phase.name,
    'providerId': providerId,
    'message': message,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    'requiresReload': requiresReload,
    'conflicts': conflicts.map((item) => item.toJson()).toList(),
    'summary': summary?.displayText,
  };

  @override
  bool operator ==(Object other) =>
      other is SyncStatus &&
      other.phase == phase &&
      other.providerId == providerId &&
      other.message == message &&
      other.lastSyncedAt == lastSyncedAt &&
      other.requiresReload == requiresReload &&
      other.conflicts.length == conflicts.length;

  @override
  int get hashCode => Object.hash(
    phase,
    providerId,
    message,
    lastSyncedAt,
    requiresReload,
    conflicts.length,
  );
}
