// AppSettings 承载资产模板清单：默认内置模板、JSON 往返、copyWith 与配置同步。

import 'package:cardory/domain/app_settings.dart';
import 'package:cardory/domain/asset_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings.assetTemplates', () {
    test('assetTemplates 默认内置模板，JSON 往返无损', () {
      const settings = AppSettings();

      expect(settings.assetTemplates.length, 4);
      final json = settings.toJson();
      final restored = AppSettings.fromJson(json);
      expect(restored.assetTemplates.length, 4);
      expect(restored.assetTemplates.first.id, 'tpl-software');
    });

    test('fromJson 解析 assetTemplates 列表', () {
      final settings = AppSettings.fromJson(const {
        'assetTemplates': [
          {
            'id': 'tpl-custom',
            'name': '自定义',
            'fields': [
              {'key': 'owner', 'label': '负责人'},
            ],
            'builtIn': false,
          },
        ],
      });

      expect(settings.assetTemplates, hasLength(1));
      expect(settings.assetTemplates.single.id, 'tpl-custom');
      expect(settings.assetTemplates.single.builtIn, isFalse);
      expect(settings.assetTemplates.single.fields.single.key, 'owner');
    });

    test('fromJson 空 assetTemplates 回退内置模板', () {
      final settings = AppSettings.fromJson(const {
        'assetTemplates': <Map<String, dynamic>>[],
      });

      expect(settings.assetTemplates.length, 4);
      expect(settings.assetTemplates.every((t) => t.builtIn), isTrue);
      expect(settings.assetTemplates.first.id, 'tpl-software');
    });

    test('copyWith 可替换 assetTemplates', () {
      const settings = AppSettings();
      final custom = [const AssetTemplate(id: 'tpl-x', name: 'X', fields: [])];

      final updated = settings.copyWith(assetTemplates: custom);

      expect(updated.assetTemplates, same(custom));
      // 原设置不受影响。
      expect(settings.assetTemplates.length, 4);
    });

    test('toSyncConfigJson 携带 assetTemplates', () {
      const settings = AppSettings();

      final syncJson = settings.toSyncConfigJson();

      expect(syncJson['assetTemplates'], isA<List>());
      expect((syncJson['assetTemplates'] as List), hasLength(4));
    });

    test('applySyncConfig 应用云端模板清单', () {
      const local = AppSettings();
      final cloud = local
          .copyWith(
            assetTemplates: [
              const AssetTemplate(id: 'tpl-y', name: 'Y', fields: []),
            ],
          )
          .toSyncConfigJson();

      final applied = local.applySyncConfig(cloud);

      expect(applied.assetTemplates, hasLength(1));
      expect(applied.assetTemplates.single.id, 'tpl-y');
    });

    test('applySyncConfig 对无 assetTemplates 键的旧配置保留本地模板', () {
      final local = const AppSettings().copyWith(
        assetTemplates: [
          const AssetTemplate(id: 'tpl-z', name: 'Z', fields: []),
        ],
      );

      final applied = local.applySyncConfig(const {'themeColorValue': 1});

      expect(applied.assetTemplates.single.id, 'tpl-z');
      expect(applied.themeColorValue, 1);
    });
  });
}
