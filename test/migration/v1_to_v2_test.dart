// 数据库迁移测试：v1 → v2 新增里程碑表，历史数据保留。

import 'dart:io';

import 'package:cardory/data/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// v1 的 projects 表 DDL（与 v2 中该表定义一致，迁移不改既有列）。
const _v1ProjectsDdl = '''
CREATE TABLE IF NOT EXISTS "projects" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "name" TEXT NOT NULL,
  "description" TEXT NOT NULL DEFAULT '',
  "color" TEXT NULL,
  "status" TEXT NOT NULL,
  "priority" TEXT NOT NULL,
  "start_at" INTEGER NULL,
  "due_at" INTEGER NULL,
  "sort_order" INTEGER NOT NULL DEFAULT 0,
  "pinned" INTEGER NOT NULL DEFAULT 0,
  "current_progress" REAL NOT NULL DEFAULT 0,
  "created_at" INTEGER NOT NULL,
  "updated_at" INTEGER NOT NULL,
  "deleted_at" INTEGER NULL
);
''';

/// v1 的 attachments 表 DDL（与 v2 中该表定义一致，v3 才加 asset_id 列）。
const _v1AttachmentsDdl = '''
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
    dbFile = File('${tempDir.path}/cardory-v1.db');
    // 用 SQLCipher 构建一个 v1 库：仅 projects 表 + 一行种子数据。
    final raw = sqlite3.open(dbFile.path);
    raw.execute("PRAGMA key = 'test-key'");
    raw.execute(_v1ProjectsDdl);
    raw.execute(_v1AttachmentsDdl);
    raw.execute(
      "INSERT INTO projects (id, name, description, status, priority, "
      "sort_order, pinned, current_progress, created_at, updated_at) "
      "VALUES ('project-1', '迁移项目', '', 'planned', 'p2', 0, 0, 0, 1000, 1000)",
    );
    raw.execute('PRAGMA user_version = 1');
    raw.close();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows 下文件句柄释放可能有延迟，尽力清理。
    }
  });

  test('打开 v1 库自动迁移到 v2：里程碑表可写，历史数据保留', () async {
    final db = AppDatabase.encrypted(dbFile, key: 'test-key');
    addTearDown(db.close);

    // v1 库逐版本推进：经 v2（里程碑表）一直迁到当前版本。
    expect(db.schemaVersion, 3);

    // 历史数据在迁移后仍可读。
    final projects = await db.select(db.projects).get();
    expect(projects.single.id, 'project-1');

    // 里程碑表已创建：可插入并读回。
    await db
        .into(db.milestones)
        .insert(
          MilestonesCompanion.insert(
            id: 'milestone-1',
            projectId: 'project-1',
            title: '首个里程碑',
            dueAt: 1726272000000,
            createdAt: 2000,
            updatedAt: 2000,
          ),
        );
    final milestones = await db.select(db.milestones).get();
    expect(milestones.single.title, '首个里程碑');
    expect(milestones.single.completed, isFalse);
  });

  test('重复打开不再触发迁移（幂等）', () async {
    final first = AppDatabase.encrypted(dbFile, key: 'test-key');
    await first.select(first.projects).get();
    await first.close();

    final second = AppDatabase.encrypted(dbFile, key: 'test-key');
    addTearDown(second.close);
    final milestones = await second.select(second.milestones).get();
    expect(milestones, isEmpty);
  });
}
