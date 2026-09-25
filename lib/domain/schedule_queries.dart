// 今日任务聚合与日历日期范围工具。
//
// “某一天”一律以本地时区的日期分量（年/月/日）判定：任务截止日期可能以
// UTC 时刻存储（数据库行）或本地时刻解析（JSON），统一 toLocal 后取日期键。

import 'asset_template.dart';
import 'cardory_models.dart';

/// 本地时区的日期键（丢弃时分秒）。
DateTime localDayKey(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// 判断任务 [todo] 是否在 [day]（本地日期键）截止。
bool isDueOnDay(TodoData todo, DateTime day) =>
    todo.endDate != null && localDayKey(todo.endDate!) == day;

/// 任务是否已逾期：未完成且截止日早于 [now] 所在日。
bool isOverdue(TodoData todo, DateTime now) =>
    !todo.done &&
    todo.endDate != null &&
    localDayKey(todo.endDate!).isBefore(localDayKey(now));

/// 聚合优先级排序：p0 最前，其次截止时间早者在前，同截止按标题。
int compareTodoForSchedule(TodoData a, TodoData b) {
  final byPriority = a.priority.index.compareTo(b.priority.index);
  if (byPriority != 0) return byPriority;
  final aDue = a.endDate ?? a.startDate;
  final bDue = b.endDate ?? b.startDate;
  if (aDue != null && bDue != null) {
    final byDue = aDue.compareTo(bDue);
    if (byDue != 0) return byDue;
  }
  if (aDue != null) return -1;
  if (bDue != null) return 1;
  return a.title.compareTo(b.title);
}

/// 今日任务聚合结果：逾期清单与今日截止清单（均已按 [compareTodoForSchedule] 排序）。
class TodayTaskAggregate {
  const TodayTaskAggregate({required this.overdue, required this.dueToday});

  final List<TodoData> overdue;
  final List<TodoData> dueToday;

  bool get isEmpty => overdue.isEmpty && dueToday.isEmpty;
  int get totalCount => overdue.length + dueToday.length;
}

/// 把未完成任务聚合为「逾期」与「今日截止」两组。
TodayTaskAggregate aggregateTodayTasks(
  List<TodoData> todos, {
  required DateTime now,
}) {
  final today = localDayKey(now);
  final overdue = <TodoData>[];
  final dueToday = <TodoData>[];
  for (final todo in todos) {
    if (todo.done) continue;
    if (isDueOnDay(todo, today)) {
      dueToday.add(todo);
    } else if (isOverdue(todo, now)) {
      overdue.add(todo);
    }
  }
  overdue.sort(compareTodoForSchedule);
  dueToday.sort(compareTodoForSchedule);
  return TodayTaskAggregate(overdue: overdue, dueToday: dueToday);
}

/// 日历筛选范围：选中日 / 本周 / 本月。
enum CalendarRange { selectedDay, week, month }

/// [CalendarRange] 对应的本地日期区间（含首尾日）。
(DateTime start, DateTime end) calendarRangeBounds(
  CalendarRange range,
  DateTime selectedDay,
) {
  final day = localDayKey(selectedDay);
  switch (range) {
    case CalendarRange.selectedDay:
      return (day, day);
    case CalendarRange.week:
      // 周一为一周开始。
      final weekday = day.weekday; // 1=周一 … 7=周日
      final monday = day.subtract(Duration(days: weekday - 1));
      return (monday, monday.add(const Duration(days: 6)));
    case CalendarRange.month:
      final first = DateTime(day.year, day.month);
      return (
        first,
        DateTime(day.year, day.month + 1).subtract(const Duration(days: 1)),
      );
  }
}

/// 任务是否截止于 [bounds] 区间内（含首尾日）。
bool isDueWithin(TodoData todo, (DateTime start, DateTime end) bounds) {
  final due = todo.endDate;
  if (due == null) return false;
  final day = localDayKey(due);
  final (start, end) = bounds;
  return !day.isBefore(start) && !day.isAfter(end);
}

/// 筛选并排序区间内的任务（含已完成，供日历视图浏览）。
List<TodoData> todosWithin(
  List<TodoData> todos,
  (DateTime start, DateTime end) bounds,
) {
  final result = todos.where((todo) => isDueWithin(todo, bounds)).toList()
    ..sort(compareTodoForSchedule);
  return result;
}

/// 资产到期条目：扫描每个资产模板中 remind 的 date 字段。
/// 一个资产可产出多条（如域名注册到期 + SSL 到期）。
class AssetDueEntry {
  const AssetDueEntry({
    required this.assetId,
    required this.assetName,
    required this.date,
    required this.fieldLabel,
    required this.title,
  });

  final String assetId;
  final String assetName;

  /// 本地日期键（0 点）。
  final DateTime date;

  /// 字段标签，例：「到期日」。
  final String fieldLabel;

  /// 展示标题，例：「到期日 · example.com」。
  final String title;
}

/// 生成 [bounds]（含首尾日）内的资产到期条目；bounds 为 null 时返回全部。
///
/// 对每个资产按其 templateId 匹配模板，扫描模板中 remind 的 date 字段，
/// 从 `customFields[key]` 解析 `yyyy-MM-dd`（`DateTime.tryParse`，失败静默跳过）。
/// 结果按 date 升序、同日按资产名排序。
List<AssetDueEntry> assetDueEntries(
  List<AssetData> assets,
  List<AssetTemplate> templates, {
  (DateTime start, DateTime end)? bounds,
}) {
  final templateById = {
    for (final template in templates) template.id: template,
  };
  final entries = <AssetDueEntry>[];
  for (final asset in assets) {
    final template = templateById[asset.templateId];
    if (template == null) continue;
    for (final field in template.fields) {
      if (field.kind != AssetFieldKind.date || !field.remind) continue;
      final raw = asset.customFields[field.key];
      if (raw == null || raw.isEmpty) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) continue;
      final day = localDayKey(parsed);
      final (start, end) = bounds ?? (day, day);
      if (day.isBefore(start) || day.isAfter(end)) continue;
      entries.add(
        AssetDueEntry(
          assetId: asset.id,
          assetName: asset.name,
          date: day,
          fieldLabel: field.label,
          title: '${field.label} · ${asset.name}',
        ),
      );
    }
  }
  entries.sort((a, b) {
    final byDate = a.date.compareTo(b.date);
    if (byDate != 0) return byDate;
    return a.assetName.compareTo(b.assetName);
  });
  return entries;
}
