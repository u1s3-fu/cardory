// 设置页「资产模板」分区：内置模板展示、启用/禁用开关与保存链路。

import 'package:cardory/domain/app_settings.dart';
import 'package:cardory/domain/asset_template.dart';
import 'package:cardory/domain/sync_credentials.dart';
import 'package:cardory/presentation/pages/settings_page.dart';
import 'package:cardory/presentation/settings_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _InMemoryCredentialStore implements SyncCredentialStore {
  @override
  Future<SyncCredentials> read() async => const SyncCredentials();

  @override
  Future<void> write(SyncCredentials credentials) async {}
}

Future<void> pumpSettings(
  WidgetTester tester, {
  required ValueChanged<SettingsResult> onSave,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SettingsDialog(
          settings: const AppSettings(),
          credentialStore: _InMemoryCredentialStore(),
          embedded: true,
          onSave: onSave,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('设置页展示资产模板分区与四个内置模板名称及字段清单', (tester) async {
    SettingsResult? captured;
    await pumpSettings(tester, onSave: (value) => captured = value);
    await tester.pumpAndSettle();

    expect(find.text('资产模板'), findsOneWidget);
    expect(find.text('软件'), findsOneWidget);
    expect(find.text('硬件'), findsOneWidget);
    expect(find.text('域名'), findsOneWidget);
    expect(find.text('SSL 证书'), findsOneWidget);
    // 字段清单只读展示。
    expect(find.textContaining('版本、端口、路径'), findsOneWidget);
    expect(find.textContaining('服务器序列号'), findsOneWidget);
    expect(find.textContaining('注册商'), findsOneWidget);
    expect(find.textContaining('签发方'), findsOneWidget);
    expect(captured, isNull);
  });

  testWidgets('切换 tpl-domain 开关后保存回调中该模板 enabled == false', (tester) async {
    SettingsResult? captured;
    await pumpSettings(tester, onSave: (value) => captured = value);
    await tester.pumpAndSettle();

    final tile = find.byKey(const Key('asset-template-tpl-domain'));
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();

    final saveButton = find.text('保存设置');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    final templates = captured!.settings.assetTemplates;
    // 禁止把清单存成空列表。
    expect(templates, hasLength(4));
    expect(templates.firstWhere((t) => t.id == 'tpl-domain').enabled, isFalse);
    for (final id in ['tpl-software', 'tpl-hardware', 'tpl-cert']) {
      expect(templates.firstWhere((t) => t.id == id).enabled, isTrue);
    }
  });

  test('下发过滤回归：enabledAssetTemplates 结果不含被禁用模板', () {
    // 详情/面板下发处（ProjectDetailPage）仍使用 enabledAssetTemplates 过滤；
    // AssetDialog 的模板过滤责任在其内部（见 asset_dialog_template_test.dart
    // 的「编辑模板已禁用的存量资产」分组）。
    final templates = [
      ...builtInAssetTemplates().map(
        (t) => t.id == 'tpl-hardware' ? t.copyWith(enabled: false) : t,
      ),
    ];
    final enabled = enabledAssetTemplates(templates);
    expect(enabled.map((t) => t.id), [
      'tpl-software',
      'tpl-domain',
      'tpl-cert',
    ]);
    expect(enabled.any((t) => t.id == 'tpl-hardware'), isFalse);
  });

  test('AssetTemplate.enabled JSON 往返无损，缺省为 true', () {
    const template = AssetTemplate(id: 'tpl-x', name: '自定义', fields: []);
    expect(template.enabled, isTrue);
    expect(AssetTemplate.fromJson(template.toJson()).enabled, isTrue);

    final disabled = template.copyWith(enabled: false);
    expect(disabled.enabled, isFalse);
    final restored = AssetTemplate.fromJson(disabled.toJson());
    expect(restored.enabled, isFalse);
    expect(restored.copyWith().enabled, isFalse);
  });
}
