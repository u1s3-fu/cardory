// Application settings and synchronization metadata.
//
// Kept separate from workspace entities so provider and UI configuration can
// evolve without changing the CardoryData aggregate.

enum SyncProviderType { none, directory, webdav, selfHosted, s3 }

class AppSettings {
  const AppSettings({
    this.themeColorValue = 0xFF6B62DF,
    this.backgroundColorValue = 0xFFF5F6FC,
    this.homeReminderPriorityThreshold = ProjectPriority.p2,
    this.recordSubTodoCreatedAt = false,
    this.renameAttachmentsOnUpload = true,
    this.keepAttachmentExtensionOnRename = false,
    this.autoLockEnabled = true,
    this.serverTypes = const [],
    this.syncProvider = SyncProviderType.none,
    this.syncDirectoryPath = '',
    this.webDavUrl = '',
    this.webDavUsername = '',
    this.selfHostedUrl = '',
    this.s3Endpoint = '',
    this.s3Region = 'us-east-1',
    this.s3Bucket = '',
    this.s3Prefix = 'cardory',
    this.pendingAttachmentDeletes = const [],
    this.syncRevision,
    this.syncLocalHash,
    this.lastSyncedAt,
    this.configSyncHash,
    this.lastConfigUpdatedAt,
  });

  final int themeColorValue;
  final int backgroundColorValue;
  final ProjectPriority homeReminderPriorityThreshold;
  final bool recordSubTodoCreatedAt;
  final bool renameAttachmentsOnUpload;
  final bool keepAttachmentExtensionOnRename;
  final bool autoLockEnabled;
  final List<String> serverTypes;
  final SyncProviderType syncProvider;
  final String syncDirectoryPath;
  final String webDavUrl;
  final String webDavUsername;
  final String selfHostedUrl;
  final String s3Endpoint;
  final String s3Region;
  final String s3Bucket;
  final String s3Prefix;
  final List<String> pendingAttachmentDeletes;
  final String? syncRevision;
  final String? syncLocalHash;
  final DateTime? lastSyncedAt;

  /// 本地上次成功同步到云端的配置哈希（用于避免重复推送配置）。
  final String? configSyncHash;

  /// 本地配置最近一次被修改的时间（用于与云端配置比较新旧）。
  final DateTime? lastConfigUpdatedAt;

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    themeColorValue: json['themeColorValue'] as int? ?? 0xFF6B62DF,
    backgroundColorValue: json['backgroundColorValue'] as int? ?? 0xFFF5F6FC,
    homeReminderPriorityThreshold: ProjectPriority.fromName(
      json['homeReminderPriorityThreshold'] as String? ?? 'p2',
    ),
    recordSubTodoCreatedAt:
        json['recordSubTodoCreatedAt'] as bool? ??
        json['autoSetSubTodoReminderTime'] as bool? ??
        false,
    renameAttachmentsOnUpload:
        json['renameAttachmentsOnUpload'] as bool? ?? true,
    keepAttachmentExtensionOnRename:
        json['keepAttachmentExtensionOnRename'] as bool? ?? false,
    autoLockEnabled: json['autoLockEnabled'] as bool? ?? true,
    serverTypes: ((json['serverTypes'] as List?) ?? [])
        .whereType<String>()
        .map((type) => type.trim())
        .where((type) => type.isNotEmpty)
        .toList(),
    syncProvider:
        SyncProviderType.values
            .where((value) => value.name == json['syncProvider'])
            .firstOrNull ??
        SyncProviderType.none,
    syncDirectoryPath: json['syncDirectoryPath'] as String? ?? '',
    webDavUrl: json['webDavUrl'] as String? ?? '',
    webDavUsername: json['webDavUsername'] as String? ?? '',
    selfHostedUrl: json['selfHostedUrl'] as String? ?? '',
    s3Endpoint: json['s3Endpoint'] as String? ?? '',
    s3Region: json['s3Region'] as String? ?? 'us-east-1',
    s3Bucket: json['s3Bucket'] as String? ?? '',
    s3Prefix: json['s3Prefix'] as String? ?? 'cardory',
    pendingAttachmentDeletes: ((json['pendingAttachmentDeletes'] as List?) ?? [])
        .whereType<String>()
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList(),
    syncRevision: json['syncRevision'] as String?,
    syncLocalHash: json['syncLocalHash'] as String?,
    lastSyncedAt: DateTime.tryParse(json['lastSyncedAt'] as String? ?? ''),
    configSyncHash: json['configSyncHash'] as String?,
    lastConfigUpdatedAt: DateTime.tryParse(
      json['lastConfigUpdatedAt'] as String? ?? '',
    ),
  );
  Map<String, dynamic> toJson() => {
    'themeColorValue': themeColorValue,
    'backgroundColorValue': backgroundColorValue,
    'homeReminderPriorityThreshold': homeReminderPriorityThreshold.name,
    'recordSubTodoCreatedAt': recordSubTodoCreatedAt,
    'renameAttachmentsOnUpload': renameAttachmentsOnUpload,
    'keepAttachmentExtensionOnRename': keepAttachmentExtensionOnRename,
    'autoLockEnabled': autoLockEnabled,
    'serverTypes': serverTypes,
    'syncProvider': syncProvider.name,
    'syncDirectoryPath': syncDirectoryPath,
    'webDavUrl': webDavUrl,
    'webDavUsername': webDavUsername,
    'selfHostedUrl': selfHostedUrl,
    's3Endpoint': s3Endpoint,
    's3Region': s3Region,
    's3Bucket': s3Bucket,
    's3Prefix': s3Prefix,
    'pendingAttachmentDeletes': pendingAttachmentDeletes,
    'syncRevision': syncRevision,
    'syncLocalHash': syncLocalHash,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    'configSyncHash': configSyncHash,
    'lastConfigUpdatedAt': lastConfigUpdatedAt?.toIso8601String(),
  };

  /// 生成仅包含可云端同步配置字段的 JSON 子集。
  ///
  /// 排除同步状态元数据（[syncRevision]、[syncLocalHash]、[lastSyncedAt]、
  /// [configSyncHash]、[lastConfigUpdatedAt]）以及本地操作队列
  /// [pendingAttachmentDeletes]，避免跨设备传播同步状态与本地待删除操作。
  Map<String, dynamic> toSyncConfigJson() => {
    'themeColorValue': themeColorValue,
    'backgroundColorValue': backgroundColorValue,
    'homeReminderPriorityThreshold': homeReminderPriorityThreshold.name,
    'recordSubTodoCreatedAt': recordSubTodoCreatedAt,
    'renameAttachmentsOnUpload': renameAttachmentsOnUpload,
    'keepAttachmentExtensionOnRename': keepAttachmentExtensionOnRename,
    'autoLockEnabled': autoLockEnabled,
    'serverTypes': serverTypes,
    'syncProvider': syncProvider.name,
    'syncDirectoryPath': syncDirectoryPath,
    'webDavUrl': webDavUrl,
    'webDavUsername': webDavUsername,
    'selfHostedUrl': selfHostedUrl,
    's3Endpoint': s3Endpoint,
    's3Region': s3Region,
    's3Bucket': s3Bucket,
    's3Prefix': s3Prefix,
  };

  /// 应用一份云端配置子集到当前设置。
  ///
  /// 仅覆盖可同步的配置字段，保留本地的同步状态与待删除队列。
  AppSettings applySyncConfig(Map<String, dynamic> cloudConfig) {
    final remote = AppSettings.fromJson(cloudConfig);
    return AppSettings(
      themeColorValue: remote.themeColorValue,
      backgroundColorValue: remote.backgroundColorValue,
      homeReminderPriorityThreshold: remote.homeReminderPriorityThreshold,
      recordSubTodoCreatedAt: remote.recordSubTodoCreatedAt,
      renameAttachmentsOnUpload: remote.renameAttachmentsOnUpload,
      keepAttachmentExtensionOnRename: remote.keepAttachmentExtensionOnRename,
      autoLockEnabled: remote.autoLockEnabled,
      serverTypes: remote.serverTypes,
      syncProvider: remote.syncProvider,
      syncDirectoryPath: remote.syncDirectoryPath,
      webDavUrl: remote.webDavUrl,
      webDavUsername: remote.webDavUsername,
      selfHostedUrl: remote.selfHostedUrl,
      s3Endpoint: remote.s3Endpoint,
      s3Region: remote.s3Region,
      s3Bucket: remote.s3Bucket,
      s3Prefix: remote.s3Prefix,
      pendingAttachmentDeletes: pendingAttachmentDeletes,
      syncRevision: syncRevision,
      syncLocalHash: syncLocalHash,
      lastSyncedAt: lastSyncedAt,
      configSyncHash: configSyncHash,
      lastConfigUpdatedAt: lastConfigUpdatedAt,
    );
  }

  AppSettings copyWith({
    int? themeColorValue,
    int? backgroundColorValue,
    ProjectPriority? homeReminderPriorityThreshold,
    bool? recordSubTodoCreatedAt,
    bool? renameAttachmentsOnUpload,
    bool? keepAttachmentExtensionOnRename,
    bool? autoLockEnabled,
    List<String>? serverTypes,
    SyncProviderType? syncProvider,
    String? syncDirectoryPath,
    String? webDavUrl,
    String? webDavUsername,
    String? selfHostedUrl,
    String? s3Endpoint,
    String? s3Region,
    String? s3Bucket,
    String? s3Prefix,
    List<String>? pendingAttachmentDeletes,
    String? syncRevision,
    String? syncLocalHash,
    DateTime? lastSyncedAt,
    String? configSyncHash,
    DateTime? lastConfigUpdatedAt,
    bool clearSyncState = false,
  }) => AppSettings(
    themeColorValue: themeColorValue ?? this.themeColorValue,
    backgroundColorValue: backgroundColorValue ?? this.backgroundColorValue,
    homeReminderPriorityThreshold:
        homeReminderPriorityThreshold ?? this.homeReminderPriorityThreshold,
    recordSubTodoCreatedAt:
        recordSubTodoCreatedAt ?? this.recordSubTodoCreatedAt,
    renameAttachmentsOnUpload:
        renameAttachmentsOnUpload ?? this.renameAttachmentsOnUpload,
    keepAttachmentExtensionOnRename:
        keepAttachmentExtensionOnRename ?? this.keepAttachmentExtensionOnRename,
    autoLockEnabled: autoLockEnabled ?? this.autoLockEnabled,
    serverTypes: serverTypes ?? this.serverTypes,
    syncProvider: syncProvider ?? this.syncProvider,
    syncDirectoryPath: syncDirectoryPath ?? this.syncDirectoryPath,
    webDavUrl: webDavUrl ?? this.webDavUrl,
    webDavUsername: webDavUsername ?? this.webDavUsername,
    selfHostedUrl: selfHostedUrl ?? this.selfHostedUrl,
    s3Endpoint: s3Endpoint ?? this.s3Endpoint,
    s3Region: s3Region ?? this.s3Region,
    s3Bucket: s3Bucket ?? this.s3Bucket,
    s3Prefix: s3Prefix ?? this.s3Prefix,
    pendingAttachmentDeletes:
        pendingAttachmentDeletes ?? this.pendingAttachmentDeletes,
    syncRevision: clearSyncState ? null : syncRevision ?? this.syncRevision,
    syncLocalHash: clearSyncState ? null : syncLocalHash ?? this.syncLocalHash,
    lastSyncedAt: clearSyncState ? null : lastSyncedAt ?? this.lastSyncedAt,
    configSyncHash:
        clearSyncState ? null : configSyncHash ?? this.configSyncHash,
    lastConfigUpdatedAt: clearSyncState
        ? null
        : lastConfigUpdatedAt ?? this.lastConfigUpdatedAt,
  );
  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeColorValue == themeColorValue &&
      other.backgroundColorValue == backgroundColorValue &&
      other.homeReminderPriorityThreshold == homeReminderPriorityThreshold &&
      other.recordSubTodoCreatedAt == recordSubTodoCreatedAt &&
      other.renameAttachmentsOnUpload == renameAttachmentsOnUpload &&
      other.keepAttachmentExtensionOnRename ==
          keepAttachmentExtensionOnRename &&
      other.autoLockEnabled == autoLockEnabled &&
      _stringListsEqual(other.serverTypes, serverTypes) &&
      other.syncProvider == syncProvider &&
      other.syncDirectoryPath == syncDirectoryPath &&
      other.webDavUrl == webDavUrl &&
      other.webDavUsername == webDavUsername &&
      other.selfHostedUrl == selfHostedUrl &&
      other.s3Endpoint == s3Endpoint &&
      other.s3Region == s3Region &&
      other.s3Bucket == s3Bucket &&
      other.s3Prefix == s3Prefix &&
      _stringListsEqual(
        other.pendingAttachmentDeletes,
        pendingAttachmentDeletes,
      ) &&
      other.syncRevision == syncRevision &&
      other.syncLocalHash == syncLocalHash &&
      other.lastSyncedAt == lastSyncedAt &&
      other.configSyncHash == configSyncHash &&
      other.lastConfigUpdatedAt == lastConfigUpdatedAt;
  @override
  int get hashCode => Object.hashAll([
    themeColorValue,
    backgroundColorValue,
    homeReminderPriorityThreshold,
    recordSubTodoCreatedAt,
    renameAttachmentsOnUpload,
    keepAttachmentExtensionOnRename,
    autoLockEnabled,
    syncProvider,
    syncDirectoryPath,
    webDavUrl,
    webDavUsername,
    selfHostedUrl,
    s3Endpoint,
    s3Region,
    s3Bucket,
    s3Prefix,
    syncRevision,
    syncLocalHash,
    lastSyncedAt,
    configSyncHash,
    lastConfigUpdatedAt,
    Object.hashAll(serverTypes),
    Object.hashAll(pendingAttachmentDeletes),
  ]);
}

bool _stringListsEqual(List<String> first, List<String> second) {
  if (identical(first, second) || first.length != second.length) {
    return identical(first, second);
  }
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}

enum ProjectPriority {
  p0('高优先级'),
  p1('中'),
  p2('普通'),
  p3('低');

  const ProjectPriority(this.label);
  final String label;
  static ProjectPriority fromName(String name) =>
      ProjectPriority.values.firstWhere(
        (item) => item.name == name,
        orElse: () => ProjectPriority.p2,
      );
}
