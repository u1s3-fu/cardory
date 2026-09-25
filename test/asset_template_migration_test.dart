// AssetData.templateId/customFields 与旧数据读时归一化的测试。

import 'dart:convert';

import 'package:cardory/data/db/app_database.dart'
    hide ProjectProgressEntry, AttachmentCategory, AssetTag;
import 'package:cardory/data/repositories/drift_row_level_workspace_store.dart';
import 'package:cardory/data/runtime/sqlcipher_data_mapper.dart';
import 'package:cardory/domain/asset_template.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('旧 software 资产读时归一化到 tpl-software，旧键可见为 customFields', () {
    final asset = const AssetData(
      id: 'a1',
      type: AssetType.software,
      name: 'Nginx',
    ).copyWith(version: '1.24', port: '443');
    // 模拟旧行：metadataJson 无 templateId/custom，仅旧顶层键（store 映射层行为
    // 等价于 version/port 已在字段里）。
    final normalized = normalizeAssetTemplate(asset, builtInAssetTemplates());
    expect(normalized.templateId, 'tpl-software');
    expect(normalized.customFields['version'], '1.24');
    expect(normalized.customFields['port'], '443');
  });

  test('已显式设置 templateId 的资产不再改写', () {
    final asset = const AssetData(
      id: 'a2',
      type: AssetType.hardware,
      name: 'NAS',
    ).copyWith(templateId: 'tpl-custom-1');
    expect(
      normalizeAssetTemplate(asset, builtInAssetTemplates()).templateId,
      'tpl-custom-1',
    );
  });

  test('metadataJson 布局往返：templateId 与 custom 进出无损且保留旧键', () async {
    final database = AppDatabase.inMemory();
    final store = DriftRowLevelWorkspaceStore(database);
    addTearDown(database.close);

    const asset = AssetData(
      id: 'asset-1',
      type: AssetType.software,
      name: 'Nginx',
      version: '1.24',
      port: '443',
      templateId: 'tpl-domain',
      customFields: {'registrar': 'Aliyun'},
    );
    await store.addAsset(asset);

    final loaded = await SqlCipherDataMapper(database).loadAssets();
    expect(loaded, hasLength(1));
    expect(loaded.single.templateId, 'tpl-domain');
    expect(loaded.single.customFields['registrar'], 'Aliyun');

    // raw db 读 metadataJson 原文：旧顶层键继续保留。
    final row = await (database.select(
      database.assets,
    )..where((r) => r.id.equals('asset-1'))).getSingle();
    final metadata = jsonDecode(row.metadataJson) as Map<String, dynamic>;
    expect(metadata['templateId'], 'tpl-domain');
    expect(
      (metadata['custom'] as Map<dynamic, dynamic>)['registrar'],
      'Aliyun',
    );
    expect(metadata['version'], '1.24');
    expect(metadata['port'], '443');
  });
}
