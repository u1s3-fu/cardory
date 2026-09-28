// 日历月视图：月份网格 + 每日任务/资产/系统日程标记 + 图例。

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../../domain/schedule_queries.dart';
import '../cardory_theme.dart';
import '../model_colors.dart';
import 'calendar_entry.dart';

/// 月视图：月份网格，每日截止任务按优先级着色标记，资产到期以中性图标标记。
class MonthView extends StatelessWidget {
  const MonthView({
    super.key,
    required this.month,
    required this.selectedDay,
    required this.today,
    required this.taskEntries,
    required this.assetEntries,
    required this.hasSystemEntries,
    required this.showAssetLegend,
    required this.hasSystemCalendar,
    required this.onSelectDay,
  });

  final DateTime month;
  final DateTime selectedDay;
  final DateTime today;
  final List<CalendarEntry> taskEntries;
  final List<CalendarEntry> assetEntries;
  final bool Function(DateTime day) hasSystemEntries;
  final bool showAssetLegend;
  final bool hasSystemCalendar;
  final ValueChanged<DateTime> onSelectDay;

  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  Map<DateTime, List<CalendarEntry>> get _entriesByDay {
    final byDay = <DateTime, List<CalendarEntry>>{};
    for (final entry in taskEntries) {
      byDay.putIfAbsent(localDayKey(entry.start), () => []).add(entry);
    }
    return byDay;
  }

  Map<DateTime, List<CalendarEntry>> get _assetEntriesByDay {
    final byDay = <DateTime, List<CalendarEntry>>{};
    for (final entry in assetEntries) {
      byDay.putIfAbsent(localDayKey(entry.start), () => []).add(entry);
    }
    return byDay;
  }

  @override
  Widget build(BuildContext context) {
    final byDay = _entriesByDay;
    final assetByDay = _assetEntriesByDay;
    final firstOfMonth = DateTime(month.year, month.month);
    final leadingBlanks = firstOfMonth.weekday - 1;
    final dayCount = DateTime(
      month.year,
      month.month + 1,
    ).difference(firstOfMonth).inDays;
    final cells = <DateTime?>[
      for (var i = 0; i < leadingBlanks; i++) null,
      for (var i = 0; i < dayCount; i++) firstOfMonth.add(Duration(days: i)),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: cardDecoration(),
      child: Column(
        children: [
          Row(
            children: [
              for (final label in _weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: CardoryColors.gray500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var row = 0; row < cells.length ~/ 7; row++)
            Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: switch (cells[row * 7 + col]) {
                      null => const SizedBox(height: 52),
                      final day => _DayCell(
                        key: ValueKey('calendar-day-$day'),
                        day: day,
                        isSelected: day == selectedDay,
                        isToday: day == today,
                        entries: byDay[day] ?? const [],
                        assetEntries: assetByDay[day] ?? const [],
                        hasSystemEntries: hasSystemEntries(day),
                        onSelect: () => onSelectDay(day),
                      ),
                    },
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              _LegendDot(color: ProjectPriority.p0.color, label: '任务'),
              if (hasSystemCalendar) ...[
                const SizedBox(width: 12),
                _LegendDot(color: CardoryColors.gray500, label: '系统日程'),
              ],
              if (showAssetLegend) ...[
                const SizedBox(width: 12),
                const _LegendAsset(label: '资产到期'),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// 月视图图例：色点 + 标签。
class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: CardoryColors.gray500)),
    ],
  );
}

/// 月视图图例：资产到期（中性色小图标，不占任务优先级色）。
class _LegendAsset extends StatelessWidget {
  const _LegendAsset({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.event_available_outlined,
        size: 12,
        color: CardoryColors.gray500,
      ),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: CardoryColors.gray500)),
    ],
  );
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.entries,
    required this.assetEntries,
    required this.hasSystemEntries,
    required this.onSelect,
  });

  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final List<CalendarEntry> entries;

  /// 当日资产到期条目（中性色小图标标记）。
  final List<CalendarEntry> assetEntries;
  final bool hasSystemEntries;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onSelect,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 52,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : isToday
                ? CardoryColors.gray400
                : Colors.transparent,
            width: isSelected || isToday ? 1.4 : 0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected || isToday
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: isSelected ? colorScheme.primary : CardoryColors.gray800,
              ),
            ),
            const SizedBox(height: 3),
            if (entries.isNotEmpty ||
                assetEntries.isNotEmpty ||
                hasSystemEntries)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final entry in entries.take(4))
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: entry.isDone
                            ? CardoryColors.gray300
                            : entry.priority.color,
                      ),
                    ),
                  for (final _ in assetEntries.take(2))
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Icon(
                        Icons.event_available_outlined,
                        size: 11,
                        color: CardoryColors.gray500,
                      ),
                    ),
                  if (hasSystemEntries)
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: CardoryColors.gray500,
                      ),
                    ),
                ],
              )
            else
              const SizedBox(height: 5),
          ],
        ),
      ),
    );
  }
}
