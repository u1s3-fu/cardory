// CredentialRow 凭据展示行：掩码/限时揭示/复制，及其在资产详情对话框中的接入。

import 'package:cardory/domain/asset_models.dart';
import 'package:cardory/presentation/widgets/asset_detail_dialog.dart';
import 'package:cardory/presentation/widgets/credential_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

Future<void> _mockClipboard(WidgetTester tester) async {
  String? clipboardText;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboardText = (call.arguments as Map<Object?, Object?>)['text']
              as String?;
          return null;
        case 'Clipboard.getData':
          return <String, dynamic>{'text': clipboardText};
        default:
          return null;
      }
    },
  );
}

void main() {
  testWidgets('secret=true 默认显示等长掩码，明文不可见', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const CredentialRow(
          label: '登录密码',
          value: 'secret123',
          secret: true,
        ),
      ),
    );

    expect(find.text('•••••••••'), findsOneWidget);
    expect(find.text('secret123'), findsNothing);
  });

  testWidgets('点眼睛揭示明文，30 秒后自动回到掩码态', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const CredentialRow(
          label: '登录密码',
          value: 'secret123',
          secret: true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('credential-reveal')));
    await tester.pump();

    expect(find.text('secret123'), findsOneWidget);
    expect(find.text('•••••••••'), findsNothing);

    await tester.pump(const Duration(seconds: 30));

    expect(find.text('•••••••••'), findsOneWidget);
    expect(find.text('secret123'), findsNothing);
  });

  testWidgets('揭示期间再点眼睛立即收回', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const CredentialRow(
          label: '登录密码',
          value: 'secret123',
          secret: true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('credential-reveal')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('credential-reveal')));
    await tester.pump();

    expect(find.text('•••••••••'), findsOneWidget);
    expect(find.text('secret123'), findsNothing);
  });

  testWidgets('点复制写入剪贴板并回调原值', (tester) async {
    await _mockClipboard(tester);
    String? copied;
    await tester.pumpWidget(
      _wrap(
        CredentialRow(
          label: '登录密码',
          value: 'secret123',
          secret: true,
          onCopied: (value) => copied = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('credential-copy')));
    await tester.pump();

    expect(copied, 'secret123');
    final data = await Clipboard.getData('text/plain');
    expect(data?.text, 'secret123');
  });

  testWidgets('secret=false 默认明文且无眼睛按钮', (tester) async {
    await tester.pumpWidget(
      _wrap(const CredentialRow(label: '登录用户名', value: 'admin')),
    );

    expect(find.text('admin'), findsOneWidget);
    expect(find.byKey(const Key('credential-reveal')), findsNothing);
    expect(find.byKey(const Key('credential-copy')), findsOneWidget);
  });

  testWidgets('value 为空显示「未填写」且无操作按钮', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const CredentialRow(label: '登录密码', value: '', secret: true),
      ),
    );

    expect(find.text('未填写'), findsOneWidget);
    expect(find.byKey(const Key('credential-reveal')), findsNothing);
    expect(find.byKey(const Key('credential-copy')), findsNothing);
  });
}
