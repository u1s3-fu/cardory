// 日历页：月视图 / 周视图 / 日视图 + 日期范围筛选 + 系统日历集成。
//
// - 月视图：月份网格，每日截止任务按优先级着色标记；
// - 周视图：7 列 × 24 小时时间网格，任务与系统日程按时间落位；
// - 日视图：单列 24 小时网格；
// - 系统日历：移动端读写系统日历（需授权），桌面端以 .ics 文件落地
//   （见 SystemCalendarService）。
//
// 视图子组件与公共类型拆分在同目录：calendar_entry / calendar_header /
// calendar_month_view / calendar_time_grid_view / calendar_entry_list /
// system_event_dialog；此处 re-export 公共类型以保持旧导入路径兼容。

import 'package:flutter/material.dart';

import '../../domain/calendar_push_registry.dart';
import '../../domain/cardory_models.dart';
import '../../domain/schedule_queries.dart';
import '../../services/system_calendar_service.dart';
import '../cardory_theme.dart';
import 'calendar_entry.dart';
import 'calendar_entry_list.dart';
import 'calendar_header.dart';
import 'calendar_month_view.dart';
import 'calendar_time_grid_view.dart';
import 'system_event_dialog.dart';

export 'calendar_entry.dart' show CalendarEntry, CalendarViewMode;
export 'system_event_dialog.dart' show SystemEventDialog, SystemEventDraft;

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.todos,
    required this.now,
    required this.onToggleTodo,
    required this.onOpenTodo,
    this.systemCalendar,
    this.calendarPushRegistry,
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

  /// 日历推送登记表：推送成功后登记事件，供删除资产/改期时回收；
  /// null 时推送不登记。
  final CalendarPushRegistry? calendarPushRegistry;

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
      if (write.success && write.eventId != null) {
        await _registerPushedEvent(due, write.eventId!);
      }
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

  /// 推送成功后写入登记表（资产删除/改期时由控制器对账回收）。
  Future<void> _registerPushedEvent(AssetDueEntry due, String eventId) async {
    final registry = widget.calendarPushRegistry;
    if (registry == null) return;
    try {
      final entries = await registry.load();
      entries[calendarPushRegistryKey(
        due.assetId,
        due.fieldKey,
      )] = CalendarPushRecord(
        eventId: eventId,
        date: due.date.toIso8601String().substring(0, 10),
        title: due.title,
      );
      await registry.save(entries);
    } catch (error) {
      // 登记失败只影响回收，不影响已写入的日程。
      debugPrint('Failed to record calendar push: $error');
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
        CalendarHeader(
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
            CalendarViewMode.month => MonthView(
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
            CalendarViewMode.week => TimeGridView(
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
            CalendarViewMode.day => TimeGridView(
              days: [_selectedDay],
              entriesFor: entriesOnDay,
              now: widget.now,
              onOpenTodo: _openTodoEntry,
              onOpenAssetDue: _openAssetDueEntry,
            ),
          },
        const SizedBox(height: 16),
        if (_viewMode == CalendarViewMode.month) ...[
          RangeSelector(
            range: _range,
            selectedDay: _selectedDay,
            onChanged: (range) => setState(() => _range = range),
          ),
          const SizedBox(height: 12),
          TaskList(
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
          DayEntryList(
            day: _selectedDay,
            entries: entriesOnDay(_selectedDay),
            onOpenTodo: _openTodoEntry,
            onOpenAssetDue: _openAssetDueEntry,
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
