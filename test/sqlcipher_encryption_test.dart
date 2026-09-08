import 'dart:io';

import 'package:cardory/data/db/app_database.dart';
import 'package:cardory/data/db/database_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'cardory-sqlcipher-test-',
    );
  });
  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('a SQLCipher file rejects a different key', () async {
    final file = File('${directory.path}${Platform.pathSeparator}cardory.db');
    final first = DatabaseSession();
    final opened = await first.open(file, key: 'correct session key');
    await opened
        .into(opened.settings)
        .insert(
          SettingsCompanion.insert(
            key: 'probe',
            value: 'protected',
            updatedAt: 1,
          ),
        );
    await first.close();

    final wrongKey = DatabaseSession();
    addTearDown(wrongKey.close);
    await expectLater(
      wrongKey.open(file, key: 'wrong session key'),
      throwsA(isA<Object>()),
    );
    expect(wrongKey.isOpen, isFalse);
  });
}
