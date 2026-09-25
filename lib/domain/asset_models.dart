// 资产领域模型：资产分类、附件与资产实体。

import 'asset_template.dart';
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

  AttachmentCategory copyWith({String? name}) =>
      AttachmentCategory(id: id, name: name ?? this.name, createdAt: createdAt);

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
    this.assetId,
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

  /// 关联的同项目资产 id；null 表示未关联。
  final String? assetId;
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
    assetId: json['assetId'] as String?,
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
    String? assetId,
    bool clearAssetId = false,
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
    categoryIds: clearCategoryIds
        ? const []
        : (categoryIds ?? this.categoryIds),
    assetId: clearAssetId ? null : (assetId ?? this.assetId),
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
    if (assetId != null) 'assetId': assetId,
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
  const AssetTag({required this.id, required this.name, this.createdAt});

  final String id;
  final String name;
  final DateTime? createdAt;

  factory AssetTag.fromJson(Map<String, dynamic> json) => AssetTag(
    id: json['id'] as String? ?? newId(),
    name: json['name'] as String? ?? '未命名标签',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? ''),
  );

  AssetTag copyWith({String? name}) =>
      AssetTag(id: id, name: name ?? this.name, createdAt: createdAt);

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
    this.templateId = '',
    this.customFields = const {},
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

  /// 资产承载的模板 id；'' 表示旧数据或未指定，读路径会归一化补齐。
  final String templateId;

  /// 模板自定义字段值；旧数据由 [normalizeAssetTemplate] 从旧顶层键回填。
  final Map<String, String> customFields;
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
    templateId: json['templateId'] as String? ?? '',
    customFields: ((json['customFields'] as Map?) ?? const {}).map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    ),
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
    String? templateId,
    Map<String, String>? customFields,
    bool clearCustomFields = false,
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
    templateId: templateId ?? this.templateId,
    customFields: clearCustomFields
        ? const {}
        : (customFields ?? this.customFields),
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
    if (templateId.isNotEmpty) 'templateId': templateId,
    if (customFields.isNotEmpty) 'customFields': customFields,
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

/// 读时归一化：为旧数据补齐 templateId，并把旧顶层键回填为模板 customFields。
///
/// - [asset.templateId] 为空时按 `typeTag == asset.type.name` 匹配模板补齐；
///   已显式设置 templateId 的资产不再改写（未知 id 也原样保留）；
/// - customFields 缺失的模板键从旧顶层字段取值（version/port/path/
///   serialNumber/network/serverType 与内置模板 key 同名，天然命中）。
AssetData normalizeAssetTemplate(
  AssetData asset,
  List<AssetTemplate> templates,
) {
  AssetTemplate? template;
  if (asset.templateId.isNotEmpty) {
    for (final candidate in templates) {
      if (candidate.id == asset.templateId) template = candidate;
    }
  } else {
    for (final candidate in templates) {
      if (candidate.typeTag == asset.type.name) {
        template = candidate;
        break;
      }
    }
  }
  if (template == null) return asset;
  final resolvedId = asset.templateId.isEmpty ? template.id : asset.templateId;
  final custom = Map<String, String>.of(asset.customFields);
  for (final field in template.fields) {
    if (custom.containsKey(field.key)) continue;
    final legacy = _legacyFieldValue(asset, field.key);
    if (legacy != null) custom[field.key] = legacy;
  }
  if (resolvedId == asset.templateId &&
      _sameStringMap(custom, asset.customFields)) {
    return asset;
  }
  return asset.copyWith(templateId: resolvedId, customFields: custom);
}

/// 旧数据顶层字段（对应 metadataJson 旧顶层键）的取值；空值不回填。
String? _legacyFieldValue(AssetData asset, String key) {
  switch (key) {
    case 'version':
      return asset.version.isEmpty ? null : asset.version;
    case 'port':
      return asset.port.isEmpty ? null : asset.port;
    case 'path':
      return asset.path.isEmpty ? null : asset.path;
    case 'serialNumber':
      return asset.serialNumber.isEmpty ? null : asset.serialNumber;
    case 'network':
      return asset.network.isEmpty ? null : asset.network;
    case 'serverType':
      return asset.serverType.isEmpty ? null : asset.serverType;
  }
  return null;
}

bool _sameStringMap(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
