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
  });

  factory DeltaRecord.fromChange(db.SyncChange change) => DeltaRecord(
    changeId: change.id,
    entityType: change.entityType,
    entityId: change.entityId,
    operation: change.operation,
    payload: jsonDecode(change.payloadJson) as Map<String, dynamic>,
    deviceId: change.deviceId,
    createdAt: change.createdAt,
  );

  factory DeltaRecord.fromJson(Map<String, dynamic> json) => DeltaRecord(
    changeId: json['changeId'] as String,
    entityType: json['entityType'] as String,
    entityId: json['entityId'] as String,
    operation: json['operation'] as String,
    payload: (json['payload'] as Map).cast<String, dynamic>(),
    deviceId: json['deviceId'] as String,
    createdAt: json['createdAt'] as int,
  );

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
  const DeltaConflict({required this.record, required this.localUpdatedAt});

  final DeltaRecord record;
  final int localUpdatedAt;

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

  Future<DeltaApplyResult> apply(Iterable<DeltaRecord> records) async {
    var applied = 0;
    var skipped = 0;
    final conflicts = <DeltaConflict>[];
    for (final record in records) {
      if (record.deviceId == localDeviceId) {
        // 自己产生的记录：本地行就是权威状态，直接跳过。
        skipped++;
        continue;
      }
      final outcome = await _applyOne(record);
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
            ),
          );
      }
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
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.projects,
          fromJson: db.Project.fromJson,
        );
      case 'task':
        return _applyRow(
          record,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.tasks,
          fromJson: db.Task.fromJson,
        );
      case 'asset':
        // 资产的敏感字段（账号/密码）不出同步通道：覆盖时保留本地列。
        return _applyRow<db.Asset>(
          record,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.assets,
          fromJson: db.Asset.fromJson,
          preserve: (current, incoming) =>
              incoming.copyWith(sensitiveJson: Value(current.sensitiveJson)),
        );
      case 'asset_tag':
        return _applyRow(
          record,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.assetTags,
          fromJson: db.AssetTag.fromJson,
        );
      case 'attachment':
        return _applyRow(
          record,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.attachments,
          fromJson: db.Attachment.fromJson,
        );
      case 'attachment_category':
        return _applyRow(
          record,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.attachmentCategories,
          fromJson: db.AttachmentCategory.fromJson,
        );
      case 'project_progress_entry':
        return _applyRow(
          record,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.projectProgressEntries,
          fromJson: db.ProjectProgressEntry.fromJson,
        );
      case 'time_entry':
        return _applyRow(
          record,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.timeEntries,
          fromJson: db.TimeEntry.fromJson,
        );
      case 'pomodoro_session':
        return _applyRow(
          record,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.pomodoroSessions,
          fromJson: db.PomodoroSession.fromJson,
        );
      case 'task_dependency':
        return _applyRow(
          record,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.taskDependencies,
          fromJson: db.TaskDependency.fromJson,
        );
      case 'milestone':
        return _applyRow(
          record,
          incomingUpdatedAt: incomingUpdatedAt,
          table: _db.milestones,
          fromJson: db.Milestone.fromJson,
        );
      default:
        return _ApplyOutcome.skipped;
    }
  }

  /// 通用行级 LWW：读当前行 → 比较 updatedAt → 写入或跳过。
  ///
  /// [preserve] 允许在覆盖前把本地独有列（如资产 sensitiveJson，不出同步
  /// 通道）从当前行合并进远端行。
  Future<_ApplyOutcome> _applyRow<T extends DataClass>(
    DeltaRecord record, {
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
    final incoming = fromJson(record.payload);
    final existing =
        await (table.select()..where((_) => idColumn.equals(record.entityId)))
            .getSingleOrNull();
    if (existing == null) {
      if (record.payload['deletedAt'] != null) {
        // 远端删除一个本地不存在的行：无需操作（tombstone 重放幂等）。
        return _ApplyOutcome.skipped;
      }
      await _db.into(table).insert(incoming as Insertable<dynamic>);
      return _ApplyOutcome.applied;
    }
    final currentUpdatedAt =
        (existing.toJson()['updatedAt'] as num?)?.toInt() ?? 0;
    if (incomingUpdatedAt < currentUpdatedAt) {
      return _ApplyOutcome.skipped;
    }
    if (incomingUpdatedAt == currentUpdatedAt) {
      if (jsonEncode(incoming.toJson()) == jsonEncode(existing.toJson())) {
        return _ApplyOutcome.skipped;
      }
      return _ApplyOutcome.conflict;
    }
    final target = preserve?.call(existing, incoming) ?? incoming;
    await (_db.update(table)..where((_) => idColumn.equals(record.entityId)))
        .write(target as Insertable<dynamic>);
    return _ApplyOutcome.applied;
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
