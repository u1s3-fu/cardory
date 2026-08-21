import 'dart:convert';
import 'dart:io';

import 'package:cardory/data/cardory_container_codec.dart';
import 'package:cardory/data/cardory_store.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late CardoryStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('cardory-store-test-');
    store = _store(directory);
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'creates an encrypted empty document and unlocks with password',
    () async {
      expect(await store.accessState(), CardoryAccessState.setupRequired);
      final initial = await store.setup('test password');
      final reloaded = await _store(
        directory,
      ).unlockWithPassword('test password');

      expect(initial.data.projects, isEmpty);
      expect(initial.data.todos, isEmpty);
      expect(reloaded.data.projects, isEmpty);
      expect(reloaded.data.todos, isEmpty);
      expect(File(initial.path).existsSync(), isTrue);
      expect(initial.path, endsWith('.cardory'));
      expect(
        utf8.decode(
          await File(initial.path).readAsBytes(),
          allowMalformed: true,
        ),
        isNot(contains('Cardory 桌面端')),
      );
    },
  );

  test('unlocks and keeps saving through the password', () async {
    final initial = await store.setup('test password');
    final unlockedStore = _store(directory);
    final unlocked = await unlockedStore.unlockWithPassword('test password');
    final updated = CardoryData(
      projects: [_testProject('更新后的项目')],
      todos: const [],
    );

    await unlockedStore.save(updated, unlocked.settings);

    final backup = File('${initial.path}.bak');
    expect(await backup.exists(), isTrue);
    final reloaded = await _store(
      directory,
    ).unlockWithPassword('test password');
    expect(reloaded.data.projects.first.title, '更新后的项目');
    expect(
      utf8.decode(await File(initial.path).readAsBytes(), allowMalformed: true),
      isNot(contains('更新后的项目')),
    );
  });

  test('recovers a corrupt document from its backup', () async {
    final initial = await store.setup('test password');
    final updated = CardoryData(
      projects: [_testProject('更新后的项目')],
      todos: const [],
    );
    await store.save(updated, initial.settings);
    await File(initial.path).writeAsBytes([1, 2, 3], flush: true);

    final recovered = await _store(
      directory,
    ).unlockWithPassword('test password');

    expect(recovered.recoveredFromBackup, isTrue);
    expect(recovered.data.projects, isEmpty);
    expect(recovered.data.todos, isEmpty);
    expect(await File(initial.path).readAsBytes(), hasLength(greaterThan(3)));
  });

  test('serializes concurrent saves in invocation order', () async {
    await store.setup('test password');
    final first = CardoryData(
      projects: [_testProject('第一次保存')],
      todos: const [],
    );
    final second = CardoryData(
      projects: [_testProject('第二次保存')],
      todos: const [],
    );

    await Future.wait([
      store.save(first, const AppSettings()),
      store.save(second, const AppSettings()),
    ]);

    final loaded = await _store(directory).unlockWithPassword('test password');
    expect(loaded.data.projects.single.title, '第二次保存');
  });

  test('rejects an incorrect password', () async {
    await store.setup('test password');
    await expectLater(
      _store(directory).unlockWithPassword('incorrect password'),
      throwsA(isA<CardoryStorageException>()),
    );
  });

  test('changes password atomically', () async {
    final initial = await store.setup('old password');

    await store.changePassword('old password', 'new password');

    expect(File('${initial.path}.bak').existsSync(), isTrue);
    await expectLater(
      _store(directory).unlockWithPassword('old password'),
      throwsA(isA<CardoryStorageException>()),
    );
    expect(
      (await _store(
        directory,
      ).unlockWithPassword('new password')).data.toJson(),
      initial.data.toJson(),
    );
  });

  test('restores a backup with the source password', () async {
    final sourceDirectory = await Directory.systemTemp.createTemp(
      'cardory-restore-source-',
    );
    addTearDown(() async {
      if (await sourceDirectory.exists()) {
        await sourceDirectory.delete(recursive: true);
      }
    });
    final source = _store(sourceDirectory);
    final sourceInitial = await source.setup('source password');
    final backupData = CardoryData(
      projects: [_testProject('备份项目')],
      todos: const [],
    );
    await source.save(backupData, sourceInitial.settings);
    final backup = await source.exportContainer();

    final restored = await store.restoreFromBackup(
      backup,
      'source password',
    );

    expect(restored.data.projects.single.title, '备份项目');
    expect(
      (await _store(
        directory,
      ).unlockWithPassword('source password')).data.projects.single.title,
      '备份项目',
    );
  });

  test(
    'keeps local data when the backup password is invalid',
    () async {
      final initial = await store.setup('local password');
      final original = await File(initial.path).readAsBytes();

      await expectLater(
        store.restoreFromBackup(original, 'incorrect password'),
        throwsA(isA<CardoryStorageException>()),
      );

      expect(await File(initial.path).readAsBytes(), original);
      expect(
        (await _store(
          directory,
        ).unlockWithPassword('local password')).data.toJson(),
        initial.data.toJson(),
      );
    },
  );

  test(
    'rejects a wrong current password without replacing the container',
    () async {
      await store.setup('correct password');
      final original = await store.exportContainer();

      await expectLater(
        store.changePassword('wrong password', 'new password'),
        throwsA(isA<CardoryStorageException>()),
      );

      expect(await store.exportContainer(), original);
    },
  );

  test('exports and imports a valid encrypted container', () async {
    final initial = await store.setup('test password');
    final sourceDirectory = await Directory.systemTemp.createTemp(
      'cardory-import-source-',
    );
    addTearDown(() async {
      if (await sourceDirectory.exists()) {
        await sourceDirectory.delete(recursive: true);
      }
    });
    final source = _store(sourceDirectory);
    final sourceInitial = await source.setup('test password');
    final remoteData = CardoryData(
      projects: [_testProject('远端项目')],
      todos: const [],
    );
    await source.save(remoteData, sourceInitial.settings);

    final remoteContainer = await source.exportContainer();
    final imported = await store.importContainer(
      remoteContainer,
      initial.settings,
    );

    expect(imported.projects.single.title, '远端项目');
    expect(await store.exportContainer(), remoteContainer);
    expect(
      (await _store(
        directory,
      ).unlockWithPassword('test password')).data.projects.single.title,
      '远端项目',
    );
  });

  test('rejects an invalid container without replacing local data', () async {
    final initial = await store.setup('test password');
    final original = await File(initial.path).readAsBytes();

    await expectLater(
      store.importContainer([1, 2, 3], initial.settings),
      throwsA(isA<CardoryStorageException>()),
    );

    expect(await File(initial.path).readAsBytes(), original);
    expect(await store.exportContainer(), original);
  });
}

CardoryStore _store(Directory directory) => CardoryStore(
  directoryProvider: () async => directory,
  codec: CardoryContainerCodec(passwordIterations: 100000),
);

ProjectData _testProject(String title) => ProjectData(
  id: 'project-${title.hashCode}',
  title: title,
  description: '测试项目',
  priority: ProjectPriority.p1,
  stage: ProjectStage.doing,
  progressEntries: const [],
);
