// 日历周/日视图：24 小时时间网格，任务与系统日程按时间落位。

import 'package:flutter/material.dart';

import '../../domain/schedule_queries.dart';
import '../cardory_theme.dart';
import '../model_colors.dart';
import 'calendar_entry.dart';

/// 周（7 列）/ 日（单列）视图共用的时间网格：全天条目置顶，
/// 定时条目按时间重叠自动分道。
class TimeGridView extends StatelessWidget {
  const TimeGridView({
    super.key,
    required this.days,
    required this.entriesFor,
    required this.now,
    required this.onOpenTodo,
    required this.onOpenAssetDue,
  });

  final List<DateTime> days;
  final List<CalendarEntry> Function(DateTime day) entriesFor;
  final DateTime now;
  final Future<void> Function(CalendarEntry entry) onOpenTodo;
  final void Function(CalendarEntry entry) onOpenAssetDue;

  static const _hourHeight = 46.0;
  static const _minColumnWidth = 130.0;
  static const _timeColumnWidth = 44.0;

  @override
  Widget build(BuildContext context) {
    // 统一固定列宽 + 水平滚动：内部行使用定宽子项而非 Expanded，
    // 避免无界宽度约束下的 flex 冲突；日视图单列时宽度自适应撑满由
    // 外层列宽取 max(视口可用, 最小列宽) 实现。
    final availableWidth = MediaQuery.sizeOf(context).width - 56;
    final dayColumnWidth = days.length == 1
        ? (availableWidth < _minColumnWidth ? _minColumnWidth : availableWidth)
        : _minColumnWidth;
    // 容器左右 padding 24 + 边框 2（Border.all 1px 两侧）。
    final gridWidth = _timeColumnWidth + days.length * dayColumnWidth + 26;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: gridWidth,
        child: Container(
          decoration: cardDecoration(),
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              SizedBox(
                height: 30,
                child: Row(
                  children: [
                    const SizedBox(width: _timeColumnWidth),
                    for (final day in days)
                      SizedBox(
                        width: dayColumnWidth,
                        child: Center(
                          child: Text(
                            '周${_weekdayName(day.weekday)} ${day.day}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: localDayKey(now) == day
                                  ? Theme.of(context).colorScheme.primary
                                  : CardoryColors.gray600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 24 * _hourHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _timeColumnWidth,
                      child: Column(
                        children: [
                          for (var hour = 0; hour < 24; hour++)
                            SizedBox(
                              height: _hourHeight,
                              child: Text(
                                '$hour:00',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: CardoryColors.gray400,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (final day in days)
                      SizedBox(
                        width: dayColumnWidth,
                        child: _DayHourColumn(
                          day: day,
                          entries: entriesFor(day),
                          now: now,
                          hourHeight: _hourHeight,
                          onOpenTodo: onOpenTodo,
                          onOpenAssetDue: onOpenAssetDue,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _weekdayName(int weekday) => switch (weekday) {
    1 => '一',
    2 => '二',
    3 => '三',
    4 => '四',
    5 => '五',
    6 => '六',
    _ => '日',
  };
}

class _DayHourColumn extends StatelessWidget {
  const _DayHourColumn({
    required this.day,
    required this.entries,
    required this.now,
    required this.hourHeight,
    required this.onOpenTodo,
    required this.onOpenAssetDue,
  });

  final DateTime day;
  final List<CalendarEntry> entries;
  final DateTime now;
  final double hourHeight;
  final Future<void> Function(CalendarEntry entry) onOpenTodo;
  final void Function(CalendarEntry entry) onOpenAssetDue;

  static bool overlapsDay(CalendarEntry entry, DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return entry.end.isAfter(dayStart) && entry.start.isBefore(dayEnd);
  }

  /// 条目点击分发：任务条目走任务详情，资产条目弹操作面板
  /// （见 _openAssetDueEntry），系统日程条目（entityType 为 null）不响应点击。
  void _handleTap(CalendarEntry entry) {
    if (entry.entityType == 'asset') {
      onOpenAssetDue(entry);
    } else if (entry.entityType != null) {
      onOpenTodo(entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 单日条目按时间重叠分道，避免互相遮挡。
    final positioned = _layoutEntries(
      entries.where((entry) {
        final sameDay =
            localDayKey(entry.start) == day || overlapsDay(entry, day);
        return sameDay && !entry.isAllDay;
      }).toList(),
    );
    final allDay = entries
        .where((entry) => entry.isAllDay || localDayKey(entry.start) == day)
        .toList();

    return Container(
      height: 24 * hourHeight,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: CardoryColors.gray100, width: 0.5),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var hour = 0; hour < 24; hour++)
            Positioned(
              left: 0,
              right: 0,
              top: hour * hourHeight,
              child: Container(
                height: hourHeight,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: CardoryColors.gray100,
                      width: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 2,
            right: 2,
            top: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (allDay.isNotEmpty)
                  for (final entry in allDay.take(3))
                    _EntryChip(
                      entry: entry,
                      label: '全天 · ${entry.title}',
                      height: 18,
                      // 仅任务/资产条目响应点击；系统日程透传（onTap: null）。
                      onTap: entry.entityType == null
                          ? null
                          : () => _handleTap(entry),
                    ),
              ],
            ),
          ),
          for (final layout in positioned)
            Positioned(
              left: 2 + layout.column * 6,
              right: 2 - layout.column * 6,
              top: layout.top,
              child: _EntryChip(
                entry: layout.entry,
                label: '${_timeText(layout.entry.start)} ${layout.entry.title}',
                height: layout.height,
                // 仅任务/资产条目响应点击；系统日程透传（onTap: null）。
                onTap: layout.entry.entityType == null
                    ? null
                    : () => _handleTap(layout.entry),
              ),
            ),
        ],
      ),
    );
  }

  static String _timeText(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  List<_PositionedEntry> _layoutEntries(List<CalendarEntry> entries) {
    final positioned = <_PositionedEntry>[];
    for (final entry in entries) {
      final startMinutes = entry.start.hour * 60 + entry.start.minute;
      final endMinutes = entry.end.hour * 60 + entry.end.minute;
      final clampedEnd = endMinutes <= startMinutes
          ? startMinutes + 30
          : endMinutes;
      final top = startMinutes / 60 * hourHeight;
      final height = ((clampedEnd - startMinutes) / 60 * hourHeight).clamp(
        20.0,
        24 * hourHeight - top,
      );
      var column = 0;
      while (positioned.any(
        (item) =>
            item.column == column &&
            item.top < top + height &&
            item.top + item.height > top,
      )) {
        column++;
      }
      positioned.add(
        _PositionedEntry(
          entry: entry,
          top: top,
          height: height,
          column: column,
        ),
      );
    }
    return positioned;
  }
}

class _PositionedEntry {
  const _PositionedEntry({
    required this.entry,
    required this.top,
    required this.height,
    required this.column,
  });

  final CalendarEntry entry;
  final double top;
  final double height;
  final int column;
}

class _EntryChip extends StatelessWidget {
  const _EntryChip({
    required this.entry,
    required this.label,
    required this.height,
    this.onTap,
  });

  final CalendarEntry entry;
  final String label;
  final double height;

  /// 点击回调（任务条目打开任务详情；null 时仅吸收点击不透传）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isAsset = entry.entityType == 'asset';
    return GestureDetector(
      onTap: onTap ?? (entry.isTask ? () {} : null),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          // 资产条目用中性色，不占用任务优先级色。
          color: isAsset
              ? CardoryColors.gray100
              : entry.isTask
              ? entry.priority.color.withValues(alpha: 0.18)
              : CardoryColors.primarySoft,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isAsset
                ? CardoryColors.gray300
                : entry.isTask
                ? entry.priority.color.withValues(alpha: 0.5)
                : CardoryColors.gray300,
            width: 0.6,
          ),
        ),
        child: Row(
          children: [
            if (isAsset) ...[
              Icon(
                Icons.event_available_outlined,
                size: 11,
                color: CardoryColors.gray500,
              ),
              const SizedBox(width: 3),
            ],
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    decoration: entry.isDone
                        ? TextDecoration.lineThrough
                        : null,
                    color: entry.isTask
                        ? CardoryColors.gray800
                        : CardoryColors.gray700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
