// delta 引擎测试：LWW 应用、冲突检测、敏感列保留、加密往返与 tombstone 清理。

import 'package:cardory/data/db/app_database.dart';
import 'package:cardory/sync/delta_sync.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';

DeltaRecord _record(
  String changeId, {
  required String entityType,
  required String entityId,
  required Map<String, dynamic> payload,
  String deviceId = 'device-a',
  String operation = 'update',
}) => DeltaRecord(
  changeId: changeId,
  entityType: entityType,
  entityId: entityId,
  operation: operation,
  payload: payload,
  deviceId: deviceId,
  createdAt: 1000,
);

Map<String, dynamic> _projectPayload({
  required String id,
  required String name,
  required int updatedAt,
  int? deletedAt,
  String status = 'planned',
}) => {
  'id': id,
  'name': name,
  'description': '',
  'status': status,
  'priority': 'p2',
  'sortOrder': 0,
  'pinned': false,
  'currentProgress': 0.0,
  'createdAt': 1,
  'updatedAt': updatedAt,
  if (deletedAt != null) 'deletedAt': deletedAt,
};

void main() {
  late AppDatabase db;
  late DeltaApplier applier;

  setUp(() {
    db = AppDatabase.inMemory();
    applier = DeltaApplier(db, localDeviceId: 'local');
  });
  tearDown(() => db.close());

  test('远端新增记录插入本地行，更高 updatedAt 覆盖本地', () async {
    final result = await applier.apply([
      _record(
        'c1',
        entityType: 'project',
        entityId: 'p1',
        payload: _projectPayload(id: 'p1', name: '来自远端', updatedAt: 100),
      ),
    ]);
    expect(result.applied, 1);
    final row = await (db.select(
      db.projects,
    )..where((r) => r.id.equals('p1'))).getSingle();
    expect(row.name, '来自远端');

    final second = await applier.apply([
      _record(
        'c2',
        entityType: 'project',
        entityId: 'p1',
        payload: _projectPayload(id: 'p1', name: '远端更新', updatedAt: 200),
      ),
    ]);
    expect(second.applied, 1);
    final updated = await (db.select(
      db.projects,
    )..where((r) => r.id.equals('p1'))).getSingle();
    expect(updated.name, '远端更新');
  });

  test('本地更新（updatedAt 更大）时跳过远端旧记录', () async {
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: '本地较新',
            status: 'planned',
            priority: 'p2',
            createdAt: 1,
            updatedAt: 500,
          ),
        );
    final result = await applier.apply([
      _record(
        'c1',
        entityType: 'project',
        entityId: 'p1',
        payload: _projectPayload(id: 'p1', name: '远端较旧', updatedAt: 100),
      ),
    ]);
    expect(result.skipped, 1);
    final row = await (db.select(
      db.projects,
    )..where((r) => r.id.equals('p1'))).getSingle();
    expect(row.name, '本地较新');
  });

  test('相同 updatedAt 且载荷一致时幂等跳过；不一致时报冲突', () async {
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: '同名',
            status: 'planned',
            priority: 'p2',
            createdAt: 1,
            updatedAt: 100,
          ),
        );
    final same = await applier.apply([
      _record(
        'c1',
        entityType: 'project',
        entityId: 'p1',
        payload: _projectPayload(id: 'p1', name: '同名', updatedAt: 100),
      ),
    ]);
    expect(same.skipped, 1);
    expect(same.conflicts, isEmpty);

    final differs = await applier.apply([
      _record(
        'c2',
        entityType: 'project',
        entityId: 'p1',
        payload: _projectPayload(
          id: 'p1',
          name: '同名',
          status: 'doing',
          updatedAt: 100,
        ),
      ),
    ]);
    expect(differs.conflicts, hasLength(1));
    expect(differs.conflicts.single.entityId, 'p1');
  });

  test('远端删除记录（tombstone）覆盖较旧的本地行', () async {
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: '将被删除',
            status: 'planned',
            priority: 'p2',
            createdAt: 1,
            updatedAt: 100,
          ),
        );
    final result = await applier.apply([
      _record(
        'c1',
        entityType: 'project',
        entityId: 'p1',
        payload: _projectPayload(
          id: 'p1',
          name: '将被删除',
          updatedAt: 200,
          deletedAt: 200,
        ),
      ),
    ]);
    expect(result.applied, 1);
    final row = await (db.select(
      db.projects,
    )..where((r) => r.id.equals('p1'))).getSingle();
    expect(row.deletedAt, 200);
  });

  test('资产覆盖时保留本地敏感列（sensitiveJson 不出同步通道）', () async {
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'a1',
            type: 'software',
            title: '资产',
            sensitiveJson: const drift.Value('{"password":"secret"}'),
            createdAt: 1,
            updatedAt: 100,
          ),
        );
    await applier.apply([
      _record(
        'c1',
        entityType: 'asset',
        entityId: 'a1',
        payload: {
          'id': 'a1',
          'type': 'software',
          'title': '资产-远端改名',
          'uriOrPath': '',
          'note': '',
          'tagsJson': '[]',
          'metadataJson': '{}',
          'isLocalOnly': false,
          'createdAt': 1,
          'updatedAt': 200,
        },
      ),
    ]);
    final row = await (db.select(
      db.assets,
    )..where((r) => r.id.equals('a1'))).getSingle();
    expect(row.title, '资产-远端改名');
    expect(row.sensitiveJson, '{"password":"secret"}');
  });

  test('attachment 载荷携带 assetId 应用后保留，旧载荷（无 assetId）不崩', () async {
    // 外键目标：asset_id REFERENCES assets(id)。
    await db
        .into(db.assets)
        .insert(
          AssetsCompanion.insert(
            id: 'asset-1',
            type: 'software',
            title: 'Nginx',
            createdAt: 1,
            updatedAt: 1,
          ),
        );

    Map<String, dynamic> attachmentPayload(
      String id,
      String fileName, {
      required int updatedAt,
      String? assetId,
    }) => {
      'id': id,
      'projectId': null,
      'taskId': null,
      if (assetId != null) 'assetId': assetId,
      'fileName': fileName,
      'storageKey': '$id.cardory-attachment',
      'sizeBytes': 10,
      'sha256': 'deadbeef',
      'mimeType': '',
      'kind': 'document',
      'note': '',
      'isLocalOnly': false,
      'encryptionKey': '',
      'categoryIdsJson': '[]',
      'createdAt': 1,
      'updatedAt': updatedAt,
    };

    // 新版本载荷：assetId 随行载荷应用并保留。
    final applied = await applier.apply([
      _record(
        'c1',
        entityType: 'attachment',
        entityId: 'att-1',
        payload: attachmentPayload(
          'att-1',
          '发票.pdf',
          updatedAt: 100,
          assetId: 'asset-1',
        ),
      ),
    ]);
    expect(applied.applied, 1);
    final row = await (db.select(
      db.attachments,
    )..where((r) => r.id.equals('att-1'))).getSingle();
    expect(row.assetId, 'asset-1');

    // 旧版本载荷（无 assetId 键）：应用成功，行存在。
    final legacy = await applier.apply([
      _record(
        'c2',
        entityType: 'attachment',
        entityId: 'att-2',
        payload: attachmentPayload('att-2', '旧版.pdf', updatedAt: 100),
      ),
    ]);
    expect(legacy.applied, 1);
    final legacyRow = await (db.select(
      db.attachments,
    )..where((r) => r.id.equals('att-2'))).getSingle();
    expect(legacyRow.assetId, isNull);
  });

  test('feed 编解码往返与加密互认', () async {
    final codec = const DeltaFeedCodec();
    final records = [
      _record(
        'c1',
        entityType: 'project',
        entityId: 'p1',
        payload: _projectPayload(id: 'p1', name: 'X', updatedAt: 1),
      ),
    ];
    final text = codec.serialize(records);
    expect(codec.parse(text).single.changeId, 'c1');

    final cipher = DeltaFeedCipher('vault-password');
    final sealed = await cipher.seal(text);
    expect(await cipher.open(sealed), text);
    // 密文不应包含明文片段。
    expect(String.fromCharCodes(sealed), isNot(contains('project')));
    // 密码不同 → 解密必须失败。
    expect(() => DeltaFeedCipher('wrong').open(sealed), throwsA(anything));
  });

  test('purgeTombstones 清理超过保留期的软删除行', () async {
    final now = DateTime.utc(2026, 9, 13);
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'old',
            name: '过期 tombstone',
            status: 'planned',
            priority: 'p2',
            createdAt: 1,
            updatedAt: 1,
            deletedAt: drift.Value(
              now.subtract(const Duration(days: 40)).millisecondsSinceEpoch,
            ),
          ),
        );
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'new',
            name: '新鲜 tombstone',
            status: 'planned',
            priority: 'p2',
            createdAt: 1,
            updatedAt: 1,
            deletedAt: drift.Value(
              now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
            ),
          ),
        );
    final purged = await purgeTombstones(db, now: now);
    expect(purged, 1);
    final remaining = await db.select(db.projects).get();
    expect(remaining.single.id, 'new');
  });
}
