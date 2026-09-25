import 'package:cardory/domain/asset_models.dart';
import 'package:cardory/domain/asset_template.dart';
import 'package:cardory/presentation/pages/asset_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AssetDialogResult? result;

  /// 打开待测的 AssetDialog（pump 方式仿 widget_test.dart 既有用例，
  /// 通过 showDialog 捕获保存结果）。
  Future<void> pumpDialog(WidgetTester tester, {AssetData? asset}) async {
    result = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showDialog<AssetDialogResult>(
                    context: context,
                    builder: (_) => AssetDialog(
                      asset: asset,
                      templates: builtInAssetTemplates(),
                    ),
                  );
                },
                child: const Text('打开对话框'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开对话框'));
    await tester.pumpAndSettle();
  }

  /// 通过下拉框切换到指定名称的模板。
  Future<void> selectTemplate(WidgetTester tester, String name) async {
    await tester.tap(find.text('软件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  /// 通过日期选择器为指定标签的 date 字段选中“当月 15 日”。
  Future<DateTime> pickDate(WidgetTester tester, String label) async {
    await tester.tap(find.widgetWithText(TextField, label));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    return DateTime(now.year, now.month, 15);
  }

  String formatDay(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  testWidgets('defaults to software template and shows its fields', (
    tester,
  ) async {
    await pumpDialog(tester);

    expect(find.text('软件'), findsOneWidget);
    expect(find.text('版本'), findsOneWidget);
    expect(find.text('端口'), findsOneWidget);
    expect(find.text('路径'), findsOneWidget);
    expect(find.text('注册商'), findsNothing);
  });

  testWidgets('switching to domain template shows registrar and date picker', (
    tester,
  ) async {
    await pumpDialog(tester);

    await selectTemplate(tester, '域名');
    expect(find.text('注册商'), findsOneWidget);
    expect(find.text('到期日'), findsOneWidget);
    expect(find.text('版本'), findsNothing);

    await pickDate(tester, '到期日');
  });

  testWidgets('saving domain asset fills templateId and customFields', (
    tester,
  ) async {
    await pumpDialog(tester);

    await selectTemplate(tester, '域名');
    await tester.enterText(find.widgetWithText(TextField, '资产名称 *'), '我的域名');
    await tester.enterText(find.widgetWithText(TextField, '注册商'), '阿里云');
    final picked = await pickDate(tester, '到期日');

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.asset.templateId, 'tpl-domain');
    expect(result!.asset.type, AssetType.software);
    expect(result!.asset.customFields['registrar'], '阿里云');
    expect(result!.asset.customFields['expiryDate'], formatDay(picked));
  });

  testWidgets('editing existing software asset prefills customFields', (
    tester,
  ) async {
    const asset = AssetData(
      id: 'asset-1',
      type: AssetType.software,
      name: 'Cardory API',
      templateId: 'tpl-software',
      customFields: {'version': '1.2.0', 'port': '8080', 'path': '/srv/api'},
    );

    await pumpDialog(tester, asset: asset);

    expect(find.text('1.2.0'), findsOneWidget);
    expect(find.text('8080'), findsOneWidget);
    expect(find.text('/srv/api'), findsOneWidget);
    expect(find.text('Cardory API'), findsOneWidget);
  });

  testWidgets('required date left empty blocks submit with error', (
    tester,
  ) async {
    await pumpDialog(tester);

    await selectTemplate(tester, '域名');
    await tester.enterText(find.widgetWithText(TextField, '资产名称 *'), '我的域名');
    await tester.enterText(find.widgetWithText(TextField, '注册商'), '阿里云');

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(result, isNull);
    expect(find.text('请填写到期日'), findsOneWidget);
  });
}
