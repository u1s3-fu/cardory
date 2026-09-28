// 日历选中日条目清单 + 范围筛选 + 截止任务清单（月视图底部区域）。

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../../domain/schedule_queries.dart';
import '../cardory_theme.dart';
import '../widgets/badges.dart';
import 'calendar_entry.dart';

/// 选中日的条目清单（周/日视图底部）：任务、资产到期与系统日程。
class DayEntryList extends StatelessWidget {
  const DayEntryList({
    super.key,
    required this.day,
    required this.entries,
    required this.onOpenTodo,
    required this.onOpenAssetDue,
  });

  final DateTime day;
  final List<CalendarEntry> entries;
  final Future<void> Function(CalendarEntry entry) onOpenTodo;
  final void Function(CalendarEntry entry) onOpenAssetDue;

  /// 与周/日视图网格相同的点击分发规则：
  /// 任务条目走任务详情，资产条目弹操作面板，系统日程条目不响应点击。
  void _handleTap(CalendarEntry entry) {
    if (entry.entityType == 'asset') {
      onOpenAssetDue(entry);
    } else if (entry.entityType != null) {
      onOpenTodo(entry);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${formatDate(day)} 的日程与任务（${entries.length}）',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: CardoryColors.gray900,
          ),
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '该日没有任务或日程。',
              style: TextStyle(fontSize: 13, color: CardoryColors.gray500),
            ),
          )
        else
          for (final entry in entries)
            // cardDecoration 容器的背景色会遮住 ListTile 的墨水涟漪，
            // 包一层透明 Material 承载涟漪（同项目详情页待办条目的处理）。
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                // 仅任务/资产条目响应点击；系统日程条目不响应。
                onTap: entry.entityType == null
                    ? null
                    : () => _handleTap(entry),
                leading: entry.isTask
                    ? PriorityBadge(priority: entry.priority)
                    : entry.entityType == 'asset'
                    ? Icon(
                        Icons.event_available_outlined,
                        size: 18,
                        color: CardoryColors.gray500,
                      )
                    : Icon(
                        Icons.event_outlined,
                        size: 18,
                        color: CardoryColors.gray500,
                      ),
                title: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: entry.isDone
                        ? CardoryColors.gray400
                        : CardoryColors.gray900,
                    decoration: entry.isDone
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                subtitle: Text(
                  entry.isAllDay
                      ? '全天'
                      : '${entry.start.hour.toString().padLeft(2, '0')}:${entry.start.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: CardoryColors.gray500,
                  ),
                ),
              ),
            ),
      ],
    ),
  );
}

/// 截止任务范围筛选（当天/本周/本月）。
class RangeSelector extends StatelessWidget {
  const RangeSelector({
    super.key,
    required this.range,
    required this.selectedDay,
    required this.onChanged,
  });

  final CalendarRange range;
  final DateTime selectedDay;
  final ValueChanged<CalendarRange> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = {
      CalendarRange.selectedDay: '当天',
      CalendarRange.week: '本周',
      CalendarRange.month: '本月',
    };
    return SegmentedButton<CalendarRange>(
      showSelectedIcon: false,
      segments: [
        for (final entry in labels.entries)
          ButtonSegment(value: entry.key, label: Text(entry.value)),
      ],
      selected: {range},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

/// 截止任务清单（月视图底部）。
class TaskList extends StatelessWidget {
  const TaskList({
    super.key,
    required this.tasks,
    required this.now,
    required this.emptyLabel,
    required this.onToggleTodo,
    required this.onOpenTodo,
  });

  final List<TodoData> tasks;
  final DateTime now;
  final String emptyLabel;
  final Future<TodoData> Function(TodoData todo) onToggleTodo;
  final Future<TodoData?> Function(TodoData todo) onOpenTodo;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '截止任务',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: CardoryColors.gray900,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${tasks.length} 项',
              style: TextStyle(fontSize: 12, color: CardoryColors.gray500),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              emptyLabel,
              style: TextStyle(fontSize: 13, color: CardoryColors.gray500),
            ),
          )
        else
          for (final todo in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onOpenTodo(todo),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Checkbox(
                          value: todo.done,
                          onChanged: (_) => onToggleTodo(todo),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          todo.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: todo.done
                                ? CardoryColors.gray400
                                : CardoryColors.gray900,
                            decoration: todo.done
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      PriorityBadge(priority: todo.priority),
                      const SizedBox(width: 8),
                      Text(
                        formatDate(todo.endDate!),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isOverdue(todo, now)
                              ? CardoryColors.error
                              : CardoryColors.gray500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    ),
  );
}
