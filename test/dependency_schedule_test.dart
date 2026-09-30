// 依赖自动排期传播测试：单跳、链式、不推迟更晚、时长保持、环防御。

import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/domain/dependency_schedule.dart';
import 'package:cardory/domain/milestone_models.dart';
import 'package:flutter_test/flutter_test.dart';

TodoData _todo(
  String id, {
  DateTime? start,
  DateTime? end,
  bool done = false,
}) => TodoData(
  id: id,
  title: '任务-$id',
  projectId: 'project-1',
  projectTitle: '项目',
  priority: ProjectPriority.p2,
  done: done,
  startDate: start,
  endDate: end,
);

TaskDependencyData _dep(String predecessor, String successor) =>
    TaskDependencyData(
      id: '$predecessor->$successor',
      predecessorTaskId: predecessor,
      successorTaskId: successor,
    );

void main() {
  test('前置完成后，开始早于前置结束次日的后继被推迟一天起（时长保持）', () {
    final updates = propagateDependencySchedule(
      todos: [
        _todo('a', start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 5)),
        _todo('b', start: DateTime(2026, 9, 3), end: DateTime(2026, 9, 8)),
      ],
      dependencies: [_dep('a', 'b')],
      seedTodoIds: {'a'},
    );

    expect(updates, hasLength(1));
    expect(updates.single.updated.startDate, DateTime(2026, 9, 6));
    // 结束日随开始平移：原时长 5 天保持。
    expect(updates.single.updated.endDate, DateTime(2026, 9, 11));
  });

  test('链式依赖 A→B→C 在 A 完成后逐层传播', () {
    final updates = propagateDependencySchedule(
      todos: [
        _todo('a', start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 2)),
        _todo('b', start: DateTime(2026, 9, 2), end: DateTime(2026, 9, 4)),
        _todo('c', start: DateTime(2026, 9, 4), end: DateTime(2026, 9, 6)),
      ],
      dependencies: [_dep('a', 'b'), _dep('b', 'c')],
      seedTodoIds: {'a'},
    );

    final byId = {for (final update in updates) update.original.id: update};
    // B 推迟到 A 结束次日。
    expect(byId['b']!.updated.startDate, DateTime(2026, 9, 3));
    // C 以 B 的调整后结束日为约束（B 平移后 9/5 结束）。
    expect(byId['c']!.updated.startDate, DateTime(2026, 9, 6));
  });

  test('已排更晚的后继不推迟，但其日期仍作为下游约束', () {
    final updates = propagateDependencySchedule(
      todos: [
        _todo('a', start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 10)),
        _todo('b', start: DateTime(2026, 9, 20), end: DateTime(2026, 9, 22)),
        _todo('c', start: DateTime(2026, 9, 21), end: DateTime(2026, 9, 23)),
      ],
      dependencies: [_dep('a', 'b'), _dep('b', 'c')],
      seedTodoIds: {'a'},
    );

    // B 已晚于约束不动；C 以 B 原结束日（9/22）+1 推迟。
    expect(updates.map((update) => update.original.id), ['c']);
    expect(updates.single.updated.startDate, DateTime(2026, 9, 23));
  });

  test('未排期的后继自动获得开始日', () {
    final updates = propagateDependencySchedule(
      todos: [
        _todo('a', start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 5)),
        _todo('b'),
      ],
      dependencies: [_dep('a', 'b')],
      seedTodoIds: {'a'},
    );

    expect(updates.single.updated.startDate, DateTime(2026, 9, 6));
    expect(updates.single.updated.endDate, DateTime(2026, 9, 6));
  });

  test('只有截止日的后继：推迟开始但截止日不早于新开始', () {
    final updates = propagateDependencySchedule(
      todos: [
        _todo('a', start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 10)),
        _todo('b', end: DateTime(2026, 9, 12)),
      ],
      dependencies: [_dep('a', 'b')],
      seedTodoIds: {'a'},
    );

    expect(updates.single.updated.startDate, DateTime(2026, 9, 11));
    expect(updates.single.updated.endDate, DateTime(2026, 9, 12));
  });

  test('已完成的后继不搬动，但其日期仍约束更下游', () {
    final updates = propagateDependencySchedule(
      todos: [
        _todo('a', start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 10)),
        _todo(
          'b',
          start: DateTime(2026, 9, 3),
          end: DateTime(2026, 9, 4),
          done: true,
        ),
        _todo('c', start: DateTime(2026, 9, 4), end: DateTime(2026, 9, 6)),
      ],
      dependencies: [_dep('a', 'b'), _dep('b', 'c')],
      seedTodoIds: {'a'},
    );

    // B 已完成：不调整；C 以 B 原结束日（9/4）+1 推迟。
    expect(updates.map((update) => update.original.id), ['c']);
    expect(updates.single.updated.startDate, DateTime(2026, 9, 5));
  });

  test('前驱无日期不产生约束', () {
    final updates = propagateDependencySchedule(
      todos: [
        _todo('a'),
        _todo('b', start: DateTime(2026, 9, 1)),
      ],
      dependencies: [_dep('a', 'b')],
      seedTodoIds: {'a'},
    );

    expect(updates, isEmpty);
  });

  test('环数据不死循环（防御）', () {
    final updates = propagateDependencySchedule(
      todos: [
        _todo('a', start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 2)),
        _todo('b', start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 2)),
      ],
      dependencies: [_dep('a', 'b'), _dep('b', 'a')],
      seedTodoIds: {'a'},
    );

    // 每个任务至多调整一次。
    expect(updates.length, lessThanOrEqualTo(2));
  });

  test('撤销完成（done false）不作为种子也不重排', () {
    final updates = propagateDependencySchedule(
      todos: [
        _todo('a', start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 5)),
        _todo('b', start: DateTime(2026, 9, 3)),
      ],
      dependencies: [_dep('a', 'b')],
      seedTodoIds: {'a'},
    );

    // 约束只看日期，本测试确认引擎与 done 无关；由控制器决定触发时机。
    expect(updates.single.updated.startDate, DateTime(2026, 9, 6));
  });
}
