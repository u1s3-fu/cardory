// CalendarEntry 实体标识测试：
// - 日历页把任务 endDate 转 CalendarEntry 时携带 entityType/entityId；
// - 周/日视图点击任务条目时按 entityId 回查（而非按 endDate 位置反查），
//   两个任务截止时刻相同时点击第二个条目必须打开第二个任务。

import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/presentation/pages/calendar_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

TodoData _todo(String id, String title, DateTime endDate) => TodoData(
  id: id,
  title: title,
  endDate: endDate,
  projectId: 'project-1',
  projectTitle: '项目',
  priority: ProjectPriority.p1,
  done: false,
);

/// 仿 test/widget_test.dart 中日历页用例的 pump harness（todos + now 注入）。
Future<void> _pumpCalendarPage(
  WidgetTester tester,
  List<TodoData> todos, {
  required DateTime now,
  required void Function(TodoData todo) onOpenTodo,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CalendarPage(
            todos: todos,
            now: now,
            onToggleTodo: (_) async => todos.first,
            onOpenTodo: (todo) async {
              onOpenTodo(todo);
              return null;
            },
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('周/日视图：两个任务截止时刻相同，点击第二个条目打开第二个任务', (tester) async {
    // 同一天同一时刻截止的两个任务（旧实现按 endDate 反查时必然错开成第一个）。
    final due = DateTime(2026, 9, 7, 10, 0);
    final todos = [_todo('todo-1', '任务一', due), _todo('todo-2', '任务二', due)];
    final openedIds = <String>[];
    await _pumpCalendarPage(
      tester,
      todos,
      now: DateTime(2026, 9, 7, 15),
      onOpenTodo: (todo) => openedIds.add(todo.id),
    );

    // 切到日视图：任务条目出现在 24 小时网格中。
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<CalendarViewMode>),
        matching: find.text('日'),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 点击第二个任务条目，onOpenTodo 收到的必须是第二个任务的 id。
    await tester.tap(find.text('10:00 任务二'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(openedIds, ['todo-2']);
  });

  testWidgets('日历页把任务 endDate 转成 CalendarEntry 时携带实体标识', (tester) async {
    final todos = [
      _todo('todo-a', '有截止任务', DateTime(2026, 9, 7, 10, 0)),
      // 无截止任务：copyWith 不能置空 endDate，直接构造。
      TodoData(
        id: 'todo-b',
        title: '无截止任务',
        projectId: 'project-1',
        projectTitle: '项目',
        priority: ProjectPriority.p1,
        done: false,
      ),
      _todo('todo-c', '另一条截止', DateTime(2026, 9, 8, 12, 0)),
    ];

    // 通过日历页暴露的任务条目构建函数验证（页面内部同样走该函数）。
    final entries = CalendarPage.buildTaskEntries(todos);

    expect(entries.length, 2);
    expect(entries.every((entry) => entry.entityType == 'todo'), isTrue);
    expect(entries.map((entry) => entry.entityId).toList(), [
      'todo-a',
      'todo-c',
    ]);
  });
}
