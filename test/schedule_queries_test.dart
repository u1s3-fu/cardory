// 今日任务聚合与日历日期范围查询的单元测试。

import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/domain/schedule_queries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 13, 15, 30); // 周日

  TodoData todo({
    required String id,
    String title = '任务',
    DateTime? endDate,
    bool done = false,
    ProjectPriority priority = ProjectPriority.p2,
  }) => TodoData(
    id: id,
    title: title,
    projectId: 'project-1',
    projectTitle: '项目',
    priority: priority,
    done: done,
    endDate: endDate,
  );

  group('aggregateTodayTasks', () {
    test('分组逾期与今日截止，已完成不参与，按优先级与截止时间排序', () {
      final aggregate = aggregateTodayTasks([
        todo(id: 'overdue-p2', endDate: DateTime(2026, 9, 11)),
        todo(
          id: 'overdue-p0',
          endDate: DateTime(2026, 9, 10),
          priority: ProjectPriority.p0,
        ),
        todo(id: 'today-late', endDate: DateTime(2026, 9, 13, 18)),
        todo(id: 'today-early', endDate: DateTime(2026, 9, 13, 9)),
        todo(id: 'future', endDate: DateTime(2026, 9, 20)),
        todo(id: 'done-today', endDate: DateTime(2026, 9, 13), done: true),
        todo(id: 'no-date'),
      ], now: now);

      expect(aggregate.overdue.map((t) => t.id).toList(), [
        'overdue-p0',
        'overdue-p2',
      ]);
      expect(aggregate.dueToday.map((t) => t.id).toList(), [
        'today-early',
        'today-late',
      ]);
      expect(aggregate.totalCount, 4);
    });

    test('UTC 存储的截止日期按本地日期参与判定', () {
      // 本地 +8 时区下 2026-09-12 20:00+08 == 12:00Z 同日；
      // 用 UTC 时刻表示本地 9 月 12 日（逾期）。
      final utcOverdue = DateTime.utc(2026, 9, 12, 4); // 本地 12 日 12 点
      final aggregate = aggregateTodayTasks([
        todo(id: 'utc-overdue', endDate: utcOverdue),
      ], now: now);
      expect(aggregate.overdue.map((t) => t.id), ['utc-overdue']);
    });

    test('无任何任务时为空', () {
      expect(aggregateTodayTasks(const [], now: now).isEmpty, isTrue);
    });
  });

  group('calendarRangeBounds 与 todosWithin', () {
    final selected = DateTime(2026, 9, 9); // 周三

    test('当天区间只含选中日', () {
      final (start, end) = calendarRangeBounds(
        CalendarRange.selectedDay,
        selected,
      );
      expect(start, DateTime(2026, 9, 9));
      expect(end, DateTime(2026, 9, 9));
    });

    test('本周区间为周一到周日', () {
      final (start, end) = calendarRangeBounds(CalendarRange.week, selected);
      expect(start, DateTime(2026, 9, 7)); // 周一
      expect(end, DateTime(2026, 9, 13)); // 周日
    });

    test('本月区间覆盖整月', () {
      final (start, end) = calendarRangeBounds(CalendarRange.month, selected);
      expect(start, DateTime(2026, 9, 1));
      expect(end, DateTime(2026, 9, 30));
    });

    test('todosWithin 筛选区间内任务并按优先级排序', () {
      final result = todosWithin([
        todo(id: 'in-week', endDate: DateTime(2026, 9, 10)),
        todo(id: 'out-month', endDate: DateTime(2026, 10, 1)),
        todo(id: 'in-week-done', endDate: DateTime(2026, 9, 8), done: true),
        todo(id: 'no-date'),
      ], calendarRangeBounds(CalendarRange.week, selected));
      expect(result.map((t) => t.id).toList(), ['in-week-done', 'in-week']);
    });

    test('月末跨年月计算正确', () {
      final (start, end) = calendarRangeBounds(
        CalendarRange.month,
        DateTime(2026, 12, 15),
      );
      expect(start, DateTime(2026, 12, 1));
      expect(end, DateTime(2026, 12, 31));
    });
  });
}
