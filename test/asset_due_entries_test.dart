// assetDueEntries 纯函数测试：资产模板 remind date 字段 → 到期条目。
import 'package:flutter_test/flutter_test.dart';

import 'package:cardory/domain/asset_models.dart';
import 'package:cardory/domain/asset_template.dart';
import 'package:cardory/domain/schedule_queries.dart';

AssetData _asset(
  String id,
  String name, {
  String templateId = '',
  Map<String, String> customFields = const {},
}) => AssetData(
  id: id,
  type: AssetType.software,
  name: name,
  templateId: templateId,
  customFields: customFields,
);

void main() {
  group('assetDueEntries', () {
    test('用例 1：域名资产 expiryDate 产出一条到期条目', () {
      final tpl = builtInAssetTemplates().firstWhere(
        (t) => t.id == 'tpl-domain',
      );
      final assets = [
        _asset(
          'a1',
          'example.com',
          templateId: tpl.id,
          customFields: {'expiryDate': '2027-01-01'},
        ),
      ];

      final entries = assetDueEntries(assets, [tpl]);

      expect(entries, hasLength(1));
      expect(entries.first.assetId, 'a1');
      expect(entries.first.assetName, 'example.com');
      expect(entries.first.date, DateTime(2027, 1, 1));
      expect(entries.first.fieldLabel, '到期日');
      expect(entries.first.title, contains('example.com'));
      expect(entries.first.title, contains('到期日'));
    });

    test('用例 2：两个 remind 字段的模板产出两条条目', () {
      const tpl = AssetTemplate(
        id: 'tpl-test-two',
        name: '双提醒',
        fields: [
          AssetTemplateField(
            key: 'regExpire',
            label: '注册到期',
            kind: AssetFieldKind.date,
            remind: true,
          ),
          AssetTemplateField(
            key: 'sslExpire',
            label: 'SSL 到期',
            kind: AssetFieldKind.date,
            remind: true,
          ),
          AssetTemplateField(
            key: 'silentDate',
            label: '不提醒',
            kind: AssetFieldKind.date,
          ),
        ],
      );
      final assets = [
        _asset(
          'a2',
          'dual.example.com',
          templateId: tpl.id,
          customFields: {
            'regExpire': '2027-02-01',
            'sslExpire': '2027-03-01',
            'silentDate': '2027-04-01',
          },
        ),
      ];

      final entries = assetDueEntries(assets, [tpl]);

      expect(entries, hasLength(2));
      expect(entries.map((e) => e.fieldLabel), containsAll(['注册到期', 'SSL 到期']));
      expect(entries.map((e) => e.fieldLabel), isNot(contains('不提醒')));
    });

    test('用例 3：非法日期值静默跳过，不抛异常', () {
      final tpl = builtInAssetTemplates().firstWhere(
        (t) => t.id == 'tpl-domain',
      );
      final assets = [
        _asset(
          'a3',
          'bad.example.com',
          templateId: tpl.id,
          customFields: {'expiryDate': 'not-a-date'},
        ),
      ];

      expect(() => assetDueEntries(assets, [tpl]), returnsNormally);
      expect(assetDueEntries(assets, [tpl]), isEmpty);
    });

    test('用例 4：bounds 过滤含首尾日，界外剔除', () {
      final tpl = builtInAssetTemplates().firstWhere(
        (t) => t.id == 'tpl-domain',
      );
      final assets = [
        _asset(
          'before',
          'before.com',
          templateId: tpl.id,
          customFields: {'expiryDate': '2026-12-31'},
        ),
        _asset(
          'first',
          'first.com',
          templateId: tpl.id,
          customFields: {'expiryDate': '2027-01-01'},
        ),
        _asset(
          'middle',
          'middle.com',
          templateId: tpl.id,
          customFields: {'expiryDate': '2027-01-15'},
        ),
        _asset(
          'last',
          'last.com',
          templateId: tpl.id,
          customFields: {'expiryDate': '2027-01-31'},
        ),
        _asset(
          'after',
          'after.com',
          templateId: tpl.id,
          customFields: {'expiryDate': '2027-02-01'},
        ),
      ];

      final entries = assetDueEntries(
        assets,
        [tpl],
        bounds: (DateTime(2027, 1, 1), DateTime(2027, 1, 31)),
      );

      expect(entries.map((e) => e.assetId).toList(), [
        'first',
        'middle',
        'last',
      ]);
    });

    test('用例 5：不同日期条目按日期升序排序', () {
      final tpl = builtInAssetTemplates().firstWhere(
        (t) => t.id == 'tpl-domain',
      );
      final assets = [
        _asset(
          'late',
          'late.com',
          templateId: tpl.id,
          customFields: {'expiryDate': '2027-02-10'},
        ),
        _asset(
          'early',
          'early.com',
          templateId: tpl.id,
          customFields: {'expiryDate': '2027-01-05'},
        ),
      ];

      final entries = assetDueEntries(assets, [tpl]);

      expect(entries.map((e) => e.assetId).toList(), ['early', 'late']);
    });
  });
}
