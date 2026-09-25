// 日历页资产到期条目测试：月视图标记 + 图例、点击回调、空数据无差异。
//
// pump 方式仿 test/widget_test.dart 的日历用例。

import 'package:cardory/domain/schedule_queries.dart';
import 'package:cardory/presentation/pages/calendar_page.dart';
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

Widget _host({
  required List<AssetDueEntry> assetDues,
  void Function(AssetDueEntry entry)? onOpenAssetDue,
  required DateTime now,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: CalendarPage(
          todos: const [],
          now: now,
          onToggleTodo: (todo) async => todo,
          onOpenTodo: (_) async => null,
          assetDues: assetDues,
          onOpenAssetDue: onOpenAssetDue,
        ),
      ),
    ),
  );
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

  testWidgets('日视图：点击资产到期条目回调收到同 assetId 与 date', (tester) async {
    AssetDueEntry? opened;
    await tester.pumpWidget(
      _host(
        assetDues: [_dueEntry()],
        now: DateTime(2026, 10, 15, 9),
        onOpenAssetDue: (entry) => opened = entry,
      ),
    );
    await pumpUiFrames(tester);

    // 切到日视图（取 SegmentedButton 的「日」，排除星期表头同名文本），
    // 全天条目区出现资产条目。
    await tester.tap(find.text('日').first);
    await pumpUiFrames(tester);
    final chip = find.text('全天 · 到期日 · example.com');
    expect(chip, findsOneWidget);

    await tester.ensureVisible(chip);
    await pumpUiFrames(tester);
    await tester.tap(chip);
    await pumpUiFrames(tester);

    expect(opened, isNotNull);
    expect(opened!.assetId, 'asset-1');
    expect(opened!.date, DateTime(2026, 10, 15));
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
}
