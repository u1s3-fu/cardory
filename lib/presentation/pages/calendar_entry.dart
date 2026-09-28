// 日历条目公共类型：视图模式与统一条目模型（任务截止 / 资产到期 / 系统日程）。

import '../../domain/cardory_models.dart';
import '../../domain/schedule_queries.dart';

enum CalendarViewMode { month, week, day }

/// 统一的日历条目：任务截止（endDate）或系统日程。
class CalendarEntry {
  const CalendarEntry({
    required this.title,
    required this.start,
    required this.end,
    required this.isTask,
    this.isDone = false,
    this.priority = ProjectPriority.p2,
    this.note = '',
    this.entityType,
    this.entityId,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final bool isTask;
  final bool isDone;
  final ProjectPriority priority;
  final String note;

  /// 关联实体的类型与 id（如任务条目为 'todo' + todo.id）；
  /// 系统日程等非应用内实体为 null。
  final String? entityType;
  final String? entityId;

  bool get isAllDay =>
      localDayKey(start) == localDayKey(end) &&
      start.hour == 0 &&
      start.minute == 0 &&
      end.hour == 0 &&
      end.minute == 0;
}
