import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

/// SQLCipher-backed local database. All timestamps are UTC Unix milliseconds.
@DriftDatabase(
  tables: [
    Projects,
    ProjectProgressEntries,
    Tasks,
    Assets,
    AssetTags,
    AttachmentCategories,
    Attachments,
    TimeEntries,
    PomodoroSessions,
    TaskDependencies,
    Settings,
    SyncChanges,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Opens a persisted SQLCipher database. Callers own the key lifecycle and
  /// must close this instance when the vault locks.
  factory AppDatabase.encrypted(File file, {required String key}) =>
      AppDatabase(_encryptedExecutor(file, key));

  /// Test-only executor. It exercises the schema but has no persisted file.
  factory AppDatabase.inMemory({String key = 'test-key'}) =>
      AppDatabase(NativeDatabase.memory(setup: _cipherSetup(key)));

  static QueryExecutor _encryptedExecutor(File file, String key) =>
      NativeDatabase(file, setup: _cipherSetup(key));

  static DatabaseSetup _cipherSetup(String key) {
    if (key.isEmpty) {
      throw ArgumentError.value(
        key,
        'key',
        'SQLCipher database key is required',
      );
    }
    final escaped = key.replaceAll("'", "''");
    return (database) {
      database.execute("PRAGMA key = '$escaped'");
      database.execute('PRAGMA foreign_keys = ON');
    };
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      // 逐版本推进迁移：每个 schemaVersion 步进对应 _upgradeFrom 的一个 case。
      for (var version = from; version < to; version++) {
        await _upgradeFrom(migrator, version);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// 从 [from] 版本迁移到下一个版本。
  ///
  /// schemaVersion 当前为 1（首个 SQLCipher 运行时版本）。未来发布 v2 时，
  /// 在此为 `case 1` 增加真实 DDL（如新表/新列 + 数据回填），并在迁移测试
  /// 中覆盖 from=1→2 的完整路径；在此之前拒绝静默破库，明确失败。
  static Future<void> _upgradeFrom(Migrator migrator, int from) async {
    switch (from) {
      case 1:
        throw StateError(
          '尚未定义数据库 v1 → v2 的迁移步骤；升级 v2 前必须在 '
          '_upgradeFrom 中实现 case 1。',
        );
      default:
        throw StateError('未知的数据库版本来源：$from');
    }
  }
}

class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get color => text().nullable()();
  TextColumn get status => text()();
  TextColumn get priority => text()();
  IntColumn get startAt => integer().nullable()();
  IntColumn get dueAt => integer().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  RealColumn get currentProgress => real().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ProjectProgressEntries extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id)();
  RealColumn get progress => real()();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get recordedAt => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().nullable().references(Projects, #id)();
  TextColumn get parentTaskId => text().nullable().references(Tasks, #id)();
  TextColumn get title => text()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get status => text()();
  TextColumn get priority => text()();
  IntColumn get startAt => integer().nullable()();
  IntColumn get dueAt => integer().nullable()();
  IntColumn get estimateMinutes => integer().nullable()();
  IntColumn get completedAt => integer().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().nullable().references(Projects, #id)();
  TextColumn get taskId => text().nullable().references(Tasks, #id)();
  TextColumn get type => text()();
  TextColumn get title => text()();
  TextColumn get uriOrPath => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();
  BoolColumn get isLocalOnly => boolean().withDefault(const Constant(false))();

  /// SQLCipher protects this column at rest; do not include it in sync payloads.
  TextColumn get sensitiveJson => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AssetTags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AttachmentCategories extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get name => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().nullable().references(Projects, #id)();
  TextColumn get taskId => text().nullable().references(Tasks, #id)();
  TextColumn get fileName => text()();
  TextColumn get storageKey => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get sha256 => text()();
  TextColumn get mimeType => text().withDefault(const Constant(''))();
  TextColumn get kind => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  BoolColumn get isLocalOnly => boolean().withDefault(const Constant(false))();

  /// The attachment content key is encrypted by the existing Cardory vault.
  TextColumn get encryptionKey => text().withDefault(const Constant(''))();
  TextColumn get categoryIdsJson => text().withDefault(const Constant('[]'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TimeEntries extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().nullable().references(Projects, #id)();
  TextColumn get taskId => text().nullable().references(Tasks, #id)();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer().nullable()();
  IntColumn get durationSeconds => integer()();
  TextColumn get source => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PomodoroSessions extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().nullable().references(Projects, #id)();
  TextColumn get taskId => text().nullable().references(Tasks, #id)();
  TextColumn get mode => text()();
  IntColumn get plannedSeconds => integer()();
  IntColumn get actualSeconds => integer().nullable()();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class TaskDependencies extends Table {
  TextColumn get id => text()();
  @ReferenceName('predecessorDependencies')
  TextColumn get predecessorTaskId => text().references(Tasks, #id)();
  @ReferenceName('successorDependencies')
  TextColumn get successorTaskId => text().references(Tasks, #id)();
  TextColumn get type =>
      text().withDefault(const Constant('finish_to_start'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {predecessorTaskId, successorTaskId, type},
  ];
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class SyncChanges extends Table {
  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text().withDefault(const Constant('{}'))();
  TextColumn get baseRevision => text().nullable()();
  IntColumn get createdAt => integer()();
  TextColumn get deviceId => text()();
  IntColumn get acknowledgedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
