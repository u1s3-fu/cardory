// 业务领域模型定义。
//
// 顶层容器 [CardoryData] 聚合项目列表 [ProjectData]、待办 [TodoData]、
// 资产 [AssetData] 和同步配置。同时包含 [AppSettings] 配置模型、
// [SyncProviderType] 枚举以及 [newId] / [formatDate] 等工具函数。
import 'app_settings.dart';
export 'app_settings.dart';

class CardoryData {
  const CardoryData({
    required this.projects,
    required this.todos,
    this.assets = const [],
    this.assetTags = const [],
  });
  const CardoryData.empty()
    : projects = const [],
      todos = const [],
      assets = const [],
      assetTags = const [];

  final List<ProjectData> projects;
  final List<TodoData> todos;
  final List<AssetData> assets;
  final List<AssetTag> assetTags;

  factory CardoryData.seed() => CardoryData(
    projects: [
      ProjectData(
        id: 'project-cardory',
        title: 'Cardory 桌面端',
        description: '实现看板主页、项目详情、进度记录和本地数据保存。',
        priority: ProjectPriority.p0,
        stage: ProjectStage.doing,
        progressEntries: [
          ProjectProgressEntry(
            id: 'progress-cardory-1',
            note: '完成本地 JSON 保存和看板主页。',
            progress: 0.45,
            createdAt: DateTime(2026, 7, 29),
          ),
          ProjectProgressEntry(
            id: 'progress-cardory-2',
            note: '改为点击项目进入详情页记录进度。',
            progress: 0.62,
            createdAt: DateTime(2026, 7, 29),
          ),
        ],
      ),
      ProjectData(
        id: 'project-sync',
        title: '同步目录方案',
        description: '配置数据同步位置、本地存储路径和同步策略。',
        priority: ProjectPriority.p1,
        stage: ProjectStage.planned,
        progressEntries: [
          ProjectProgressEntry(
            id: 'progress-sync-1',
            note: '确定使用本地文件优先，不自建云后端。',
            progress: 0.35,
            createdAt: DateTime(2026, 7, 29),
          ),
        ],
      ),
    ],
    todos: [
      TodoData(
        id: 'todo-home',
        title: '完善项目详情页',
        description: '补充详情区与待办交互。',
        startDate: DateTime(2026, 7, 29),
        endDate: DateTime(2026, 8, 5),
        projectId: 'project-cardory',
        projectTitle: 'Cardory 桌面端',
        priority: ProjectPriority.p0,
        done: false,
        subTodos: const [
          SubTodoData(id: 'subtodo-home-1', content: '整理详情页信息结构', done: true),
          SubTodoData(id: 'subtodo-home-2', content: '加入项目待办区', done: false),
        ],
      ),
      TodoData(
        id: 'todo-sync',
        title: '后续增加选择数据目录',
        description: '优化数据目录选择体验。',
        startDate: DateTime(2026, 7, 29),
        endDate: DateTime(2026, 8, 8),
        projectId: 'project-sync',
        projectTitle: '同步目录方案',
        priority: ProjectPriority.p1,
        done: false,
        subTodos: const [
          SubTodoData(id: 'subtodo-sync-1', content: '选择本地数据目录', done: false),
          SubTodoData(id: 'subtodo-sync-2', content: '提示同步冲突风险', done: false),
        ],
      ),
    ],
  );

  factory CardoryData.fromJson(Map<String, dynamic> json) {
    final projectJson = ((json['projects'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final assetJson = ((json['assets'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();
    final legacyAttachments = <String, List<AttachmentData>>{};
    for (final asset in assetJson) {
      final projectId = asset['projectId'] as String? ?? '';
      final attachments = (asset['attachments'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AttachmentData.fromJson)
          .toList();
      if (attachments.isNotEmpty) {
        legacyAttachments.putIfAbsent(projectId, () => []).addAll(attachments);
      }
    }

    final projects = projectJson.map(ProjectData.fromJson).map((project) {
      final legacy = legacyAttachments[project.id] ?? const <AttachmentData>[];
      if (legacy.isEmpty) return project;
      final ids = project.attachments.map((item) => item.id).toSet();
      return project.copyWith(
        attachments: [
          ...project.attachments,
          ...legacy.where((item) => ids.add(item.id)),
        ],
      );
    }).toList();
    final projectIds = projects.map((project) => project.id).toSet();
    final orphanedAttachments = legacyAttachments.entries
        .where((entry) => !projectIds.contains(entry.key))
        .expand((entry) => entry.value)
        .toList();
    if (orphanedAttachments.isNotEmpty) {
      const baseId = 'project-recovered-attachments';
      var recoveryId = baseId;
      var suffix = 2;
      while (projectIds.contains(recoveryId)) {
        recoveryId = '$baseId-$suffix';
        suffix++;
      }
      projects.add(
        ProjectData(
          id: recoveryId,
          title: '待整理附件',
          description: '由旧版本中无法匹配所属项目的附件自动恢复，请检查后重新归档。',
          priority: ProjectPriority.p2,
          stage: ProjectStage.planned,
          progressEntries: const [],
          attachments: orphanedAttachments,
        ),
      );
    }

    return CardoryData(
      projects: projects,
      todos: ((json['todos'] as List?) ?? [])
          .map((item) => TodoData.fromJson(item as Map<String, dynamic>))
          .toList(),
      assets: assetJson.map(AssetData.fromJson).toList(),
      assetTags: ((json['assetTags'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AssetTag.fromJson)
          .toList(),
    );
  }
  CardoryData copyWith({
    List<ProjectData>? projects,
    List<TodoData>? todos,
    List<AssetData>? assets,
    List<AssetTag>? assetTags,
  }) => CardoryData(
    projects: projects ?? this.projects,
    todos: todos ?? this.todos,
    assets: assets ?? this.assets,
    assetTags: assetTags ?? this.assetTags,
  );
  Map<String, dynamic> toJson() => {
    'projects': projects.map((item) => item.toJson()).toList(),
    'todos': todos.map((item) => item.toJson()).toList(),
    'assets': assets.map((item) => item.toJson()).toList(),
    'assetTags': assetTags.map((item) => item.toJson()).toList(),
  };
}

enum AssetType { software, hardware }

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

class ProjectData {
  const ProjectData({
    required this.id,
    required this.title,
    required this.description,
    this.startDate,
    this.endDate,
    required this.priority,
    required this.stage,
    required this.progressEntries,
    this.attachments = const [],
    this.categories = const [],
  });

  final String id;
  final String title;
  final String description;
  final DateTime? startDate;
  final DateTime? endDate;
  final ProjectPriority priority;
  final ProjectStage stage;
  final List<ProjectProgressEntry> progressEntries;
  final List<AttachmentData> attachments;
  final List<AttachmentCategory> categories;
  double get progress =>
      progressEntries.isEmpty ? 0 : progressEntries.last.progress;

  factory ProjectData.fromJson(Map<String, dynamic> json) {
    final entries = ((json['progressEntries'] as List?) ?? [])
        .map(
          (item) => ProjectProgressEntry.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    final id = json['id'] as String? ?? newId();
    return ProjectData(
      id: id,
      title: json['title'] as String? ?? '未命名项目',
      description: json['description'] as String? ?? '',
      startDate: DateTime.tryParse(json['startDate'] as String? ?? ''),
      endDate: DateTime.tryParse(json['endDate'] as String? ?? ''),
      priority: ProjectPriority.fromName(json['priority'] as String? ?? 'p2'),
      stage: ProjectStage.fromName(json['stage'] as String? ?? 'planned'),
      progressEntries: entries,
      attachments: (json['attachments'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AttachmentData.fromJson)
          .toList(),
      categories: ((json['categories'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(AttachmentCategory.fromJson)
          .toList(),
    );
  }

  ProjectData copyWith({
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    ProjectPriority? priority,
    ProjectStage? stage,
    List<ProjectProgressEntry>? progressEntries,
    List<AttachmentData>? attachments,
    List<AttachmentCategory>? categories,
  }) => ProjectData(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    priority: priority ?? this.priority,
    stage: stage ?? this.stage,
    progressEntries: progressEntries ?? this.progressEntries,
    attachments: attachments ?? this.attachments,
    categories: categories ?? this.categories,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'startDate': startDate?.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'priority': priority.name,
    'stage': stage.name,
    'progressEntries': progressEntries.map((item) => item.toJson()).toList(),
    'attachments': attachments.map((item) => item.toJson()).toList(),
    'categories': categories.map((item) => item.toJson()).toList(),
  };
}

class ProjectProgressEntry {
  const ProjectProgressEntry({
    required this.id,
    required this.note,
    required this.progress,
    required this.createdAt,
  });
  final String id;
  final String note;
  final double progress;
  final DateTime createdAt;
  factory ProjectProgressEntry.fromJson(Map<String, dynamic> json) =>
      ProjectProgressEntry(
        id: json['id'] as String? ?? newId(),
        note: json['note'] as String? ?? '',
        progress: readProgress(json['progress']),
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'note': note,
    'progress': progress,
    'createdAt': createdAt.toIso8601String(),
  };
}

class TodoData {
  const TodoData({
    required this.id,
    required this.title,
    this.description = '',
    this.startDate,
    this.endDate,
    required this.projectId,
    required this.projectTitle,
    required this.priority,
    required this.done,
    this.subTodos = const [],
  });
  final String id;
  final String title;
  final String description;
  final DateTime? startDate;
  final DateTime? endDate;
  final String projectId;
  final String projectTitle;
  final ProjectPriority priority;
  final bool done;
  final List<SubTodoData> subTodos;
  String get dateRangeText {
    if (startDate == null && endDate == null) return '未设置日期';
    if (startDate != null && endDate != null) {
      return '${formatDate(startDate!)} 至 ${formatDate(endDate!)}';
    }
    if (startDate != null) return '开始 ${formatDate(startDate!)}';
    return '截止 ${formatDate(endDate!)}';
  }

  factory TodoData.fromJson(Map<String, dynamic> json) => TodoData(
    id: json['id'] as String? ?? newId(),
    title: json['title'] as String? ?? '未命名待办',
    description: json['description'] as String? ?? '',
    startDate: DateTime.tryParse(json['startDate'] as String? ?? ''),
    endDate: DateTime.tryParse(json['endDate'] as String? ?? ''),
    projectId: json['projectId'] as String? ?? '',
    projectTitle: json['projectTitle'] as String? ?? '未关联项目',
    priority: ProjectPriority.fromName(json['priority'] as String? ?? 'p2'),
    done: json['done'] as bool? ?? false,
    subTodos: ((json['subTodos'] as List?) ?? [])
        .map((item) => SubTodoData.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
  TodoData copyWith({
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    String? projectId,
    String? projectTitle,
    ProjectPriority? priority,
    bool? done,
    List<SubTodoData>? subTodos,
  }) => TodoData(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    projectId: projectId ?? this.projectId,
    projectTitle: projectTitle ?? this.projectTitle,
    priority: priority ?? this.priority,
    done: done ?? this.done,
    subTodos: subTodos ?? this.subTodos,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'startDate': startDate?.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'projectId': projectId,
    'projectTitle': projectTitle,
    'priority': priority.name,
    'done': done,
    'subTodos': subTodos.map((item) => item.toJson()).toList(),
  };
}

class SubTodoData {
  const SubTodoData({
    required this.id,
    required this.content,
    required this.done,
    this.createdAt,
    this.dueAt,
  });
  final String id;
  final String content;
  final bool done;
  final DateTime? createdAt;
  final DateTime? dueAt;
  factory SubTodoData.fromJson(Map<String, dynamic> json) => SubTodoData(
    id: json['id'] as String? ?? newId(),
    content: json['content'] as String? ?? '',
    done: json['done'] as bool? ?? false,
    createdAt: _readSubTodoCreatedAt(json),
    dueAt: DateTime.tryParse(json['dueAt'] as String? ?? ''),
  );
  SubTodoData copyWith({
    String? content,
    bool? done,
    DateTime? createdAt,
    DateTime? dueAt,
    bool clearDueAt = false,
  }) => SubTodoData(
    id: id,
    content: content ?? this.content,
    done: done ?? this.done,
    createdAt: createdAt ?? this.createdAt,
    dueAt: clearDueAt ? null : dueAt ?? this.dueAt,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'done': done,
    'createdAt': createdAt?.toIso8601String(),
    'dueAt': dueAt?.toIso8601String(),
  };
}

DateTime? _readSubTodoCreatedAt(Map<String, dynamic> json) {
  final stored = DateTime.tryParse(json['createdAt'] as String? ?? '');
  if (stored != null) return stored;

  final microseconds = int.tryParse(json['id'] as String? ?? '');
  if (microseconds == null) return null;
  try {
    return DateTime.fromMicrosecondsSinceEpoch(microseconds);
  } on ArgumentError {
    return null;
  }
}

enum ProjectStage {
  planned('计划中'),
  doing('进行中'),
  review('待验收'),
  done('已完成');

  const ProjectStage(this.label);
  final String label;
  static ProjectStage fromName(String name) => ProjectStage.values.firstWhere(
    (item) => item.name == name,
    orElse: () => ProjectStage.planned,
  );
}

double readProgress(Object? value) =>
    (value as num? ?? 0).clamp(0, 1).toDouble();
String formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String formatDateTime(DateTime date) =>
    '${formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
String newId() => DateTime.now().microsecondsSinceEpoch.toString();
