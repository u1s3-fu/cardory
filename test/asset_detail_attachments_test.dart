// 资产详情对话框：关联附件展示与解除关联入口。

import 'package:cardory/domain/asset_models.dart';
import 'package:cardory/presentation/widgets/asset_detail_dialog.dart';
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

Future<void> _pump(WidgetTester tester, List<AttachmentData> attachments) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssetDetailDialog(
            asset: const AssetData(
              id: 'a1',
              type: AssetType.software,
              name: 'Nginx',
            ),
            attachments: attachments,
            onLinkAttachment: (_) {},
            onUnlinkAttachment: (_) {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('展示已关联附件并提供解除关联入口', (tester) async {
    await _pump(tester, [_att('att-1', '发票.pdf', assetId: 'a1')]);
    expect(find.text('发票.pdf'), findsOneWidget);
    expect(find.byKey(const Key('unlink-attachment-att-1')), findsOneWidget);
  });

  testWidgets('未关联的附件不出现在资产详情里', (tester) async {
    await _pump(tester, [_att('att-2', '合同.pdf', assetId: null)]);
    expect(find.text('合同.pdf'), findsNothing);
  });
}
