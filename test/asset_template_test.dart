import 'package:flutter_test/flutter_test.dart';

import 'package:cardory/domain/asset_template.dart';

void main() {
  group('AssetTemplate', () {
    test('内置模板默认两套（软件/硬件），字段 key 与旧 metadataJson 键对齐', () {
      final templates = builtInAssetTemplates();
      expect(templates.map((t) => t.id), ['tpl-software', 'tpl-hardware']);
      final software = templates.firstWhere((t) => t.id == 'tpl-software');
      expect(
        software.fields.map((f) => f.key),
        containsAll(['version', 'port', 'path']),
      );
      final hardware = templates.firstWhere((t) => t.id == 'tpl-hardware');
      expect(
        hardware.fields.map((f) => f.key),
        containsAll(['serialNumber', 'network', 'serverType']),
      );
      expect(templates.every((t) => t.builtIn), isTrue);
    });

    test('模板 JSON 往返无损；未知 kind 回退 text', () {
      const t = AssetTemplate(
        id: 'tpl-custom-1',
        name: '域名',
        fields: [
          AssetTemplateField(
            key: 'expiryDate',
            label: '到期日',
            kind: AssetFieldKind.date,
            required: true,
            remind: true,
          ),
        ],
      );
      final restored = AssetTemplate.fromJson(t.toJson());
      expect(restored.id, t.id);
      expect(restored.fields.length, t.fields.length);
      expect(restored.fields.single.remind, isTrue);
      expect(restored.fields.single.required, isTrue);
      final bad = AssetTemplateField.fromJson({
        'key': 'k',
        'label': 'K',
        'kind': 'nope',
      });
      expect(bad.kind, AssetFieldKind.text);
    });
  });
}
