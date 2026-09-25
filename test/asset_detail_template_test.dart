// 资产详情与面板：模板字段渲染、无模板回退与面板摘要行。

import 'package:cardory/domain/asset_models.dart';
import 'package:cardory/domain/asset_template.dart';
import 'package:cardory/presentation/widgets/project_assets_panel.dart';
import 'package:cardory/presentation/widgets/asset_detail_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AssetTemplate _template(String id) =>
    builtInAssetTemplates().firstWhere((t) => t.id == id);

Future<void> _pumpDetail(
  WidgetTester tester,
  AssetData asset,
  AssetTemplate? template,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: AssetDetailDialog(asset: asset, template: template),
    ),
  ),
);

Future<void> _pumpPanel(WidgetTester tester, List<AssetData> assets) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProjectAssetsPanel(
              assets: assets,
              assetTags: const [],
              templates: builtInAssetTemplates(),
              onAdd: () async {},
              onView: (_) async {},
              onDelete: (_) async {},
              onUpdateAssetsTags: (_, __) async {},
              onAddTag: (tag) async => tag,
              onUpdateTag: (tag) async => tag,
              onDeleteTag: (_) async {},
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('详情按模板字段渲染域名资产', (tester) async {
    const asset = AssetData(
      id: 'asset-domain',
      type: AssetType.software,
      name: 'example.com',
      templateId: 'tpl-domain',
      customFields: {'registrar': 'Aliyun', 'expiryDate': '2027-01-01'},
    );

    await _pumpDetail(tester, asset, _template('tpl-domain'));

    expect(find.text('注册商'), findsOneWidget);
    expect(find.text('Aliyun'), findsOneWidget);
    expect(find.text('到期日'), findsOneWidget);
    expect(find.text('2027-01-01'), findsOneWidget);
    // 旧 software 分支字段不再出现。
    expect(find.text('版本'), findsNothing);
  });

  testWidgets('template 为 null 时回退旧 software/hardware 分支', (tester) async {
    const asset = AssetData(
      id: 'asset-sw',
      type: AssetType.software,
      name: 'Nginx',
      version: '1.2.0',
      port: '8080',
      path: '/srv/nginx',
    );

    await _pumpDetail(tester, asset, null);

    expect(find.text('版本'), findsOneWidget);
    expect(find.text('1.2.0'), findsOneWidget);
    expect(find.text('端口'), findsOneWidget);
    expect(find.text('路径'), findsOneWidget);
  });

  testWidgets('面板摘要行显示模板名与第一个非空字段', (tester) async {
    const asset = AssetData(
      id: 'asset-domain-2',
      type: AssetType.software,
      name: 'cardory.dev',
      templateId: 'tpl-domain',
      customFields: {'registrar': 'Aliyun', 'expiryDate': '2027-01-01'},
    );

    await _pumpPanel(tester, [asset]);

    expect(find.text('cardory.dev'), findsOneWidget);
    expect(find.textContaining('域名'), findsOneWidget);
    expect(find.textContaining('Aliyun'), findsOneWidget);
  });
}
