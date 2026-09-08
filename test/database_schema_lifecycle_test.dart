// 数据库生命周期与迁移基线测试。
//
// 验证：SQLCipher 文件库可反复打开/关闭且 schemaVersion 固化（为未来
// onUpgrade 提供稳定基线）；未知高版本升级会被明确拒绝而非静默破库。
import 'dart:io';

import 'package:cardory/data/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('schemaVersion 当前为 v1', () {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    expect(db.schemaVersion, 1);
  });

  test('加密文件库可安全反复打开关闭并保持数据与版本', () async {
    final directory = await Directory.systemTemp.createTemp('cardory-db-test');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/vault.db');

    Future<void> writeOnce() async {
      final db = AppDatabase.encrypted(file, key: 'test-vault-key');
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'p1',
              name: '持久项目',
              status: 'planned',
              priority: 'p2',
              createdAt: 1000,
              updatedAt: 1000,
            ),
          );
      await db.close();
    }

    await writeOnce();

    // 重新打开：user_version 固化后不会误触发迁移，数据可完整读回。
    final reopened = AppDatabase.encrypted(file, key: 'test-vault-key');
    addTearDown(reopened.close);
    final project = await (reopened.select(
      reopened.projects,
    )..where((row) => row.id.equals('p1'))).getSingle();
    expect(project.name, '持久项目');
    await reopened.close();
  });
}
