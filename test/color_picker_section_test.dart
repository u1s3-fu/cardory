// 切换式颜色编辑区测试：SegmentedButton 切换编辑目标，
// 预设/滑条/hex 只渲染一份并作用于当前选中的颜色。

import 'package:cardory/presentation/widgets/color_picker_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  void Function(int background, int accent)? onChanged,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ColorPickerSection(
          initialBackgroundColor: 0xFFF5F6FC,
          initialThemeColor: 0xFF6B62DF,
          onChanged: onChanged,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('默认编辑背景色：滑条 key 为 background-color，hex 显示背景色', (tester) async {
    await _pump(tester, null);

    expect(
      find.byKey(const Key('background-color-red-slider')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('theme-color-red-slider')), findsNothing);
    expect(find.text('背景色十六进制'), findsOneWidget);
    expect(find.text('强调色十六进制'), findsNothing);

    final hexField = tester.widget<TextField>(
      find.widgetWithText(TextField, '背景色十六进制'),
    );
    expect(hexField.controller!.text, '#F5F6FC');
  });

  testWidgets('切到强调色标签：滑条与 hex 切换为强调色目标', (tester) async {
    await _pump(tester, null);
    await tester.tap(find.text('强调色'));
    await tester.pump();

    expect(find.byKey(const Key('theme-color-red-slider')), findsOneWidget);
    expect(find.byKey(const Key('background-color-red-slider')), findsNothing);
    expect(find.text('强调色十六进制'), findsOneWidget);

    final hexField = tester.widget<TextField>(
      find.widgetWithText(TextField, '强调色十六进制'),
    );
    expect(hexField.controller!.text, '#6B62DF');
  });

  testWidgets('强调色下点预设圆点：onChanged 上报新强调色且背景色不变', (tester) async {
    int? background;
    int? accent;
    await _pump(tester, (b, a) {
      background = b;
      accent = a;
    });
    await tester.tap(find.text('强调色'));
    await tester.pump();

    await tester.tap(find.byTooltip('选择 #0EA5E9'));
    await tester.pump();

    expect(accent, 0xFF0EA5E9);
    expect(background, 0xFFF5F6FC);
  });

  testWidgets('背景色下点预设圆点：onChanged 上报新背景色且强调色不变', (tester) async {
    int? background;
    int? accent;
    await _pump(tester, (b, a) {
      background = b;
      accent = a;
    });

    // 默认即背景色标签；0D1117 是背景色预设里的深色。
    await tester.tap(find.byTooltip('选择 #0D1117'));
    await tester.pump();

    expect(background, 0xFF0D1117);
    expect(accent, 0xFF6B62DF);
  });

  testWidgets('来回切换标签：两色各自保留，hex 回显正确', (tester) async {
    int? background;
    int? accent;
    await _pump(tester, (b, a) {
      background = b;
      accent = a;
    });

    await tester.tap(find.byTooltip('选择 #0D1117'));
    await tester.pump();
    await tester.tap(find.text('强调色'));
    await tester.pump();
    await tester.tap(find.byTooltip('选择 #0EA5E9'));
    await tester.pump();
    await tester.tap(find.text('背景色'));
    await tester.pump();

    final hexField = tester.widget<TextField>(
      find.widgetWithText(TextField, '背景色十六进制'),
    );
    expect(hexField.controller!.text, '#0D1117');
    expect(background, 0xFF0D1117);
    expect(accent, 0xFF0EA5E9);
  });
}
