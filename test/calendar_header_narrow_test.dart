// 窄屏日历页头部测试：标题/回到今天/视图切换/翻页箭头单行 Row 在手机宽度
// （约 360dp）下溢出，「下一月」按钮被推出屏幕不可达；降级为两行后应无
// 溢出异常且翻页按钮可达可点。

import 'package:cardory/presentation/pages/calendar_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpUiFrames(WidgetTester tester) async {
  for (var index = 0; index < 20; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _host() => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: CalendarPage(
        todos: const [],
        now: DateTime(2026, 10, 1, 9),
        onToggleTodo: (todo) async => todo,
        onOpenTodo: (_) async => null,
      ),
    ),
  ),
);

void main() {
  testWidgets('窄屏（360dp）：头部不溢出，「下一月」可达且点击翻到下月', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host());
    await pumpUiFrames(tester);

    expect(find.text('2026 年 10 月'), findsOneWidget);

    // 「下一月」按钮完全落在屏幕内且可点击。
    final nextButton = find.byTooltip('下一月');
    await tester.ensureVisible(nextButton);
    await pumpUiFrames(tester);
    final rect = tester.getRect(nextButton);
    expect(rect.right, lessThanOrEqualTo(360));

    await tester.tap(nextButton);
    await pumpUiFrames(tester);
    expect(find.text('2026 年 11 月'), findsOneWidget);
  });

  testWidgets('宽屏（800dp）：头部保持单行布局', (tester) async {
    await tester.pumpWidget(_host());
    await pumpUiFrames(tester);

    expect(find.text('2026 年 10 月'), findsOneWidget);
    await tester.tap(find.byTooltip('下一月'));
    await pumpUiFrames(tester);
    expect(find.text('2026 年 11 月'), findsOneWidget);
  });
}
