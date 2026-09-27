// 自定义资产模板编辑器测试：新建（字段 key 生成、日期字段的提醒开关）、
// 校验（名称必填）、编辑（key 保持不变）。

import 'package:cardory/domain/asset_template.dart';
import 'package:cardory/presentation/pages/asset_template_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 打开编辑器并等待渲染；保存后经 showDialog 返回结果。
Future<void> _pumpEditor(
  WidgetTester tester, {
  AssetTemplate? initial,
  required ValueChanged<AssetTemplate?> onSaved,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                final result = await showDialog<AssetTemplate>(
                  context: context,
                  builder: (_) => AssetTemplateEditorDialog(initial: initial),
                );
                onSaved(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _addField(
  WidgetTester tester,
  String label, {
  AssetFieldKind kind = AssetFieldKind.text,
}) async {
  await tester.tap(find.byKey(const Key('add-template-field')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('template-field-label-new')).last,
    label,
  );
  if (kind != AssetFieldKind.text) {
    await tester.tap(find.byKey(const Key('template-field-kind-new')).last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(switch (kind) {
        AssetFieldKind.multiline => '多行文本',
        AssetFieldKind.number => '数字',
        AssetFieldKind.date => '日期',
        AssetFieldKind.url => '链接',
        _ => '文本',
      }).last,
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('新建模板：填名称加字段，保存返回 builtIn=false 且字段 key 已生成', (tester) async {
    AssetTemplate? saved;
    await _pumpEditor(tester, onSaved: (value) => saved = value);

    await tester.enterText(
      find.byKey(const Key('template-name-field')),
      '虚拟主机',
    );
    await _addField(tester, '机房');
    await _addField(tester, '到期日', kind: AssetFieldKind.date);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.name, '虚拟主机');
    expect(saved!.builtIn, isFalse);
    expect(saved!.id, startsWith('tpl-custom-'));
    expect(saved!.fields.length, 2);
    expect(saved!.fields[0].label, '机房');
    expect(saved!.fields[0].key, isNotEmpty);
    expect(saved!.fields[1].kind, AssetFieldKind.date);
    // 两个字段的 key 互不相同。
    expect(saved!.fields[0].key, isNot(saved!.fields[1].key));
  });

  testWidgets('日期字段展示「进入日历提醒」开关并可勾选', (tester) async {
    AssetTemplate? saved;
    await _pumpEditor(tester, onSaved: (value) => saved = value);

    await tester.enterText(find.byKey(const Key('template-name-field')), '域名');
    await _addField(tester, '到期日', kind: AssetFieldKind.date);
    await tester.tap(find.byKey(const Key('template-field-remind-new')).last);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved!.fields.single.remind, isTrue);
  });

  testWidgets('名称为空时保存报错且不关闭', (tester) async {
    AssetTemplate? saved;
    await _pumpEditor(tester, onSaved: (value) => saved = value);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('请填写模板名称'), findsOneWidget);
    expect(saved, isNull);
  });

  testWidgets('编辑既有模板：预填名称与字段，保存后字段 key 不变', (tester) async {
    AssetTemplate? saved;
    const existing = AssetTemplate(
      id: 'tpl-custom-1',
      name: '旧模板',
      fields: [AssetTemplateField(key: 'c-abc', label: '机房')],
    );
    await _pumpEditor(
      tester,
      initial: existing,
      onSaved: (value) => saved = value,
    );

    expect(find.text('旧模板'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('template-name-field')), '新模板');
    await tester.enterText(
      find.byKey(const Key('template-field-label-0')),
      '机房位置',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved!.id, 'tpl-custom-1');
    expect(saved!.name, '新模板');
    expect(saved!.fields.single.key, 'c-abc');
    expect(saved!.fields.single.label, '机房位置');
  });
}
