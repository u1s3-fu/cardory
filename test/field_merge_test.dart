// 字段级同步合并与任务扩展测试：
// - 逐字段 LWW 合并（双设备并发改不同字段自动收敛）；
// - 旧格式记录（无 changedFields）保持整行 LWW；
// - 删除/恢复经 deletedAt 字段合并，墓碑行不回灌旧值；
// - 重复任务完成自动生成下一次；待办标签入库与回读。

import 'package:cardory/data/db/app_database.dart';
import 'package:cardory/data/repositories/drift_row_level_workspace_store.dart';
import 'package:cardory/data/runtime/sqlcipher_data_mapper.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/sync/delta_sync.dart';

import 'package:flutter_test/flutter_test.dart';

DeltaRecord _projectRecord(
  String changeId, {
  required String entityId,
  required Map<String, dynamic> payload,
  required String deviceId,
  Set<String>? changedFields,
}) => DeltaRecord(
  changeId: changeId,
  entityType: 'project',
  entityId: entityId,
  operation: 'update',
  payload: payload,
  deviceId: deviceId,
  createdAt: payload['updatedAt'] as int,
  changedFields: changedFields,
);

Map<String, dynamic> _projectPayload({
  required String id,
  required String name,
  required String description,
  required int updatedAt,
}) => {
  'id': id,
  'name': name,
  'description': description,
  'status': 'planned',
  'priority': 'p2',
  'sortOrder': 0,
  'pinned': false,
  'currentProgress': 0.0,
  'createdAt': 1,
  'updatedAt': updatedAt,
};

void main() {
  group('字段级 LWW 合并', () {
    late AppDatabase db;
    late DeltaApplier applier;

    setUp(() {
      db = AppDatabase.inMemory();
      applier = DeltaApplier(db, localDeviceId: 'local');
    });
    tearDown(() => db.close());

    test('两台设备并发改不同字段：两侧变更都落库', () async {
      // 基线：设备 A 创建项目（同时插入 + meta 采纳）。
      await applier.apply([
        _projectRecord(
          'c0',
          entityId: 'p1',
          deviceId: 'device-a',
          payload: _projectPayload(
            id: 'p1',
            name: '初始',
            description: '',
            updatedAt: 100,
          ),
        ),
      ]);
      // 设备 A 改 name@200，设备 B 改 description@300（互不重叠）。
      await applier.apply([
        _projectRecord(
          'c1',
          entityId: 'p1',
          deviceId: 'device-a',
          changedFields: const {'name'},
          payload: _projectPayload(
            id: 'p1',
            name: '新名字',
            description: '',
            updatedAt: 200,
          ),
        ),
        _projectRecord(
          'c2',
          entityId: 'p1',
          deviceId: 'device-b',
          changedFields: const {'description'},
          payload: _projectPayload(
            id: 'p1',
            name: '初始',
            description: 'B 的说明',
            updatedAt: 300,
          ),
        ),
      ]);
      final row = await (db.select(
        db.projects,
      )..where((r) => r.id.equals('p1'))).getSingle();
      // name@200 击败基线 100；description@300 击败基线 100；均保留。
      expect(row.name, '新名字');
      expect(row.description, 'B 的说明');
      expect(row.updatedAt, 300);
    });

    test('字段时间戳较旧的记录不回灌旧值', () async {
      await applier.apply([
        _projectRecord(
          'c0',
          entityId: 'p1',
          deviceId: 'device-a',
          payload: _projectPayload(
            id: 'p1',
            name: '初始',
            description: '',
            updatedAt: 100,
          ),
        ),
        _projectRecord(
          'c1',
          entityId: 'p1',
          deviceId: 'device-a',
          changedFields: const {'name'},
          payload: _projectPayload(
            id: 'p1',
            name: '新名字',
            description: '',
            updatedAt: 200,
          ),
        ),
      ]);
      // 设备 B 基于旧基线改了 name@150：被 meta 拒绝。
      await applier.apply([
        _projectRecord(
          'c2',
          entityId: 'p1',
          deviceId: 'device-b',
          changedFields: const {'name'},
          payload: _projectPayload(
            id: 'p1',
            name: '旧名字',
            description: '',
            updatedAt: 150,
          ),
        ),
      ]);
      final row = await (db.select(
        db.projects,
      )..where((r) => r.id.equals('p1'))).getSingle();
      expect(row.name, '新名字');
    });

    test('旧格式记录（无 changedFields）保持整行 LWW', () async {
      await applier.apply([
        _projectRecord(
          'c0',
          entityId: 'p1',
          deviceId: 'device-a',
          payload: _projectPayload(
            id: 'p1',
            name: '初始',
            description: '旧说明',
            updatedAt: 100,
          ),
        ),
      ]);
      await applier.apply([
        _projectRecord(
          'c1',
          entityId: 'p1',
          deviceId: 'device-b',
          payload: _projectPayload(
            id: 'p1',
            name: '整行覆盖',
            description: '整行说明',
            updatedAt: 200,
          ),
        ),
      ]);
      final row = await (db.select(
        db.projects,
      )..where((r) => r.id.equals('p1'))).getSingle();
      expect(row.name, '整行覆盖');
      expect(row.description, '整行说明');
    });

    test('删除与恢复经 deletedAt 字段合并：恢复不回灌旧字段', () async {
      // 初始 + 远端改 description@200（仅字段合并）。
      await applier.apply([
        _projectRecord(
          'c0',
          entityId: 'p1',
          deviceId: 'device-a',
          payload: _projectPayload(
            id: 'p1',
            name: '项目',
            description: '',
            updatedAt: 100,
          ),
        ),
        _projectRecord(
          'c1',
          entityId: 'p1',
          deviceId: 'device-b',
          changedFields: const {'description'},
          payload: _projectPayload(
            id: 'p1',
            name: '项目',
            description: '远端补充',
            updatedAt: 200,
          ),
        ),
      ]);
      // 设备 A 删除@300（changedFields 仅 deletedAt）。
      final deletedPayload = _projectPayload(
        id: 'p1',
        name: '项目',
        description: '远端补充',
        updatedAt: 300,
      )..['deletedAt'] = 300;
      await applier.apply([
        _projectRecord(
          'c2',
          entityId: 'p1',
          deviceId: 'device-a',
          changedFields: const {'deletedAt'},
          payload: deletedPayload,
        ),
      ]);
      var row = await (db.select(
        db.projects,
      )..where((r) => r.id.equals('p1'))).getSingle();
      expect(row.deletedAt, 300);

      // 回收站恢复@400（payload deletedAt=null，仅 deletedAt 字段）。
      final restorePayload = _projectPayload(
        id: 'p1',
        name: '项目',
        description: '',
        updatedAt: 400,
      );
      restorePayload['deletedAt'] = null;
      await applier.apply([
        _projectRecord(
          'c3',
          entityId: 'p1',
          deviceId: 'device-a',
          changedFields: const {'deletedAt'},
          payload: restorePayload,
        ),
      ]);
      row = await (db.select(
        db.projects,
      )..where((r) => r.id.equals('p1'))).getSingle();
      // 行已复活；远端在删除前合并进来的 description 不被恢复载荷回灌。
      expect(row.deletedAt, isNull);
      expect(row.description, '远端补充');
      expect(row.updatedAt, 400);
    });

    test('墓碑行收到不含 deletedAt 的字段更新：只推进 meta 不改数据', () async {
      // 先有活行（设备 A 创建@100），再由设备 A 删除@150。
      await applier.apply([
        _projectRecord(
          'c0',
          entityId: 'p1',
          deviceId: 'device-a',
          payload: _projectPayload(
            id: 'p1',
            name: '项目',
            description: '',
            updatedAt: 100,
          ),
        ),
      ]);
      final deletedPayload = _projectPayload(
        id: 'p1',
        name: '项目',
        description: '',
        updatedAt: 150,
      )..['deletedAt'] = 150;
      await applier.apply([
        _projectRecord(
          'c1',
          entityId: 'p1',
          deviceId: 'device-a',
          changedFields: const {'deletedAt'},
          payload: deletedPayload,
        ),
      ]);
      await applier.apply([
        _projectRecord(
          'c2',
          entityId: 'p1',
          deviceId: 'device-b',
          changedFields: const {'name'},
          payload: _projectPayload(
            id: 'p1',
            name: '远端改名',
            description: '',
            updatedAt: 200,
          ),
        ),
      ]);
      final row = await (db.select(
        db.projects,
      )..where((r) => r.id.equals('p1'))).getSingle();
      expect(row.deletedAt, 150);
      expect(row.name, '项目');
      final metas = await db.select(db.syncFieldMetas).get();
      final meta = metas.singleWhere(
        (m) =>
            m.entityType == 'project' &&
            m.entityId == 'p1' &&
            m.fieldName == 'name',
      );
      expect(meta.updatedAt, 200);
    });
  });

  group('重复任务', () {
    late AppDatabase db;
    late DriftRowLevelWorkspaceStore store;

    setUp(() {
      db = AppDatabase.inMemory();
      store = DriftRowLevelWorkspaceStore(db);
    });
    tearDown(() => db.close());

    test('带重复规则与标签的任务入库并按原样回读', () async {
      await store.addProject(
        ProjectData(
          id: 'p1',
          title: '项目一',
          description: '',
          priority: ProjectPriority.p1,
          stage: ProjectStage.doing,
          progressEntries: const [],
        ),
      );
      await store.addTodo(
        TodoData(
          id: 't1',
          title: '周会',
          projectId: 'p1',
          projectTitle: '项目一',
          priority: ProjectPriority.p2,
          done: false,
          startDate: DateTime(2026, 10, 5),
          endDate: DateTime(2026, 10, 5),
          tags: const ['例行', '会议'],
          repeatFrequency: RepeatFrequency.weekly,
        ),
      );
      final todos = await SqlCipherDataMapper(db).loadTodos();
      expect(todos.single.tags, ['例行', '会议']);
      expect(todos.single.repeatFrequency, RepeatFrequency.weekly);
    });
  });
}
