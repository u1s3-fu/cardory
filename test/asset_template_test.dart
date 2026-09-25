import 'package:flutter_test/flutter_test.dart';

import 'package:cardory/domain/asset_template.dart';

void main() {
  group('AssetTemplate', () {
    test('内置模板含四套且字段 key 与旧 metadataJson 键对齐', () {
      final templates = builtInAssetTemplates();
      expect(
        templates.map((t) => t.id),
        containsAll(['tpl-software', 'tpl-hardware', 'tpl-domain', 'tpl-cert']),
      );
      final software = templates.firstWhere((t) => t.id == 'tpl-software');
      expect(
        software.fields.map((f) => f.key),
        containsAll(['version', 'port', 'path']),
      );
      final domain = templates.firstWhere((t) => t.id == 'tpl-domain');
      expect(
        domain.fields.where((f) => f.remind).map((f) => f.key),
        contains('expiryDate'),
      );
    });

    test('模板 JSON 往返无损；未知 kind 回退 text', () {
      final t = builtInAssetTemplates().firstWhere((t) => t.id == 'tpl-cert');
      final restored = AssetTemplate.fromJson(t.toJson());
      expect(restored.id, t.id);
      expect(restored.fields.length, t.fields.length);
      final bad = AssetTemplateField.fromJson({
        'key': 'k',
        'label': 'K',
        'kind': 'nope',
      });
      expect(bad.kind, AssetFieldKind.text);
    });
  });
}
