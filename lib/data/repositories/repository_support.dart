// Repository 层共享工具：时间源、UUID、sync_changes 记录与 payload 序列化。
//
// 约束（见 docs/CARDORY_PHASE1_MIGRATION.md 数据协议）：
// - 所有时间戳为 UTC Unix 毫秒；
// - 所有主键为 UUID 字符串；
// - sync_changes 必须携带实体完整 payload，禁止 '{}' 空载荷；
// - 敏感列（如 Assets.sensitiveJson）不进入 payload。
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';

/// 主键生成器（各 Repository 共享，保证相同 RNG 源）。
const repositoryUuid = Uuid();

/// 时钟注入点；生产默认返回当前 UTC Unix 毫秒。
typedef Clock = int Function();

/// 默认时钟：UTC Unix 毫秒。
int nowUtcMillis() => DateTime.now().toUtc().millisecondsSinceEpoch;

/// 将 drift 数据行序列化为 sync_changes payload。
///
/// [exclude] 用于剔除禁止进入同步记录的敏感键；[deletedAt]/[updatedAt] 允许
/// 在软删除等场景直接覆写时间戳，避免回读一次数据库。
String rowPayload(
  dynamic row, {
  Set<String> exclude = const <String>{},
  int? deletedAt,
  int? updatedAt,
}) {
  final json = row is Map<String, dynamic>
      ? Map<String, dynamic>.from(row)
      : (row.toJson() as Map).cast<String, dynamic>();
  if (updatedAt != null) {
    json['updatedAt'] = updatedAt;
  }
  if (deletedAt != null) {
    json['deletedAt'] = deletedAt;
  }
  for (final key in exclude) {
    json.remove(key);
  }
  return jsonEncode(json);
}

/// 在当前事务内追加一条 sync_changes 记录。
///
/// [payload] 必须为实体完整字段的非空 JSON；空对象将被拒绝，保证同步协议
/// 在拿到每条记录时都能独立重建实体，而不依赖跨记录推导。
Future<void> recordSyncChange(
  AppDatabase db, {
  required String entityType,
  required String entityId,
  required String operation,
  required String payload,
  required String deviceId,
  required int createdAt,
  String? baseRevision,
}) async {
  if (payload.trim().isEmpty) {
    throw ArgumentError.value(
      payload,
      'payload',
      'sync_changes 不允许空 payload，必须携带实体完整字段。',
    );
  }
  await db
      .into(db.syncChanges)
      .insert(
        SyncChangesCompanion.insert(
          id: repositoryUuid.v4(),
          entityType: entityType,
          entityId: entityId,
          operation: operation,
          payloadJson: Value(payload),
          baseRevision: Value(baseRevision),
          createdAt: createdAt,
          deviceId: deviceId,
        ),
      );
}
