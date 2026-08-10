/// 业务领域模型定义。
///
/// 顶层容器 [CardoryData] 聚合项目列表 [ProjectData]、待办 [TodoData]、
/// 资产 [AssetData] 和同步配置。同时包含 [AppSettings] 配置模型、
/// [SyncProviderType] 枚举以及 [newId] / [formatDate] 等工具函数。

enum SyncProviderType { none, directory, webdav, selfHosted }

class AppSettings {
  const AppSettings({
    this.themeColorValue = 0xFF6B62DF,
    this.backgroundColorValue = 0xFFF5F6FC,
    this.homeReminderPriorityThreshold = ProjectPriority.p2,
    this.recordSubTodoCreatedAt = false,
    this.autoLockEnabled = true,
    this.serverTypes = const [],
    this.dataPath = '',
    this.syncProvider = SyncProviderType.none,
    this.syncDirectoryPath = '',
    this.webDavUrl = '',
    this.webDavUsername = '',
    this.selfHostedUrl = '',
    this.syncRevision,
    this.syncLocalHash,
    this.lastSyncedAt,
  });

  final int themeColorValue;
  final int backgroundColorValue;
  final ProjectPriority homeReminderPriorityThreshold;
  final bool recordSubTodoCreatedAt;
  final bool autoLockEnabled;
  final List<String> serverTypes;
  final String dataPath;
  final SyncProviderType syncProvider;
  final String syncDirectoryPath;
  final String webDavUrl;
  final String webDavUsername;
  final String selfHostedUrl;
  final String? syncRevision;
  final String? syncLocalHash;
  final DateTime? lastSyncedAt;
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
    autoLockEnabled: json['autoLockEnabled'] as bool? ?? true,
    serverTypes: ((json['serverTypes'] as List?) ?? [])
        .whereType<String>()
        .map((type) => type.trim())
        .where((type) => type.isNotEmpty)
        .toList(),
    dataPath: json['dataPath'] as String? ?? '',
    syncProvider:
        SyncProviderType.values
            .where((value) => value.name == json['syncProvider'])
            .firstOrNull ??
        SyncProviderType.none,
    syncDirectoryPath: json['syncDirectoryPath'] as String? ?? '',
    webDavUrl: json['webDavUrl'] as String? ?? '',
    webDavUsername: json['webDavUsername'] as String? ?? '',
    selfHostedUrl: json['selfHostedUrl'] as String? ?? '',
    syncRevision: json['syncRevision'] as String?,
    syncLocalHash: json['syncLocalHash'] as String?,
    lastSyncedAt: DateTime.tryParse(json['lastSyncedAt'] as String? ?? ''),
  );
  Map<String, dynamic> toJson() => {
    'themeColorValue': themeColorValue,
    'backgroundColorValue': backgroundColorValue,
    'homeReminderPriorityThreshold': homeReminderPriorityThreshold.name,
    'recordSubTodoCreatedAt': recordSubTodoCreatedAt,
    'autoLockEnabled': autoLockEnabled,
    'serverTypes': serverTypes,
    'dataPath': dataPath,
    'syncProvider': syncProvider.name,
    'syncDirectoryPath': syncDirectoryPath,
    'webDavUrl': webDavUrl,
    'webDavUsername': webDavUsername,
    'selfHostedUrl': selfHostedUrl,
    'syncRevision': syncRevision,
    'syncLocalHash': syncLocalHash,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
  };
  AppSettings copyWith({
    int? themeColorValue,
    int? backgroundColorValue,
    ProjectPriority? homeReminderPriorityThreshold,
    bool? recordSubTodoCreatedAt,
    bool? autoLockEnabled,
    List<String>? serverTypes,
    String? dataPath,
    SyncProviderType? syncProvider,
    String? syncDirectoryPath,
    String? webDavUrl,
    String? webDavUsername,
    String? selfHostedUrl,
    String? syncRevision,
    String? syncLocalHash,
    DateTime? lastSyncedAt,
    bool clearSyncState = false,
  }) => AppSettings(
    themeColorValue: themeColorValue ?? this.themeColorValue,
    backgroundColorValue: backgroundColorValue ?? this.backgroundColorValue,
    homeReminderPriorityThreshold:
        homeReminderPriorityThreshold ?? this.homeReminderPriorityThreshold,
    recordSubTodoCreatedAt:
        recordSubTodoCreatedAt ?? this.recordSubTodoCreatedAt,
    autoLockEnabled: autoLockEnabled ?? this.autoLockEnabled,
    serverTypes: serverTypes ?? this.serverTypes,
    dataPath: dataPath ?? this.dataPath,
    syncProvider: syncProvider ?? this.syncProvider,
    syncDirectoryPath: syncDirectoryPath ?? this.syncDirectoryPath,
    webDavUrl: webDavUrl ?? this.webDavUrl,
    webDavUsername: webDavUsername ?? this.webDavUsername,
    selfHostedUrl: selfHostedUrl ?? this.selfHostedUrl,
    syncRevision: clearSyncState ? null : syncRevision ?? this.syncRevision,
    syncLocalHash: clearSyncState ? null : syncLocalHash ?? this.syncLocalHash,
    lastSyncedAt: clearSyncState ? null : lastSyncedAt ?? this.lastSyncedAt,
  );
  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeColorValue == themeColorValue &&
      other.backgroundColorValue == backgroundColorValue &&
      other.homeReminderPriorityThreshold == homeReminderPriorityThreshold &&
      other.recordSubTodoCreatedAt == recordSubTodoCreatedAt &&
      other.autoLockEnabled == autoLockEnabled &&
      _stringListsEqual(other.serverTypes, serverTypes) &&
      other.dataPath == dataPath &&
      other.syncProvider == syncProvider &&
      other.syncDirectoryPath == syncDirectoryPath &&
      other.webDavUrl == webDavUrl &&
      other.webDavUsername == webDavUsername &&
      other.selfHostedUrl == selfHostedUrl &&
      other.syncRevision == syncRevision &&
      other.syncLocalHash == syncLocalHash &&
      other.lastSyncedAt == lastSyncedAt;
  @override
  int get hashCode => Object.hash(
    themeColorValue,
    backgroundColorValue,
    homeReminderPriorityThreshold,
    recordSubTodoCreatedAt,
    autoLockEnabled,
    Object.hashAll(serverTypes),
    dataPath,
    syncProvider,
    syncDirectoryPath,
    webDavUrl,
    webDavUsername,
    selfHostedUrl,
    syncRevision,
    syncLocalHash,
    lastSyncedAt,
  );
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

class CardoryData {
  const CardoryData({
    required this.projects,
    required this.todos,
    this.assets = const [],
  });
  const CardoryData.empty()
    : projects = const [],
      todos = const [],
      assets = const [];

  final List<ProjectData> projects;
  final List<TodoData> todos;
  final List<AssetData> assets;

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

  factory CardoryData.fromJson(Map<String, dynamic> json) => CardoryData(
    projects: ((json['projects'] as List?) ?? [])
        .map((item) => ProjectData.fromJson(item as Map<String, dynamic>))
        .toList(),
    todos: ((json['todos'] as List?) ?? [])
        .map((item) => TodoData.fromJson(item as Map<String, dynamic>))
        .toList(),
    assets: ((json['assets'] as List?) ?? [])
        .map((item) => AssetData.fromJson(item as Map<String, dynamic>))
        .toList(),
  );
  CardoryData copyWith({
    List<ProjectData>? projects,
    List<TodoData>? todos,
    List<AssetData>? assets,
  }) => CardoryData(
    projects: projects ?? this.projects,
    todos: todos ?? this.todos,
    assets: assets ?? this.assets,
  );
  Map<String, dynamic> toJson() => {
    'projects': projects.map((item) => item.toJson()).toList(),
    'todos': todos.map((item) => item.toJson()).toList(),
    'assets': assets.map((item) => item.toJson()).toList(),
  };
}

enum AssetType { software, hardware }

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
  });

  final String id;
  final String title;
  final String description;
  final DateTime? startDate;
  final DateTime? endDate;
  final ProjectPriority priority;
  final ProjectStage stage;
  final List<ProjectProgressEntry> progressEntries;
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
  }) => ProjectData(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    startDate: startDate ?? this.startDate,
    endDate: endDate ?? this.endDate,
    priority: priority ?? this.priority,
    stage: stage ?? this.stage,
    progressEntries: progressEntries ?? this.progressEntries,
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

double readProgress(Object? value) =>
    (value as num? ?? 0).clamp(0, 1).toDouble();
String formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String formatDateTime(DateTime date) =>
    '${formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
String newId() => DateTime.now().microsecondsSinceEpoch.toString();
