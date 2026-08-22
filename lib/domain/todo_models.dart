// 待办领域模型：待办与子待办。

import 'cardory_enums.dart';
import 'cardory_utils.dart';

/// 待办实体。
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

/// 子待办。
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
