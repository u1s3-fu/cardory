// 领域聚合根：CardoryData 聚合项目、待办与资产。

import 'asset_models.dart';
import 'cardory_enums.dart';
import 'project_models.dart';
import 'todo_models.dart';

/// 领域数据容器：聚合项目列表 [ProjectData]、待办 [TodoData]、
/// 资产 [AssetData] 与资产标签 [AssetTag]。
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
