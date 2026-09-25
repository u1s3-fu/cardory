// 日历页资产到期条目测试：月视图标记 + 图例、点击回调、空数据无差异。
//
// pump 方式仿 test/widget_test.dart 的日历用例。

import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/domain/schedule_queries.dart';
import 'package:cardory/presentation/pages/calendar_page.dart';
import 'package:cardory/services/system_calendar_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpUiFrames(WidgetTester tester) async {
  for (var index = 0; index < 20; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

AssetDueEntry _dueEntry() => AssetDueEntry(
  assetId: 'asset-1',
  assetName: 'example.com',
  date: DateTime(2026, 10, 15),
  fieldLabel: '到期日',
  title: '到期日 · example.com',
);

/// 记录 createEvent 调用的假系统日历服务。
class _FakeSystemCalendarService implements SystemCalendarService {
  final List<({String title, DateTime start, DateTime end, String note})>
  created = [];

  @override
  Future<List<SystemCalendarEvent>> loadEvents(
    DateTime start,
    DateTime end,
  ) async => const [];

  @override
  Future<SystemCalendarWriteResult> createEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    String note = '',
  }) async {
    created.add((title: title, start: start, end: end, note: note));
    return const SystemCalendarWriteResult(success: true, detail: '已写入。');
  }
}

Widget _host({
  required List<AssetDueEntry> assetDues,
  void Function(AssetDueEntry entry)? onOpenAssetDue,
  required DateTime now,
  SystemCalendarService? systemCalendar,
  List<TodoData> todos = const [],
  Future<TodoData?> Function(TodoData todo)? onOpenTodo,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CalendarPage(
          todos: todos,
          now: now,
          onToggleTodo: (todo) async => todo,
          onOpenTodo: onOpenTodo ?? (_) async => null,
          systemCalendar: systemCalendar,
          assetDues: assetDues,
          onOpenAssetDue: onOpenAssetDue,
        ),
      ),
    ),
  );
}

/// 进入日视图并点击资产到期条目，返回弹出的操作面板已渲染的页面状态。
Future<void> _openAssetDuePanel(WidgetTester tester) async {
  await tester.tap(find.text('日').first);
  await pumpUiFrames(tester);
  final chip = find.text('全天 · 到期日 · example.com');
  expect(chip, findsOneWidget);
  await tester.ensureVisible(chip);
  await pumpUiFrames(tester);
  await tester.tap(chip);
  await pumpUiFrames(tester);
}

void main() {
  testWidgets('月视图：资产到期日在日期格出现资产标记，图例含资产到期', (tester) async {
    await tester.pumpWidget(
      _host(assetDues: [_dueEntry()], now: DateTime(2026, 10, 1, 9)),
    );
    await pumpUiFrames(tester);

    // 图例区出现「资产到期」。
    expect(find.text('资产到期'), findsOneWidget);
    // 10 月 15 日格出现资产标记图标（日期格 key 为 calendar-day-<DateTime>）。
    final dayCell = find.byKey(
      const ValueKey('calendar-day-2026-10-15 00:00:00.000'),
    );
    expect(dayCell, findsOneWidget);
    expect(
      find.descendant(
        of: dayCell,
        matching: find.byIcon(Icons.event_available_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('日视图：点击资产条目弹面板，「查看资产」回调收到同 assetId 与 date', (tester) async {
    AssetDueEntry? opened;
    await tester.pumpWidget(
      _host(
        assetDues: [_dueEntry()],
        now: DateTime(2026, 10, 15, 9),
        onOpenAssetDue: (entry) => opened = entry,
      ),
    );
    await pumpUiFrames(tester);

    await _openAssetDuePanel(tester);
    // 弹层出现，查看资产按钮可见（systemCalendar 为 null）。
    // 注意同页 _DayEntryList 也有同名条目标题，故限定在 AlertDialog 内断言。
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('到期日 · example.com')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('view-asset-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('view-asset-button')));
    await pumpUiFrames(tester);

    expect(opened, isNotNull);
    expect(opened!.assetId, 'asset-1');
    expect(opened!.date, DateTime(2026, 10, 15));
  });

  testWidgets('点击资产条目弹操作面板：显示标题、字段与到期日期及两个动作按钮', (tester) async {
    final fake = _FakeSystemCalendarService();
    await tester.pumpWidget(
      _host(
        assetDues: [_dueEntry()],
        now: DateTime(2026, 10, 15, 9),
        systemCalendar: fake,
      ),
    );
    await pumpUiFrames(tester);

    await _openAssetDuePanel(tester);

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text('到期日 · example.com')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('到期日 · 2026-10-15')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('view-asset-button')), findsOneWidget);
    expect(
      find.byKey(const Key('push-system-calendar-button')),
      findsOneWidget,
    );
  });

  testWidgets('点「加入系统日历」：createEvent 收到标题/到期日零点/备注，提示已加入系统日历', (tester) async {
    final fake = _FakeSystemCalendarService();
    await tester.pumpWidget(
      _host(
        assetDues: [_dueEntry()],
        now: DateTime(2026, 10, 15, 9),
        systemCalendar: fake,
      ),
    );
    await pumpUiFrames(tester);

    await _openAssetDuePanel(tester);
    await tester.tap(find.byKey(const Key('push-system-calendar-button')));
    await pumpUiFrames(tester);

    expect(fake.created, hasLength(1));
    expect(fake.created.single.title, '到期日 · example.com');
    expect(fake.created.single.start, DateTime(2026, 10, 15));
    expect(fake.created.single.end, DateTime(2026, 10, 16));
    expect(fake.created.single.note, contains('example.com'));
    expect(fake.created.single.note, contains('到期日'));
    expect(find.text('已加入系统日历'), findsOneWidget);
  });

  testWidgets('systemCalendar 为 null 时操作面板只有「查看资产」按钮', (tester) async {
    await tester.pumpWidget(
      _host(assetDues: [_dueEntry()], now: DateTime(2026, 10, 15, 9)),
    );
    await pumpUiFrames(tester);

    await _openAssetDuePanel(tester);

    expect(find.byKey(const Key('view-asset-button')), findsOneWidget);
    expect(find.byKey(const Key('push-system-calendar-button')), findsNothing);
  });

  testWidgets('assetDues 为空时与现状无差异', (tester) async {
    await tester.pumpWidget(
      _host(assetDues: const [], now: DateTime(2026, 10, 1, 9)),
    );
    await pumpUiFrames(tester);

    // 无资产图例与资产标记图标。
    expect(find.text('资产到期'), findsNothing);
    expect(find.byIcon(Icons.event_available_outlined), findsNothing);
    // 月视图正常渲染。
    expect(find.text('2026 年 10 月'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
  });

  testWidgets('日视图：底部条目列表中的资产条目可点击并弹出操作面板', (tester) async {
    AssetDueEntry? opened;
    await tester.pumpWidget(
      _host(
        assetDues: [_dueEntry()],
        now: DateTime(2026, 10, 15, 12),
        onOpenAssetDue: (due) => opened = due,
      ),
    );
    await pumpUiFrames(tester);

    await tester.tap(find.text('日').first);
    await pumpUiFrames(tester);

    // 底部 _DayEntryList 的条目标题不带「全天 ·」前缀，精确匹配时间网格芯片之外的那一个。
    final listTile = find.text('到期日 · example.com');
    expect(listTile, findsOneWidget);
    await tester.ensureVisible(listTile);
    await pumpUiFrames(tester);
    await tester.tap(listTile);
    await pumpUiFrames(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.byKey(const Key('view-asset-button')));
    await pumpUiFrames(tester);
    expect(opened?.assetId, 'asset-1');
  });

  testWidgets('日视图：底部条目列表中的任务条目可点击打开任务', (tester) async {
    final todo = TodoData(
      id: 'todo-1',
      title: '写周报',
      endDate: DateTime(2026, 10, 15, 10, 0),
      projectId: 'project-1',
      projectTitle: '项目',
      priority: ProjectPriority.p1,
      done: false,
    );
    TodoData? openedTodo;
    await tester.pumpWidget(
      _host(
        assetDues: const [],
        now: DateTime(2026, 10, 15, 12),
        todos: [todo],
        onOpenTodo: (value) async => openedTodo = value,
      ),
    );
    await pumpUiFrames(tester);

    await tester.tap(find.text('日').first);
    await pumpUiFrames(tester);

    final listTile = find.text('写周报');
    expect(listTile, findsOneWidget);
    await tester.ensureVisible(listTile);
    await pumpUiFrames(tester);
    await tester.tap(listTile);
    await pumpUiFrames(tester);

    expect(openedTodo?.id, 'todo-1');
  });
}
