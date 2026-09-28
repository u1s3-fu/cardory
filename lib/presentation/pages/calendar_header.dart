// 日历页头：月份/日期标题 + 翻页箭头 + 视图切换 + 回到今天。

import 'package:flutter/material.dart';

import 'calendar_entry.dart';

/// 日历页头。窄屏（< 560）降级为两行布局（第一行标题 + 翻页箭头、
/// 第二行视图切换 + 回到今天），宽屏单行。
class CalendarHeader extends StatelessWidget {
  const CalendarHeader({
    super.key,
    required this.month,
    required this.viewMode,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onViewModeChanged,
  });

  final DateTime month;
  final CalendarViewMode viewMode;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<CalendarViewMode> onViewModeChanged;

  String get _titleText => switch (viewMode) {
    CalendarViewMode.month => '${month.year} 年 ${month.month} 月',
    CalendarViewMode.week => '周视图',
    CalendarViewMode.day => '日视图',
  };

  @override
  Widget build(BuildContext context) {
    final title = Text(
      _titleText,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    );
    final navButtons = [
      IconButton(
        tooltip: viewMode == CalendarViewMode.month ? '上一月' : '上一天/周',
        onPressed: onPrevious,
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      IconButton(
        tooltip: viewMode == CalendarViewMode.month ? '下一月' : '下一天/周',
        onPressed: onNext,
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ];
    final viewSwitcher = SegmentedButton<CalendarViewMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: CalendarViewMode.month, label: Text('月')),
        ButtonSegment(value: CalendarViewMode.week, label: Text('周')),
        ButtonSegment(value: CalendarViewMode.day, label: Text('日')),
      ],
      selected: {viewMode},
      onSelectionChanged: (selection) => onViewModeChanged(selection.first),
    );
    final todayButton = TextButton(
      onPressed: onToday,
      child: const Text('回到今天'),
    );

    // 窄屏单行放不下（标题+回到今天+视图切换+翻页箭头），降级为两行：
    // 第一行「标题 + 翻页箭头」，第二行「视图切换 + 回到今天」。
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [title, const Spacer(), ...navButtons]),
              const SizedBox(height: 4),
              Row(children: [viewSwitcher, const Spacer(), todayButton]),
            ],
          );
        }
        return Row(
          children: [
            title,
            const Spacer(),
            todayButton,
            viewSwitcher,
            ...navButtons,
          ],
        );
      },
    );
  }
}
