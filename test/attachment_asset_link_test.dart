// 附件面板：附件行菜单「关联资产 / 解除关联」操作。

import 'package:cardory/domain/asset_models.dart';
import 'package:cardory/presentation/pages/project_attachments_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AttachmentData _att(String id, String name, {String? assetId}) =>
    AttachmentData(
      id: id,
      fileName: name,
      storageKey: 'k-$id',
      size: 1,
      sha256: 'x',
      createdAt: DateTime(2026),
      assetId: assetId,
    );

const _assetA = AssetData(
  id: 'asset-a',
  type: AssetType.software,
  name: 'Nginx',
);
const _assetB = AssetData(id: 'asset-b', type: AssetType.hardware, name: '交换机');

Future<void> _pump(
  WidgetTester tester, {
  required List<AttachmentData> attachments,
  required List<AssetData> assets,
  required void Function(AttachmentData, AssetData) onLinkAsset,
  required void Function(AttachmentData) onUnlinkAsset,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ProjectAttachmentsPanel(
          attachments: attachments,
          categories: const [],
          assets: assets,
          onChanged: (_, _) async {},
          onLinkAsset: onLinkAsset,
          onUnlinkAsset: onUnlinkAsset,
        ),
      ),
    ),
  ),
);

Future<void> _openRowMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('附件行菜单含「关联资产」，选择器列出资产并回调', (tester) async {
    AttachmentData? linkedAttachment;
    AssetData? linkedAsset;
    await _pump(
      tester,
      attachments: [_att('att-1', '合同.pdf')],
      assets: [_assetA, _assetB],
      onLinkAsset: (attachment, asset) {
        linkedAttachment = attachment;
        linkedAsset = asset;
      },
      onUnlinkAsset: (_) {},
    );

    await _openRowMenu(tester);
    expect(find.text('关联资产…'), findsOneWidget);

    await tester.tap(find.text('关联资产…'));
    await tester.pumpAndSettle();
    // 选择器列出本项目全部资产。
    expect(find.text('Nginx'), findsOneWidget);
    expect(find.text('交换机'), findsOneWidget);

    await tester.tap(find.text('Nginx'));
    await tester.pumpAndSettle();
    expect(linkedAttachment?.id, 'att-1');
    expect(linkedAsset?.id, 'asset-a');
  });

  testWidgets('已关联附件的菜单含「解除关联」，点击触发回调', (tester) async {
    AttachmentData? unlinked;
    await _pump(
      tester,
      attachments: [_att('att-1', '合同.pdf', assetId: 'asset-a')],
      assets: [_assetA],
      onLinkAsset: (_, _) {},
      onUnlinkAsset: (attachment) => unlinked = attachment,
    );

    await _openRowMenu(tester);
    expect(find.text('解除关联'), findsOneWidget);

    await tester.tap(find.text('解除关联'));
    await tester.pumpAndSettle();
    expect(unlinked?.id, 'att-1');
  });
}
