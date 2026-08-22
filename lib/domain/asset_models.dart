// 资产领域模型：资产分类、附件与资产实体。

import 'cardory_utils.dart';

/// 资产类型。
enum AssetType { software, hardware }

/// 附件类型。
enum AttachmentKind {
  image('图片'),
  document('文档'),
  archive('压缩包'),
  other('其他');

  const AttachmentKind(this.label);

  final String label;

  static AttachmentKind fromName(
    String? name, {
    required String fileName,
    String mimeType = '',
  }) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return infer(fileName, mimeType);
  }

  static AttachmentKind infer(String fileName, [String mimeType = '']) {
    final normalizedMime = mimeType.toLowerCase();
    if (normalizedMime.startsWith('image/')) return AttachmentKind.image;
    if (normalizedMime.contains('zip') ||
        normalizedMime.contains('compressed') ||
        normalizedMime.contains('archive')) {
      return AttachmentKind.archive;
    }
    final extension = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    if (AttachmentData._imageExtensions.contains(extension)) {
      return AttachmentKind.image;
    }
    if (AttachmentData._archiveExtensions.contains(extension)) {
      return AttachmentKind.archive;
    }
    if (AttachmentData._documentExtensions.contains(extension) ||
        normalizedMime.startsWith('text/') ||
        normalizedMime == 'application/pdf') {
      return AttachmentKind.document;
    }
    return AttachmentKind.other;
  }
}

/// 附件分类。
class AttachmentCategory {
  const AttachmentCategory({
    required this.id,
    required this.name,
    this.createdAt,
  });

  final String id;
  final String name;
  final DateTime? createdAt;

  factory AttachmentCategory.fromJson(Map<String, dynamic> json) =>
      AttachmentCategory(
        id: json['id'] as String? ?? newId(),
        name: json['name'] as String? ?? '未命名分类',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
      );

  AttachmentCategory copyWith({String? name}) => AttachmentCategory(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt?.toIso8601String(),
  };
}

/// 附件元数据。文件本体通过加密容器与附件仓库存储。
class AttachmentData {
  AttachmentData({
    required this.id,
    required this.fileName,
    this.storageKey = '',
    this.encryptionKey = '',
    this.size = 0,
    this.sha256 = '',
    this.mimeType = '',
    AttachmentKind? kind,
    this.note = '',
    required this.createdAt,
    this.categoryIds = const [],
    this.legacyFileBytes,
  }) : kind = kind ?? AttachmentKind.infer(fileName, mimeType);

  final String id;
  final String fileName;
  final String storageKey;
  final String encryptionKey;
  final int size;
  final String sha256;
  final String mimeType;
  final AttachmentKind kind;
  final String note;
  final DateTime createdAt;
  final List<String> categoryIds;
  final String? legacyFileBytes;

  bool get needsMigration => storageKey.isEmpty && legacyFileBytes != null;

  String get fileExtension =>
      fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';

  static const _imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'webp',
    'svg',
    'ico',
    'tiff',
    'tif',
  };
  static const _archiveExtensions = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2'};
  static const _documentExtensions = {
    'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'pdf',
    // WPS 专有格式
    'wps', 'et', 'dps',
  };

  factory AttachmentData.fromJson(Map<String, dynamic> json) => AttachmentData(
    id: json['id'] as String? ?? newId(),
    fileName: json['fileName'] as String? ?? 'unknown',
    storageKey: json['storageKey'] as String? ?? '',
    encryptionKey: json['encryptionKey'] as String? ?? '',
    size: json['size'] as int? ?? 0,
    sha256: json['sha256'] as String? ?? '',
    mimeType: json['mimeType'] as String? ?? '',
    kind: AttachmentKind.fromName(
      json['kind'] as String?,
      fileName: json['fileName'] as String? ?? 'unknown',
      mimeType: json['mimeType'] as String? ?? '',
    ),
    note: json['note'] as String? ?? '',
    createdAt: _readAttachmentCreatedAt(json),
    categoryIds: ((json['categoryIds'] as List?) ?? [])
        .whereType<String>()
        .toList(),
    legacyFileBytes: json['fileBytes'] as String?,
  );

  AttachmentData copyWith({
    String? fileName,
    String? storageKey,
    String? encryptionKey,
    int? size,
    String? sha256,
    String? mimeType,
    AttachmentKind? kind,
    String? note,
    DateTime? createdAt,
    List<String>? categoryIds,
    bool clearCategoryIds = false,
    String? legacyFileBytes,
  }) => AttachmentData(
    id: id,
    fileName: fileName ?? this.fileName,
    storageKey: storageKey ?? this.storageKey,
    encryptionKey: encryptionKey ?? this.encryptionKey,
    size: size ?? this.size,
    sha256: sha256 ?? this.sha256,
    mimeType: mimeType ?? this.mimeType,
    kind: kind ?? this.kind,
    note: note ?? this.note,
    createdAt: createdAt ?? this.createdAt,
    categoryIds: clearCategoryIds ? const [] : (categoryIds ?? this.categoryIds),
    legacyFileBytes: legacyFileBytes ?? this.legacyFileBytes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'storageKey': storageKey,
    'encryptionKey': encryptionKey,
    'size': size,
    'sha256': sha256,
    'mimeType': mimeType,
    'kind': kind.name,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
    'categoryIds': categoryIds,
    if (needsMigration) 'fileBytes': legacyFileBytes,
  };
}

DateTime _readAttachmentCreatedAt(Map<String, dynamic> json) {
  final stored = DateTime.tryParse(json['createdAt'] as String? ?? '');
  if (stored != null) return stored;

  final microseconds = int.tryParse(json['id'] as String? ?? '');
  if (microseconds != null) {
    try {
      return DateTime.fromMicrosecondsSinceEpoch(microseconds);
    } on ArgumentError {
      // 对格式异常的旧版元数据，回退到一个稳定的取值。
    }
  }
  return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
}

/// 资产标签。
class AssetTag {
  const AssetTag({
    required this.id,
    required this.name,
    this.createdAt,
  });

  final String id;
  final String name;
  final DateTime? createdAt;

  factory AssetTag.fromJson(Map<String, dynamic> json) => AssetTag(
    id: json['id'] as String? ?? newId(),
    name: json['name'] as String? ?? '未命名标签',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
  );

  AssetTag copyWith({String? name}) => AssetTag(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt?.toIso8601String(),
  };
}

/// 资产实体，支持软件/硬件两类资产。
class AssetData {
  const AssetData({
    required this.id,
    required this.type,
    required this.name,
    this.projectId = '',
    this.version = '',
    this.port = '',
    this.path = '',
    this.serialNumber = '',
    this.network = '',
    this.serverType = '',
    this.username = '',
    this.password = '',
    this.note = '',
    this.tagIds = const [],
    this.activities = const [],
  });

  final String id;
  final AssetType type;
  final String name;
  final String projectId;
  final String version;
  final String port;
  final String path;
  final String serialNumber;
  final String network;
  final String serverType;
  final String username;
  final String password;
  final String note;
  final List<String> tagIds;
  final List<AssetActivity> activities;

  factory AssetData.fromJson(Map<String, dynamic> json) => AssetData(
    id: json['id'] as String? ?? newId(),
    type: AssetType.values.firstWhere(
      (value) => value.name == json['type'],
      orElse: () => AssetType.software,
    ),
    name: json['name'] as String? ?? '未命名资产',
    projectId: json['projectId'] as String? ?? '',
    version: json['version'] as String? ?? '',
    port: json['port'] as String? ?? '',
    path: json['path'] as String? ?? '',
    serialNumber: json['serialNumber'] as String? ?? '',
    network: json['network'] as String? ?? '',
    serverType: json['serverType'] as String? ?? '',
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    note: json['note'] as String? ?? '',
    tagIds: ((json['tagIds'] as List?) ?? []).whereType<String>().toList(),
    activities: (json['activities'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(AssetActivity.fromJson)
        .toList(),
  );

  AssetData copyWith({
    AssetType? type,
    String? name,
    String? projectId,
    String? version,
    String? port,
    String? path,
    String? serialNumber,
    String? network,
    String? serverType,
    String? username,
    String? password,
    String? note,
    List<String>? tagIds,
    bool clearTagIds = false,
    List<AssetActivity>? activities,
  }) => AssetData(
    id: id,
    type: type ?? this.type,
    name: name ?? this.name,
    projectId: projectId ?? this.projectId,
    version: version ?? this.version,
    port: port ?? this.port,
    path: path ?? this.path,
    serialNumber: serialNumber ?? this.serialNumber,
    network: network ?? this.network,
    serverType: serverType ?? this.serverType,
    username: username ?? this.username,
    password: password ?? this.password,
    note: note ?? this.note,
    tagIds: clearTagIds ? const [] : (tagIds ?? this.tagIds),
    activities: activities ?? this.activities,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'projectId': projectId,
    'version': version,
    'port': port,
    'path': path,
    'serialNumber': serialNumber,
    'network': network,
    'serverType': serverType,
    'username': username,
    'password': password,
    'note': note,
    'tagIds': tagIds,
    'activities': activities.map((a) => a.toJson()).toList(),
  };
}

/// 资产变动类型。
enum AssetActivityKind {
  created,
  updated,
  deleted;

  static AssetActivityKind fromName(String name) =>
      AssetActivityKind.values.firstWhere(
        (value) => value.name == name,
        orElse: () => AssetActivityKind.updated,
      );
}

/// 资产变动记录。
class AssetActivity {
  const AssetActivity({
    required this.kind,
    required this.message,
    required this.timestamp,
  });

  final AssetActivityKind kind;
  final String message;
  final DateTime timestamp;

  factory AssetActivity.fromJson(Map<String, dynamic> json) => AssetActivity(
    kind: AssetActivityKind.fromName(json['kind'] as String? ?? 'updated'),
    message: json['message'] as String? ?? '',
    timestamp:
        DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
  };
}
