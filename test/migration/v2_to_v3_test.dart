// 数据库迁移测试：v2 → v3 attachments 新增 asset_id 列，历史数据保留。

import 'dart:io';

import 'package:cardory/data/db/app_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// v2 的 assets 表 DDL（attachments.asset_id 外键引用它，夹具需一并提供建表）。
const _v2AssetsDdl = '''
CREATE TABLE IF NOT EXISTS "assets" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "project_id" TEXT NULL,
  "task_id" TEXT NULL,
  "type" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "uri_or_path" TEXT NOT NULL DEFAULT '',
  "note" TEXT NOT NULL DEFAULT '',
  "tags_json" TEXT NOT NULL DEFAULT '[]',
  "metadata_json" TEXT NOT NULL DEFAULT '{}',
  "is_local_only" INTEGER NOT NULL DEFAULT 0,
  "sensitive_json" TEXT NULL,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL,
  "deleted_at" INTEGER NULL
);
''';

/// v2 的 attachments 表 DDL（与 v3 中该表定义一致，仅缺 asset_id 列）。
const _v2AttachmentsDdl = '''
CREATE TABLE IF NOT EXISTS "attachments" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "project_id" TEXT NULL,
  "task_id" TEXT NULL,
  "file_name" TEXT NOT NULL,
  "storage_key" TEXT NOT NULL,
  "size_bytes" INTEGER NOT NULL,
  "sha256" TEXT NOT NULL,
  "mime_type" TEXT NOT NULL DEFAULT '',
  "kind" TEXT NOT NULL,
  "note" TEXT NOT NULL DEFAULT '',
  "is_local_only" INTEGER NOT NULL DEFAULT 0,
  "encryption_key" TEXT NOT NULL DEFAULT '',
  "category_ids_json" TEXT NOT NULL DEFAULT '[]',
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL,
  "deleted_at" INTEGER NULL
);
''';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cardory-migration');
    dbFile = File('${tempDir.path}/cardory-v2.db');
    final raw = sqlite3.open(dbFile.path);
    raw.execute("PRAGMA key = 'test-key'");
    raw.execute(_v2AssetsDdl);
    raw.execute(
      "INSERT INTO assets (id, type, title, is_local_only, created_at, "
      "updated_at) VALUES ('asset-1', 'software', 'Nginx', 0, 1000, 1000)",
    );
    raw.execute(_v2AttachmentsDdl);
    raw.execute(
      "INSERT INTO attachments (id, file_name, storage_key, size_bytes, "
      "sha256, kind, is_local_only, encryption_key, category_ids_json, "
      "created_at, updated_at) "
      "VALUES ('att-1', '发票.pdf', 'att-1-abc.cardory-attachment', 1024, "
      "'deadbeef', 'document', 0, '', '[]', 1000, 1000)",
    );
    raw.execute('PRAGMA user_version = 2');
    raw.close();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows 下文件句柄释放可能有延迟，尽力清理。
    }
  });

  test('打开 v2 库自动迁移到 v3：asset_id 列存在，历史数据保留', () async {
    final db = AppDatabase.encrypted(dbFile, key: 'test-key');
    addTearDown(db.close);

    final row = await (db.select(
      db.attachments,
    )..where((r) => r.id.equals('att-1'))).getSingle();
    expect(row.fileName, '发票.pdf');
    expect(row.assetId, isNull);

    // 新列可写。
    await (db.update(db.attachments)..where((r) => r.id.equals('att-1'))).write(
      AttachmentsCompanion(assetId: const Value('asset-1')),
    );
    final updated = await (db.select(
      db.attachments,
    )..where((r) => r.id.equals('att-1'))).getSingle();
    expect(updated.assetId, 'asset-1');
  });
}
