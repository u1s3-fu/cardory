import 'dart:convert';

import 'package:cardory/data/cardory_container_codec.dart';
import 'package:cardory/domain/cardory_container.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CardoryContainerCodec codec;

  setUp(() {
    var nextByte = 0;
    codec = CardoryContainerCodec(
      passwordIterations: 100000,
      randomBytes: (length) =>
          List<int>.generate(length, (_) => nextByte++ & 0xff, growable: false),
    );
  });

  test('creates an AES-256-GCM container with a password key slot', () async {
    final creation = await codec.create(
      plaintext: utf8.encode('Cardory 加密数据'),
      password: 'correct horse battery staple',
    );

    final info = codec.inspect(creation.bytes);

    expect(CardoryContainerCodec.extension, '.cardory');
    expect(info.version, CardoryContainerCodec.currentVersion);
    expect(info.cipher, CardoryContainerCodec.cipherName);
    expect(info.payloadLength, utf8.encode('Cardory 加密数据').length);
    expect(info.keySlots.map((slot) => slot.type), [
      CardoryKeySlotType.password,
    ]);
    expect(
      utf8.decode(creation.bytes, allowMalformed: true),
      isNot(contains('Cardory 加密数据')),
    );
  });

  test('opens the payload through the password slot', () async {
    final plaintext = utf8.encode('通过密码恢复');
    final creation = await codec.create(
      plaintext: plaintext,
      password: 'strong password',
    );

    expect(
      await codec.openWithPassword(creation.bytes, 'strong password'),
      plaintext,
    );
  });

  test('round-trips CardoryData through typed helpers', () async {
    final data = CardoryData.seed();
    final creation = await codec.createFromData(
      data: data,
      password: 'typed helper password',
    );

    final withPassword = await codec.openDataWithPassword(
      creation.bytes,
      'typed helper password',
    );

    expect(withPassword.toJson(), data.toJson());
  });

  test('rejects an incorrect password', () async {
    final creation = await codec.create(
      plaintext: [1, 2, 3],
      password: 'correct password',
    );

    await expectLater(
      codec.openWithPassword(creation.bytes, 'incorrect password'),
      throwsA(
        isA<CardoryContainerException>().having(
          (error) => error.error,
          'error',
          CardoryContainerError.invalidCredential,
        ),
      ),
    );
  });

  test('detects ciphertext and protected-header tampering', () async {
    final creation = await codec.create(
      plaintext: utf8.encode('authenticated payload'),
      password: 'tamper password',
    );
    final ciphertextTampered = List<int>.from(creation.bytes);
    ciphertextTampered[ciphertextTampered.length - 1] ^= 1;
    final headerTampered = List<int>.from(creation.bytes);
    final passwordMarker = utf8.encode('password');
    final markerIndex = _indexOf(headerTampered, passwordMarker);
    expect(markerIndex, greaterThan(0));
    headerTampered[markerIndex] = 'P'.codeUnitAt(0);

    await expectLater(
      codec.openWithPassword(ciphertextTampered, 'tamper password'),
      throwsA(isA<CardoryContainerException>()),
    );
    await expectLater(
      codec.openWithPassword(headerTampered, 'tamper password'),
      throwsA(isA<CardoryContainerException>()),
    );
  });

  test('changes password and re-encrypts with the new password', () async {
    final plaintext = utf8.encode('密码轮换正文');
    final creation = await codec.create(
      plaintext: plaintext,
      password: 'current password',
    );

    final changed = await codec.changePassword(
      creation.bytes,
      currentPassword: 'current password',
      newPassword: 'replacement password',
    );

    expect(
      await codec.openWithPassword(changed, 'replacement password'),
      plaintext,
    );
    await expectLater(
      codec.openWithPassword(changed, 'current password'),
      throwsA(isA<CardoryContainerException>()),
    );
  });

  test(
    'rejects malformed containers, versions and passwords',
    () async {
      expect(
        () => codec.create(plaintext: const [], password: ''),
        throwsArgumentError,
      );
      expect(
        () => CardoryContainerCodec(passwordIterations: 99999),
        throwsArgumentError,
      );
      expect(
        () => codec.inspect(utf8.encode('not a cardory container')),
        throwsA(
          isA<CardoryContainerException>().having(
            (error) => error.error,
            'error',
            CardoryContainerError.invalidFormat,
          ),
        ),
      );

      final creation = await codec.create(
        plaintext: const [],
        password: 'version password',
      );
      final unsupported = List<int>.from(creation.bytes)..[8] = 2;
      expect(
        () => codec.inspect(unsupported),
        throwsA(
          isA<CardoryContainerException>().having(
            (error) => error.error,
            'error',
            CardoryContainerError.unsupportedVersion,
          ),
        ),
      );
    },
  );
}

int _indexOf(List<int> bytes, List<int> pattern) {
  for (var index = 0; index <= bytes.length - pattern.length; index++) {
    var matches = true;
    for (var offset = 0; offset < pattern.length; offset++) {
      if (bytes[index + offset] != pattern[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return index;
  }
  return -1;
}
