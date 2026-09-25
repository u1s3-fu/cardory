// 日历页：月视图 / 周视图 / 日视图 + 日期范围筛选 + 系统日历集成。
//
// - 月视图：月份网格，每日截止任务按优先级着色标记；
// - 周视图：7 列 × 24 小时时间网格，任务与系统日程按时间落位；
// - 日视图：单列 24 小时网格；
// - 系统日历：移动端读写系统日历（需授权），桌面端以 .ics 文件落地
//   （见 SystemCalendarService）。

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../../domain/schedule_queries.dart';
import '../../services/system_calendar_service.dart';
import '../cardory_theme.dart';
import '../model_colors.dart';
import '../widgets/badges.dart';

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

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.todos,
    required this.now,
    required this.onToggleTodo,
    required this.onOpenTodo,
    this.systemCalendar,
    this.assetDues = const [],
    this.onOpenAssetDue,
  });

  final List<TodoData> todos;

  /// 当前时间（测试可注入固定值）。
  final DateTime now;
  final Future<TodoData> Function(TodoData todo) onToggleTodo;
  final Future<TodoData?> Function(TodoData todo) onOpenTodo;

  /// 系统日历服务；null 时隐藏系统日程相关功能（仅显示应用内任务）。
  final SystemCalendarService? systemCalendar;

  /// 资产到期条目（P3 数据源，见 assetDueEntries）；并入三视图的全天条目区。
  final List<AssetDueEntry> assetDues;

  /// 点击资产到期条目回调；null 时安全忽略。
  final void Function(AssetDueEntry entry)? onOpenAssetDue;

  /// 任务条目构建（公开以便测试与后续复用）：条目携带实体标识，
  /// 周/日视图点击回查时按 [CalendarEntry.entityId] 匹配任务。
  static List<CalendarEntry> buildTaskEntries(List<TodoData> todos) => [
    for (final todo in todos)
      if (todo.endDate != null)
        CalendarEntry(
          title: todo.title,
          start: todo.endDate!,
          end: todo.endDate!,
          isTask: true,
          isDone: todo.done,
          priority: todo.priority,
          entityType: 'todo',
          entityId: todo.id,
        ),
  ];

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _selectedDay = localDayKey(widget.now);
  late DateTime _month = DateTime(_selectedDay.year, _selectedDay.month);
  CalendarRange _range = CalendarRange.selectedDay;
  CalendarViewMode _viewMode = CalendarViewMode.month;

  List<SystemCalendarEvent> _systemEvents = [];
  String? _systemCalendarError;
  bool _loadingSystemEvents = false;

  DateTime get _now => localDayKey(widget.now);

  @override
  void initState() {
    super.initState();
    _loadSystemEvents();
  }

  /// 当前视图可见的日期区间（用于加载系统日程）。
  (DateTime, DateTime) get _visibleRange => switch (_viewMode) {
    CalendarViewMode.month => calendarRangeBounds(
      CalendarRange.month,
      DateTime(_month.year, _month.month, 15),
    ),
    CalendarViewMode.week => calendarRangeBounds(
      CalendarRange.week,
      _selectedDay,
    ),
    CalendarViewMode.day => (_selectedDay, _selectedDay),
  };

  Future<void> _loadSystemEvents() async {
    final service = widget.systemCalendar;
    if (service == null) return;
    final (start, end) = _visibleRange;
    setState(() => _loadingSystemEvents = true);
    try {
      final events = await service.loadEvents(start, end);
      if (!mounted) return;
      setState(() {
        _systemEvents = events;
        _systemCalendarError = null;
        _loadingSystemEvents = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _systemCalendarError = '系统日程读取失败：$error';
        _loadingSystemEvents = false;
      });
    }
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _loadSystemEvents();
  }

  void _selectDay(DateTime day) {
    setState(() {
      _selectedDay = day;
      if (day.year != _month.year || day.month != _month.month) {
        _month = DateTime(day.year, day.month);
      }
    });
    _loadSystemEvents();
  }

  /// 应用内任务 → 日历条目（截止时刻；0 点视为全天）。
  List<CalendarEntry> get _taskEntries =>
      CalendarPage.buildTaskEntries(widget.todos);

  /// 资产到期 → 全天日历条目（entityType 'asset'，中性色渲染，不占优先级色）。
  List<CalendarEntry> get _assetEntries => [
    for (final due in widget.assetDues)
      CalendarEntry(
        title: due.title,
        start: due.date,
        end: due.date,
        isTask: false,
        note: due.fieldLabel,
        entityType: 'asset',
        entityId: due.assetId,
      ),
  ];

  /// 点击任务条目后按 entityId 回查任务；找不到时安全忽略。
  Future<void> _openTodoEntry(CalendarEntry entry) async {
    final todo = widget.todos
        .where((item) => item.id == entry.entityId)
        .firstOrNull;
    if (todo == null) return;
    await widget.onOpenTodo(todo);
  }

  /// 点击资产条目后按 entityId + 字段标签 + 日期回查到期条目；
  /// 命中后弹操作面板（查看资产 / 加入系统日历）；找不到时安全忽略。
  void _openAssetDueEntry(CalendarEntry entry) {
    final due = widget.assetDues
        .where(
          (item) =>
              item.assetId == entry.entityId &&
              item.fieldLabel == entry.note &&
              localDayKey(item.date) == localDayKey(entry.start),
        )
        .firstOrNull;
    if (due == null) return;
    _showAssetDuePanel(due);
  }

  /// 资产到期操作面板：「查看资产」走 onOpenAssetDue；
  /// 「加入系统日历」直接写系统日程（systemCalendar 为 null 时隐藏该按钮）。
  Future<void> _showAssetDuePanel(AssetDueEntry due) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(due.title),
        content: Text('${due.fieldLabel} · ${formatDate(due.date)}'),
        actions: [
          if (widget.systemCalendar != null)
            TextButton(
              key: const Key('push-system-calendar-button'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _pushAssetDueToSystemCalendar(due);
              },
              child: const Text('加入系统日历'),
            ),
          TextButton(
            key: const Key('view-asset-button'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              widget.onOpenAssetDue?.call(due);
            },
            child: const Text('查看资产'),
          ),
        ],
      ),
    );
  }

  /// 把资产到期写入系统日历：title 用条目标题（含资产名），
  /// start 为到期日零点、end 为次日零点（满足全天事件判定），
  /// note 拼资产名与字段标签。
  Future<void> _pushAssetDueToSystemCalendar(AssetDueEntry due) async {
    final service = widget.systemCalendar;
    if (service == null) return;
    final day = DateTime(due.date.year, due.date.month, due.date.day);
    try {
      final write = await service.createEvent(
        title: due.title,
        start: day,
        end: day.add(const Duration(days: 1)),
        note: '${due.assetName} · ${due.fieldLabel}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            write.success
                ? '已加入系统日历'
                : (write.detail.isEmpty ? '加入系统日历失败。' : write.detail),
          ),
        ),
      );
      await _loadSystemEvents();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('加入系统日历失败：$error')));
    }
  }

  List<CalendarEntry> get _systemEntries => [
    for (final event in _systemEvents)
      CalendarEntry(
        title: event.title,
        start: event.start,
        end: event.end,
        isTask: false,
        note: event.note,
      ),
  ];

  List<CalendarEntry> entriesOnDay(DateTime day) {
    final entries = [
      ..._taskEntries.where((entry) => isDueOnTask(entry, day)),
      ..._assetEntries.where((entry) => isDueOnTask(entry, day)),
      ..._systemEntries.where((entry) => overlapsDay(entry, day)),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return entries;
  }

  static bool isDueOnTask(CalendarEntry entry, DateTime day) =>
      localDayKey(entry.start) == day;

  static bool overlapsDay(CalendarEntry entry, DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return entry.end.isAfter(dayStart) && entry.start.isBefore(dayEnd);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CalendarHeader(
          month: _month,
          viewMode: _viewMode,
          onPrevious: () => switch (_viewMode) {
            CalendarViewMode.month => _shiftMonth(-1),
            CalendarViewMode.week => _selectDay(
              _selectedDay.subtract(const Duration(days: 7)),
            ),
            CalendarViewMode.day => _selectDay(
              _selectedDay.subtract(const Duration(days: 1)),
            ),
          },
          onNext: () => switch (_viewMode) {
            CalendarViewMode.month => _shiftMonth(1),
            CalendarViewMode.week => _selectDay(
              _selectedDay.add(const Duration(days: 7)),
            ),
            CalendarViewMode.day => _selectDay(
              _selectedDay.add(const Duration(days: 1)),
            ),
          },
          onToday: () => _selectDay(localDayKey(widget.now)),
          onViewModeChanged: (mode) {
            setState(() => _viewMode = mode);
            _loadSystemEvents();
          },
        ),
        if (widget.systemCalendar != null && _systemCalendarError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _systemCalendarError!,
              style: TextStyle(fontSize: 11.5, color: CardoryColors.error),
            ),
          ),
        const SizedBox(height: 12),
        if (_loadingSystemEvents)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          switch (_viewMode) {
            CalendarViewMode.month => _MonthView(
              month: _month,
              selectedDay: _selectedDay,
              today: _now,
              taskEntries: _taskEntries,
              assetEntries: _assetEntries,
              hasSystemEntries: (day) => entriesOnDay(
                day,
              ).any((entry) => !entry.isTask && entry.entityType == null),
              showAssetLegend: widget.assetDues.isNotEmpty,
              hasSystemCalendar: widget.systemCalendar != null,
              onSelectDay: _selectDay,
            ),
            CalendarViewMode.week => _TimeGridView(
              days: [
                for (var i = 0; i < 7; i++)
                  calendarRangeBounds(
                    CalendarRange.week,
                    _selectedDay,
                  ).$1.add(Duration(days: i)),
              ],
              entriesFor: entriesOnDay,
              now: widget.now,
              onOpenTodo: _openTodoEntry,
              onOpenAssetDue: _openAssetDueEntry,
            ),
            CalendarViewMode.day => _TimeGridView(
              days: [_selectedDay],
              entriesFor: entriesOnDay,
              now: widget.now,
              onOpenTodo: _openTodoEntry,
              onOpenAssetDue: _openAssetDueEntry,
            ),
          },
        const SizedBox(height: 16),
        if (_viewMode == CalendarViewMode.month) ...[
          _RangeSelector(
            range: _range,
            selectedDay: _selectedDay,
            onChanged: (range) => setState(() => _range = range),
          ),
          const SizedBox(height: 12),
          _TaskList(
            tasks: todosWithin(
              widget.todos,
              calendarRangeBounds(_range, _selectedDay),
            ),
            now: widget.now,
            emptyLabel: switch (_range) {
              CalendarRange.selectedDay => '该日没有截止任务',
              CalendarRange.week => '本周没有截止任务',
              CalendarRange.month => '本月没有截止任务',
            },
            onToggleTodo: widget.onToggleTodo,
            onOpenTodo: widget.onOpenTodo,
          ),
        ] else ...[
          _DayEntryList(
            day: _selectedDay,
            entries: entriesOnDay(_selectedDay),
            onOpenTodo: widget.onOpenTodo,
          ),
        ],
        if (widget.systemCalendar != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: _createSystemEvent,
              icon: const Icon(Icons.event_available_outlined, size: 18),
              label: const Text('新建日程到系统日历'),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _createSystemEvent() async {
    final service = widget.systemCalendar;
    if (service == null) return;
    final result = await showDialog<SystemEventDraft>(
      context: context,
      builder: (_) => SystemEventDialog(initialDay: _selectedDay),
    );
    if (result == null || !mounted) return;
    final write = await service.createEvent(
      title: result.title,
      start: result.start,
      end: result.end,
      note: result.note,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          write.success
              ? (write.detail.isEmpty ? '日程已创建。' : write.detail)
              : (write.detail.isEmpty ? '日程创建失败。' : write.detail),
        ),
      ),
    );
    await _loadSystemEvents();
  }
}

// ---- 页头：月份导航 + 视图切换 ----

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
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
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        _titleText,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      const Spacer(),
      TextButton(onPressed: onToday, child: const Text('回到今天')),
      SegmentedButton<CalendarViewMode>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: CalendarViewMode.month, label: Text('月')),
          ButtonSegment(value: CalendarViewMode.week, label: Text('周')),
          ButtonSegment(value: CalendarViewMode.day, label: Text('日')),
        ],
        selected: {viewMode},
        onSelectionChanged: (selection) => onViewModeChanged(selection.first),
      ),
      if (viewMode == CalendarViewMode.month) ...[
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
      ] else ...[
        IconButton(
          tooltip: '上一天/周',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton(
          tooltip: '下一天/周',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    ],
  );
}

// ---- 月视图 ----

class _MonthView extends StatelessWidget {
  const _MonthView({
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

// ---- 周 / 日视图：24 小时时间网格 ----

class _TimeGridView extends StatelessWidget {
  const _TimeGridView({
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

// ---- 选中日条目清单 ----

class _DayEntryList extends StatelessWidget {
  const _DayEntryList({
    required this.day,
    required this.entries,
    required this.onOpenTodo,
  });

  final DateTime day;
  final List<CalendarEntry> entries;
  final Future<TodoData?> Function(TodoData todo) onOpenTodo;

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
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
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
                  decoration: entry.isDone ? TextDecoration.lineThrough : null,
                ),
              ),
              subtitle: Text(
                entry.isAllDay
                    ? '全天'
                    : '${entry.start.hour.toString().padLeft(2, '0')}:${entry.start.minute.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 11.5, color: CardoryColors.gray500),
              ),
            ),
      ],
    ),
  );
}

// ---- 范围选择与任务清单（月视图用） ----

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

// ---- 新建系统日程对话框 ----

class SystemEventDraft {
  const SystemEventDraft({
    required this.title,
    required this.start,
    required this.end,
    this.note = '',
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String note;
}

class SystemEventDialog extends StatefulWidget {
  const SystemEventDialog({super.key, required this.initialDay});

  final DateTime initialDay;

  @override
  State<SystemEventDialog> createState() => _SystemEventDialogState();
}

class _SystemEventDialogState extends State<SystemEventDialog> {
  late final TextEditingController _titleController = TextEditingController();
  late final TextEditingController _noteController = TextEditingController();
  late int _startMinutes = 9 * 60;
  late int _durationMinutes = 60;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool start}) async {
    final base = start ? _startMinutes : _startMinutes + _durationMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (base ~/ 60) % 24, minute: base % 60),
    );
    if (picked == null || !mounted) return;
    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      if (start) {
        _startMinutes = minutes;
        if (_durationMinutes <= 0) _durationMinutes = 60;
      } else {
        _durationMinutes = minutes - _startMinutes;
        if (_durationMinutes <= 0) _durationMinutes += 24 * 60;
      }
    });
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写日程标题。')));
      return;
    }
    final day = widget.initialDay;
    final start = DateTime(
      day.year,
      day.month,
      day.day,
      _startMinutes ~/ 60,
      _startMinutes % 60,
    );
    final end = start.add(Duration(minutes: _durationMinutes));
    Navigator.of(context).pop(
      SystemEventDraft(
        title: title,
        start: start,
        end: end,
        note: _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新建日程'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: '日程标题'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(start: true),
                  child: Text(
                    '开始 ${_startMinutes ~/ 60}:${(_startMinutes % 60).toString().padLeft(2, '0')}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(start: false),
                  child: Text(
                    '结束 ${(_startMinutes + _durationMinutes) ~/ 60 % 24}:${(_startMinutes + _durationMinutes) % 60}',
                  ),
                ),
              ),
            ],
          ),
          Text(
            '日期：${formatDate(widget.initialDay)} · 时长 $_durationMinutes 分钟',
            style: TextStyle(fontSize: 12, color: CardoryColors.gray500),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(labelText: '备注（可选）'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('保存')),
    ],
  );
}
