// 月历视图：月份网格 + 日期范围筛选（当天/本周/本月）+ 任务日期编辑入口。

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../../domain/schedule_queries.dart';
import '../cardory_theme.dart';
import '../model_colors.dart';
import '../widgets/badges.dart';

/// 月历页面：显示某月每日截止任务标记，选中日期后按范围筛选任务清单；
/// 点击任务打开编辑对话框（含日期编辑）。
class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.todos,
    required this.now,
    required this.onToggleTodo,
    required this.onOpenTodo,
    this.onAddTodo,
  });

  final List<TodoData> todos;

  /// 当前时间（测试可注入固定值）。
  final DateTime now;
  final Future<TodoData> Function(TodoData todo) onToggleTodo;
  final Future<TodoData?> Function(TodoData todo) onOpenTodo;
  final Future<void> Function(DateTime day)? onAddTodo;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _selectedDay = localDayKey(widget.now);
  late DateTime _month = DateTime(_selectedDay.year, _selectedDay.month);
  CalendarRange _range = CalendarRange.selectedDay;

  @override
  void didUpdateWidget(CalendarPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.todos != oldWidget.todos && !mounted) return;
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay = day;
      if (day.year != _month.year || day.month != _month.month) {
        _month = DateTime(day.year, day.month);
      }
    });
  }

  /// 每日截止任务数（含已完成，已完成数量单独弱化）。
  Map<DateTime, List<TodoData>> get _todosByDay {
    final byDay = <DateTime, List<TodoData>>{};
    for (final todo in widget.todos) {
      final due = todo.endDate;
      if (due == null) continue;
      byDay.putIfAbsent(localDayKey(due), () => []).add(todo);
    }
    return byDay;
  }

  @override
  Widget build(BuildContext context) {
    final byDay = _todosByDay;
    final today = localDayKey(widget.now);
    final tasks = todosWithin(
      widget.todos,
      calendarRangeBounds(_range, _selectedDay),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MonthHeader(
          month: _month,
          onPrevious: () => _shiftMonth(-1),
          onNext: () => _shiftMonth(1),
          onToday: () => _selectDay(today),
        ),
        const SizedBox(height: 12),
        _MonthGrid(
          month: _month,
          selectedDay: _selectedDay,
          today: today,
          todosByDay: byDay,
          onSelectDay: _selectDay,
        ),
        const SizedBox(height: 16),
        _RangeSelector(
          range: _range,
          selectedDay: _selectedDay,
          onChanged: (range) => setState(() => _range = range),
        ),
        const SizedBox(height: 12),
        _TaskList(
          tasks: tasks,
          now: widget.now,
          emptyLabel: switch (_range) {
            CalendarRange.selectedDay => '该日没有截止任务',
            CalendarRange.week => '本周没有截止任务',
            CalendarRange.month => '本月没有截止任务',
          },
          onToggleTodo: widget.onToggleTodo,
          onOpenTodo: widget.onOpenTodo,
          onAddTodo: widget.onAddTodo == null
              ? null
              : () => widget.onAddTodo!(_selectedDay),
        ),
      ],
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        '${month.year} 年 ${month.month} 月',
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      const Spacer(),
      TextButton(onPressed: onToday, child: const Text('回到今天')),
      IconButton(
        tooltip: '上一月',
        onPressed: onPrevious,
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      IconButton(
        tooltip: '下一月',
        onPressed: onNext,
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ],
  );
}

/// 周一开头的 6 行月历网格。
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selectedDay,
    required this.today,
    required this.todosByDay,
    required this.onSelectDay,
  });

  final DateTime month;
  final DateTime selectedDay;
  final DateTime today;
  final Map<DateTime, List<TodoData>> todosByDay;
  final ValueChanged<DateTime> onSelectDay;

  static const _weekdayLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(month.year, month.month);
    // weekday: 1=周一 … 7=周日；偏移 = 月首之前的空格数。
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
                        todos: todosByDay[day] ?? const [],
                        onSelect: () => onSelectDay(day),
                      ),
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.todos,
    required this.onSelect,
  });

  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final List<TodoData> todos;
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
            if (todos.isNotEmpty)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final todo in todos.take(4))
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: todo.done
                            ? CardoryColors.gray300
                            : todo.priority.color,
                      ),
                    ),
                  if (todos.length > 4)
                    Text(
                      '+${todos.length - 4}',
                      style: TextStyle(
                        fontSize: 8,
                        color: CardoryColors.gray400,
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

class _RangeSelector extends StatelessWidget {
  const _RangeSelector({
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

class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.tasks,
    required this.now,
    required this.emptyLabel,
    required this.onToggleTodo,
    required this.onOpenTodo,
    this.onAddTodo,
  });

  final List<TodoData> tasks;
  final DateTime now;
  final String emptyLabel;
  final Future<TodoData> Function(TodoData todo) onToggleTodo;
  final Future<TodoData?> Function(TodoData todo) onOpenTodo;
  final VoidCallback? onAddTodo;

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
            const Spacer(),
            if (onAddTodo != null)
              TextButton.icon(
                onPressed: onAddTodo,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建'),
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
