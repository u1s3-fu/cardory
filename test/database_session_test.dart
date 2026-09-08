import 'dart:io';

import 'package:cardory/data/db/database_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session remains closed until an unlock-derived key opens it', () async {
    final session = DatabaseSession();
    addTearDown(session.close);

    expect(session.isOpen, isFalse);
    await expectLater(
      session.open(
        File('${Directory.systemTemp.path}/unused.cardory.db'),
        key: '',
      ),
      throwsArgumentError,
    );
    expect(session.isOpen, isFalse);
  });
}
