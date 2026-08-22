// 项目领域模型：项目实体与进度记录。

import 'asset_models.dart';
import 'cardory_enums.dart';
import 'cardory_utils.dart';

/// 项目实体，包含进度记录、附件与附件分类。
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

/// 项目进度记录。
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
