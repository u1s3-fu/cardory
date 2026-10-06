// 实体级增量同步（delta）引擎。
//
// 协议：远端单一 delta 文件 `cardory-delta-v1.bin`（AES-GCM 加密的 JSONL，
// 密钥由保险库密码派生——delta 载荷含完整实体行，且资产敏感字段不出加密
// 边界）。每台设备把本地 sync_changes 中待推送的记录追加进 feed；拉取时
// 仅应用其他设备的记录，按 updatedAt 做 LWW：
// - 远端 updatedAt 更新 → 覆盖本地行；
// - 相等且载荷一致 → 幂等跳过；
// - 相等但载荷不同 → 交给逐实体冲突界面；
// - 本地更新 → 跳过（远端稍后会因本设备的推送而收敛）。
//
// 已删除行（tombstone）超过保留期后由 [purgeTombstones] 清理，避免软删除
// 数据无限累积。

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../data/db/app_database.dart' as db;
import 'sync_models.dart' show SyncProviderException;

/// 远端 delta 文档键。
const deltaDocumentKey = 'cardory-delta-v1.bin';

/// 一条实体级变更记录（对应本地 sync_changes 一行）。
class DeltaRecord {
  const DeltaRecord({
    required this.changeId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.deviceId,
    required this.createdAt,
    this.changedFields,
  });

  factory DeltaRecord.fromChange(db.SyncChange change) => DeltaRecord(
    changeId: change.id,
    entityType: change.entityType,
    entityId: change.entityId,
    operation: change.operation,
    payload: jsonDecode(change.payloadJson) as Map<String, dynamic>,
    deviceId: change.deviceId,
    createdAt: change.createdAt,
    changedFields: _parseChangedFields(change.changedFields),
  );

  /// 本次写入实际变更的载荷键（null = 旧格式，整行 LWW）。
  final Set<String>? changedFields;

  factory DeltaRecord.fromJson(Map<String, dynamic> json) => DeltaRecord(
    changeId: json['changeId'] as String,
    entityType: json['entityType'] as String,
    entityId: json['entityId'] as String,
    operation: json['operation'] as String,
    payload: (json['payload'] as Map).cast<String, dynamic>(),
    deviceId: json['deviceId'] as String,
    createdAt: json['createdAt'] as int,
    changedFields: _parseChangedFields(json['changedFields'] as String?),
  );

  static Set<String>? _parseChangedFields(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<String>().toSet();
    } catch (_) {
      return null;
    }
  }

  final String changeId;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payload;
  final String deviceId;
  final int createdAt;

  Map<String, dynamic> toJson() => {
    'changeId': changeId,
    'entityType': entityType,
    'entityId': entityId,
    'operation': operation,
    'payload': payload,
    'deviceId': deviceId,
    'createdAt': createdAt,
    if (changedFields != null)
      'changedFields': jsonEncode(changedFields!.toList()),
  };
}

/// delta feed 的 JSONL 编解码。
class DeltaFeedCodec {
  const DeltaFeedCodec();

  String serialize(Iterable<DeltaRecord> records) =>
      records.map((record) => jsonEncode(record.toJson())).join('\n');

  List<DeltaRecord> parse(String text) => text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map(
        (line) =>
            DeltaRecord.fromJson(jsonDecode(line) as Map<String, dynamic>),
      )
      .toList();
}

/// 一条无法用 LWW 自动裁决的记录（时间戳相等但载荷不同）。
class DeltaConflict {
  const DeltaConflict({
    required this.record,
    required this.localUpdatedAt,
    this.differingFields = const [],
  });

  final DeltaRecord record;
  final int localUpdatedAt;

  /// 与本地当前行存在差异的字段名（updatedAt 除外），供界面呈现差异明细。
  final List<String> differingFields;

  String get entityType => record.entityType;
  String get entityId => record.entityId;
}

class DeltaApplyResult {
  const DeltaApplyResult({
    this.applied = 0,
    this.skipped = 0,
    this.conflicts = const [],
  });

  final int applied;
  final int skipped;
  final List<DeltaConflict> conflicts;
}

/// 把远端 delta 记录按 LWW 应用到本地数据库。
class DeltaApplier {
  DeltaApplier(this._db, {required this.localDeviceId});

  final db.AppDatabase _db;

  /// 本设备标识；记录的 deviceId 与之相同时跳过（本地行即权威状态）。
  final String localDeviceId;

  /// 实体类型的 FK 依赖层级：父表实体先于子表实体应用，让绝大多数
  /// feed 顺序在第一轮就能落库；同表自引用（任务父链）等剩余顺序交给
  /// 多轮重试收敛。
  static const _entityRank = <String, int>{
    'project': 0,
    'asset_tag': 1,
    'attachment_category': 1,
    'task': 2,
    'milestone': 3,
    'project_progress_entry': 3,
    'time_entry': 3,
    'pomodoro_session': 3,
    'asset': 4,
    'attachment': 5,
    'task_dependency': 6,
  };

  static int _rankOf(DeltaRecord record) =>
      _entityRank[record.entityType] ?? (_entityRank.length ~/ 2);

  /// 上一次 [_applyRow] 判定为冲突时与本地行的差异字段名。apply 循环
  /// 串行执行、判定后立即读取，不跨事件使用。
  List<String> _lastConflictFields = const [];

  /// SQL 列名（snake_case）→ 载荷 JSON 键（camelCase，drift 默认命名）。
  static String _jsonKeyOf(String sqlName) {
    final parts = sqlName.split('_');
    return parts.first +
        [
          for (final part in parts.skip(1))
            part.isEmpty ? '' : '${part[0].toUpperCase()}${part.substring(1)}',
        ].join();
  }

  /// 补齐旧版本 feed 载荷缺失的新增列：以列默认值（或 null）回填，
  /// 保证 typed fromJson 在跨版本同步下不因缺键崩溃。
  static Map<String, dynamic> _normalizePayload(
    TableInfo table,
    Map<String, dynamic> payload,
  ) {
    final normalized = Map<String, dynamic>.of(payload);
    for (final column in table.$columns) {
      final key = _jsonKeyOf(column.name);
      if (normalized.containsKey(key)) continue;
      final constant = column.defaultValue is Constant
          ? column.defaultValue! as Constant
          : null;
      normalized[key] = constant?.value;
    }
    return normalized;
  }

  /// 比较快照与本地行的 JSON 值差异（updatedAt 除外；双向覆盖键缺失）。
  static List<String> _differingFieldsOf(
    Map<String, dynamic> incoming,
    Map<String, dynamic> existing,
  ) {
    String encode(Object? value) {
      try {
        return jsonEncode(value);
      } catch (_) {
        return value.toString();
      }
    }

    final differing = <String>[];
    for (final key in incoming.keys) {
      if (key == 'updatedAt') continue;
      if (!existing.containsKey(key) ||
          encode(incoming[key]) != encode(existing[key])) {
        differing.add(key);
      }
    }
    for (final key in existing.keys) {
      if (key == 'updatedAt' || incoming.containsKey(key)) continue;
      differing.add(key);
    }
    return differing;
  }

  Future<DeltaApplyResult> apply(Iterable<DeltaRecord> records) async {
    var applied = 0;
    var skipped = 0;
    final conflicts = <DeltaConflict>[];
    final all = records.toList();
    // 自己的记录直接跳过（本地行即权威状态）；其余按 FK 层级排序后
    // 多轮应用：单条失败（如引用行尚未落库）推迟到下一轮重试，引用
    // 已删数据的坏行不阻塞其余记录收敛。每条记录在独立事务中应用，
    // 与写入侧「实体行 + sync_changes 单事务」的原子性口径一致。
    var pending =
        all.where((record) => record.deviceId != localDeviceId).toList()
          ..sort((a, b) => _rankOf(a).compareTo(_rankOf(b)));
    skipped += all.length - pending.length;
    while (pending.isNotEmpty) {
      final deferred = <DeltaRecord>[];
      Object? firstFailure;
      for (final record in pending) {
        try {
          final outcome = await _db.transaction(() => _applyOne(record));
          switch (outcome) {
            case _ApplyOutcome.applied:
              applied++;
            case _ApplyOutcome.skipped:
              skipped++;
            case _ApplyOutcome.conflict:
              conflicts.add(
                DeltaConflict(
                  record: record,
                  localUpdatedAt: _payloadUpdatedAt(record),
                  differingFields: _lastConflictFields,
                ),
              );
          }
        } catch (error) {
          firstFailure ??= error;
          deferred.add(record);
        }
      }
      if (deferred.length == pending.length) {
        // 整轮无一成功：剩余记录引用了本地永远缺失的行（如已被级联
        // 删除的父实体），继续重试只会永久卡死同步。已应用的记录保持
        // 已应用（重放幂等），这里如实抛错让界面提示重试。
        throw SyncProviderException(
          '增量数据无法应用，可能引用了已删除的记录，请重新同步或联系开发者。',
          cause: firstFailure,
        );
      }
      pending = deferred;
    }
    return DeltaApplyResult(
      applied: applied,
      skipped: skipped,
      conflicts: conflicts,
    );
  }

  static int _payloadUpdatedAt(DeltaRecord record) =>
      (record.payload['updatedAt'] as num?)?.toInt() ?? 0;

  Future<_ApplyOutcome> _applyOne(DeltaRecord record) async {
    final incomingUpdatedAt = _payloadUpdatedAt(record);
    switch (record.entityType) {
      case 'project':
        return _applyRow(
          record,
          entityType: record.entityType,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.projects,
          fromJson: db.Project.fromJson,
        );
      case 'task':
        return _applyRow(
          record,
          entityType: record.entityType,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.tasks,
          fromJson: db.Task.fromJson,
        );
      case 'asset':
        // 资产的敏感字段（账号/密码）不出同步通道：覆盖时保留本地列。
        return _applyRow<db.Asset>(
          record,
          entityType: record.entityType,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.assets,
          fromJson: db.Asset.fromJson,
          preserve: (current, incoming) =>
              incoming.copyWith(sensitiveJson: Value(current.sensitiveJson)),
        );
      case 'asset_tag':
        return _applyRow(
          record,
          entityType: record.entityType,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.assetTags,
          fromJson: db.AssetTag.fromJson,
        );
      case 'attachment':
        return _applyRow(
          record,
          entityType: record.entityType,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.attachments,
          fromJson: db.Attachment.fromJson,
        );
      case 'attachment_category':
        return _applyRow(
          record,
          entityType: record.entityType,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.attachmentCategories,
          fromJson: db.AttachmentCategory.fromJson,
        );
      case 'project_progress_entry':
        return _applyRow(
          record,
          entityType: record.entityType,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.projectProgressEntries,
          fromJson: db.ProjectProgressEntry.fromJson,
        );
      case 'time_entry':
        return _applyRow(
          record,
          entityType: record.entityType,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.timeEntries,
          fromJson: db.TimeEntry.fromJson,
        );
      case 'pomodoro_session':
        return _applyRow(
          record,
          entityType: record.entityType,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.pomodoroSessions,
          fromJson: db.PomodoroSession.fromJson,
        );
      case 'task_dependency':
        return _applyRow(
          record,
          entityType: record.entityType,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.taskDependencies,
          fromJson: db.TaskDependency.fromJson,
        );
      case 'milestone':
        return _applyRow(
          record,
          entityType: record.entityType,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.milestones,
          fromJson: db.Milestone.fromJson,
        );
      default:
        return _ApplyOutcome.skipped;
    }
  }

  /// 通用行级应用：
  ///
  /// - 本地无行：整行插入（远端删除不存在的行幂等跳过）；
  /// - 旧格式记录（changedFields == null）：整行 LWW（updatedAt 比较）；
  /// - 新格式记录：按 changedFields 逐字段 LWW——只应用字段时间戳比本地
  ///   sync_field_metas 更新的列，与本机对其他列的并发修改自动合并。
  ///
  /// 逐字段合并通过「以本地行为底、叠加应用字段」重建完整载荷后走 typed
  /// fromJson 整行写实现；applied 后把应用字段的 meta 抬到记录时间戳，
  /// 旧格式整行应用则把全部字段 meta 抬到 incomingUpdatedAt（后续字段级
  /// 合并以它为基线）。[preserve] 允许在整行覆盖前把本地独有列（如资产
  /// sensitiveJson，不出同步通道）合并进远端行。
  Future<_ApplyOutcome> _applyRow<T extends DataClass>(
    DeltaRecord record, {
    required String entityType,
    required int incomingUpdatedAt,
    required TableInfo table,
    required T Function(Map<String, dynamic>) fromJson,
    T Function(T current, T incoming)? preserve,
  }) async {
    final idColumn = table.columnsByName['id'];
    final updatedAtColumn = table.columnsByName['updated_at'];
    if (idColumn == null || updatedAtColumn == null) {
      return _ApplyOutcome.skipped;
    }
    final incoming = fromJson(_normalizePayload(table, record.payload));
    final existing =
        await (table.select()..where((_) => idColumn.equals(record.entityId)))
            .getSingleOrNull();
    if (existing == null) {
      if (record.payload['deletedAt'] != null) {
        // 远端删除一个本地不存在的行：无需操作（tombstone 重放幂等）。
        return _ApplyOutcome.skipped;
      }
      await _db.into(table).insert(incoming as Insertable<dynamic>);
      await _adoptFieldMeta(
        entityType: entityType,
        entityId: record.entityId,
        row: incoming.toJson(),
        timestamp: incomingUpdatedAt,
      );
      return _ApplyOutcome.applied;
    }
    final currentUpdatedAt =
        (existing.toJson()['updatedAt'] as num?)?.toInt() ?? 0;
    if (incomingUpdatedAt < currentUpdatedAt) {
      return _ApplyOutcome.skipped;
    }

    final changed = record.changedFields;
    if (changed == null || changed.isEmpty) {
      if (incomingUpdatedAt == currentUpdatedAt) {
        if (jsonEncode(incoming.toJson()) == jsonEncode(existing.toJson())) {
          return _ApplyOutcome.skipped;
        }
        _lastConflictFields = _differingFieldsOf(
          incoming.toJson(),
          existing.toJson(),
        );
        return _ApplyOutcome.conflict;
      }
      final target = preserve?.call(existing, incoming) ?? incoming;
      await (_db.update(table)..where((_) => idColumn.equals(record.entityId)))
          .write(target as Insertable<dynamic>);
      await _adoptFieldMeta(
        entityType: entityType,
        entityId: record.entityId,
        row: target.toJson(),
        timestamp: incomingUpdatedAt,
      );
      return _ApplyOutcome.applied;
    }

    // 新格式：逐字段 LWW。meta 缺失视为 0（首次收到该字段的远端变更
    // 总能应用，与整行 LWW 的首同步行为一致）。
    final incomingJson = incoming.toJson();
    final localRowDeleted = existing.toJson()['deletedAt'] != null;
    final applied = <String, int>{};
    final appliedColumns = <String, Expression>{};
    for (final field in changed) {
      if (field == 'id' || !incomingJson.containsKey(field)) continue;
      final localTs = await _fieldMetaTs(
        entityType: entityType,
        entityId: record.entityId,
        field: field,
      );
      if (incomingUpdatedAt < localTs) continue;
      if (localRowDeleted && field != 'deletedAt') {
        // 墓碑行只推进 meta，不改数据（保持已删除事实）。
        applied[field] = incomingUpdatedAt;
        continue;
      }
      final column = table.columnsByName[_sqlKeyOf(field)];
      if (column == null) continue;
      final value = incomingJson[field];
      appliedColumns[column.name] = value == null
          ? const Constant(null)
          : Variable(value);
      applied[field] = incomingUpdatedAt;
    }
    if (applied.isEmpty) return _ApplyOutcome.skipped;
    // 行时间戳只前进（含删除/恢复的字段写入），保持审计与 LWW 语义。
    // 用 RawValuesInsertable 只写应用列：DataClass 整行写会跳过 null 的
    // 可空列（toColumns(nullToAbsent: true)），恢复（deletedAt=null）将
    // 永远无法清除本地墓碑。
    appliedColumns[updatedAtColumn.name] = Variable(
      incomingUpdatedAt > currentUpdatedAt
          ? incomingUpdatedAt
          : currentUpdatedAt,
    );
    await (_db.update(table)..where((_) => idColumn.equals(record.entityId)))
        .write(RawValuesInsertable<T>(appliedColumns));
    await _saveFieldMeta(
      entityType: entityType,
      entityId: record.entityId,
      fields: applied,
    );
    return _ApplyOutcome.applied;
  }

  /// 载荷 JSON 键（camelCase）→ SQL 列名（snake_case，drift 默认命名）。
  static String _sqlKeyOf(String jsonKey) {
    final buffer = StringBuffer();
    for (var i = 0; i < jsonKey.length; i++) {
      final char = jsonKey[i];
      if (_isUpper(char) && i > 0) buffer.write('_');
      buffer.write(char.toLowerCase());
    }
    return buffer.toString();
  }

  static bool _isUpper(String char) =>
      char.toUpperCase() == char && char.toLowerCase() != char;

  /// 把 [row] 的全部字段 meta 抬到 [timestamp]（整行应用/插入后调用）。
  Future<void> _adoptFieldMeta({
    required String entityType,
    required String entityId,
    required Map<String, dynamic> row,
    required int timestamp,
  }) async {
    final fields = <String, int>{
      for (final key in row.keys)
        if (key != 'id') key: timestamp,
    };
    await _saveFieldMeta(
      entityType: entityType,
      entityId: entityId,
      fields: fields,
    );
  }

  Future<int> _fieldMetaTs({
    required String entityType,
    required String entityId,
    required String field,
  }) async {
    final row =
        await (_db.select(_db.syncFieldMetas)..where(
              (r) =>
                  r.entityType.equals(entityType) &
                  r.entityId.equals(entityId) &
                  r.fieldName.equals(field),
            ))
            .getSingleOrNull();
    return row?.updatedAt ?? 0;
  }

  Future<void> _saveFieldMeta({
    required String entityType,
    required String entityId,
    required Map<String, int> fields,
  }) async {
    for (final entry in fields.entries) {
      await _db
          .into(_db.syncFieldMetas)
          .insertOnConflictUpdate(
            db.SyncFieldMetasCompanion.insert(
              entityType: entityType,
              entityId: entityId,
              fieldName: entry.key,
              updatedAt: entry.value,
            ),
          );
    }
  }

  TableInfo? _tableOf(String entityType) => switch (entityType) {
    'project' => _db.projects,
    'task' => _db.tasks,
    'asset' => _db.assets,
    'asset_tag' => _db.assetTags,
    'attachment' => _db.attachments,
    'attachment_category' => _db.attachmentCategories,
    'project_progress_entry' => _db.projectProgressEntries,
    'time_entry' => _db.timeEntries,
    'pomodoro_session' => _db.pomodoroSessions,
    'task_dependency' => _db.taskDependencies,
    'milestone' => _db.milestones,
    _ => null,
  };

  DataClass? _fromJson(String entityType, Map<String, dynamic> payload) =>
      switch (entityType) {
        'project' => db.Project.fromJson(payload),
        'task' => db.Task.fromJson(payload),
        'asset' => db.Asset.fromJson(payload),
        'asset_tag' => db.AssetTag.fromJson(payload),
        'attachment' => db.Attachment.fromJson(payload),
        'attachment_category' => db.AttachmentCategory.fromJson(payload),
        'project_progress_entry' => db.ProjectProgressEntry.fromJson(payload),
        'time_entry' => db.TimeEntry.fromJson(payload),
        'pomodoro_session' => db.PomodoroSession.fromJson(payload),
        'task_dependency' => db.TaskDependency.fromJson(payload),
        'milestone' => db.Milestone.fromJson(payload),
        _ => null,
      };

  DeltaRecord _rerecord(
    DeltaRecord source,
    Map<String, dynamic> payload,
    DateTime now,
  ) => DeltaRecord(
    changeId: const Uuid().v4(),
    entityType: source.entityType,
    entityId: source.entityId,
    operation: 'update',
    payload: payload,
    deviceId: source.deviceId,
    createdAt: now.toUtc().millisecondsSinceEpoch,
  );

  /// 冲突裁决：采纳远端载荷。为确保其他设备收敛，把 updatedAt 抬到
  /// [now]（否则等时间戳冲突会在对端反复出现），返回可直接推送的记录。
  Future<DeltaRecord> adoptRemote(
    DeltaConflict conflict, {
    required DateTime now,
  }) async {
    final record = conflict.record;
    final payload = Map<String, dynamic>.from(record.payload)
      ..['updatedAt'] = now.toUtc().millisecondsSinceEpoch;
    final table = _tableOf(record.entityType);
    if (table == null) return _rerecord(record, payload, now);
    final idColumn = table.columnsByName['id']!;
    final existing =
        await (table.select()..where((_) => idColumn.equals(record.entityId)))
            .getSingleOrNull();
    final incoming = _fromJson(record.entityType, payload);
    if (incoming == null) return _rerecord(record, payload, now);
    if (existing == null) {
      if (payload['deletedAt'] != null) return _rerecord(record, payload, now);
      await _db.into(table).insert(incoming as Insertable<dynamic>);
    } else {
      await (_db.update(table)..where((_) => idColumn.equals(record.entityId)))
          .write(incoming as Insertable<dynamic>);
    }
    return _rerecord(record, payload, now);
  }

  /// 冲突裁决：保留本地行。把本地 updatedAt 抬到 [now] 以在 LWW 下胜出，
  /// 返回可直接推送的记录（本地行无变化时返回 null）。
  Future<DeltaRecord?> keepLocal(
    DeltaConflict conflict, {
    required DateTime now,
  }) async {
    final record = conflict.record;
    final table = _tableOf(record.entityType);
    if (table == null) return null;
    final idColumn = table.columnsByName['id']!;
    final existing =
        await (table.select()..where((_) => idColumn.equals(record.entityId)))
            .getSingleOrNull();
    if (existing == null) return null;
    final payload = Map<String, dynamic>.from(existing.toJson())
      ..['updatedAt'] = now.toUtc().millisecondsSinceEpoch;
    return _rerecord(record, payload, now);
  }
}

enum _ApplyOutcome { applied, skipped, conflict }

/// tombstone 保留期：软删除超过该时长的行被物理清理。
const tombstoneRetention = Duration(days: 30);

/// 物理清理超过保留期的软删除行。
///
/// delta feed 中对应记录无需移除：重放已清理实体的删除记录是幂等的
/// （本地行不存在则跳过）。
Future<int> purgeTombstones(
  db.AppDatabase db, {
  DateTime? now,
  Duration olderThan = tombstoneRetention,
}) async {
  final cutoff = (now ?? DateTime.now().toUtc())
      .subtract(olderThan)
      .millisecondsSinceEpoch;
  final tables = <TableInfo>[
    db.projects,
    db.tasks,
    db.assets,
    db.assetTags,
    db.attachmentCategories,
    db.attachments,
    db.projectProgressEntries,
    db.timeEntries,
    db.pomodoroSessions,
    db.taskDependencies,
    db.milestones,
  ];
  var purged = 0;
  for (final table in tables) {
    final deletedAt = table.columnsByName['deleted_at'];
    if (deletedAt is! GeneratedColumn<int>) continue;
    purged += await (db.delete(
      table,
    )..where((_) => deletedAt.isSmallerThanValue(cutoff))).go();
  }
  return purged;
}

/// delta feed 的对称加密：AES-GCM-256，密钥由保险库密码 PBKDF2 派生。
class DeltaFeedCipher {
  DeltaFeedCipher(this.passphrase);

  static const _salt = 'cardory-delta-v1';
  static const _iterations = 120000;

  final String passphrase;

  Future<SecretKey> _key() => Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  ).deriveKeyFromPassword(password: passphrase, nonce: utf8.encode(_salt));

  Future<List<int>> seal(String plaintext) async {
    final key = await _key();
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(plaintext),
      secretKey: key,
    );
    return [...box.nonce, ...box.cipherText, ...box.mac.bytes];
  }

  Future<String> open(List<int> bytes) async {
    const nonceLength = 12;
    const macLength = 16;
    if (bytes.length < nonceLength + macLength) {
      throw const FormatException('delta feed 已损坏或不是有效的加密文档。');
    }
    final box = SecretBox(
      bytes.sublist(nonceLength, bytes.length - macLength),
      nonce: bytes.sublist(0, nonceLength),
      mac: Mac(bytes.sublist(bytes.length - macLength)),
    );
    final key = await _key();
    final clear = await AesGcm.with256bits().decrypt(box, secretKey: key);
    return utf8.decode(clear);
  }
}
