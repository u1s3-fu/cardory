/// 加密容器的序列化与反序列化编解码器。
///
/// 负责将 [CardoryContainer] 编码为加密的字节流写入磁盘，以及从磁盘读取密文
/// 并解码恢复为容器对象。

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../domain/cardory_container.dart';
import '../domain/cardory_models.dart';

typedef CardoryRandomBytes = List<int> Function(int length);

class CardoryContainerCodec {
  CardoryContainerCodec({
    int passwordIterations = 210000,
    CardoryRandomBytes? randomBytes,
  }) : _passwordIterations = passwordIterations,
       _randomBytes = randomBytes ?? _secureRandomBytes {
    if (passwordIterations < 100000) {
      throw ArgumentError.value(
        passwordIterations,
        'passwordIterations',
        '至少需要 100000 次迭代',
      );
    }
  }

  static const extension = '.cardory';
  static const currentVersion = 1;
  static const cipherName = 'AES-256-GCM';
  static const _passwordKdfName = 'PBKDF2-HMAC-SHA256';
  static const _recoveryKdfName = 'RAW-256';
  static const _prefixLength = 13;
  static const _maxHeaderLength = 1024 * 1024;
  static const _magic = <int>[67, 65, 82, 68, 79, 82, 89, 0];

  final int _passwordIterations;
  final CardoryRandomBytes _randomBytes;
  final AesGcm _aes = AesGcm.with256bits();

  Future<CardoryContainerCreation> create({
    required List<int> plaintext,
    required String password,
    String? recoveryKey,
  }) async {
    _validatePassword(password);
    final dataKeyBytes = _randomBytes(32);
    final dataKey = SecretKey(dataKeyBytes);
    final resolvedRecoveryKey =
        recoveryKey ?? _encodeRecoveryKey(_randomBytes(32));
    final recoveryKeyBytes = _decodeRecoveryKey(resolvedRecoveryKey);
    final slots = <Map<String, dynamic>>[
      await _createPasswordSlot(dataKeyBytes, password),
      await _createRecoverySlot(dataKeyBytes, recoveryKeyBytes),
    ];
    final payloadNonce = _randomBytes(12);
    final protectedHeader = <String, dynamic>{
      'cipher': cipherName,
      'payloadNonce': _encode(payloadNonce),
      'keySlots': slots,
    };
    final aad = _canonicalJson(protectedHeader);
    final payloadBox = await _aes.encrypt(
      plaintext,
      secretKey: dataKey,
      nonce: payloadNonce,
      aad: aad,
    );
    final header = <String, dynamic>{
      ...protectedHeader,
      'payloadMac': _encode(payloadBox.mac.bytes),
    };
    final headerBytes = _canonicalJson(header);
    final output = BytesBuilder(copy: false)
      ..add(_magic)
      ..addByte(currentVersion)
      ..add(_uint32(headerBytes.length))
      ..add(headerBytes)
      ..add(payloadBox.cipherText);
    return CardoryContainerCreation(
      bytes: output.takeBytes(),
      recoveryKey: resolvedRecoveryKey,
    );
  }

  Future<CardoryContainerCreation> createFromData({
    required CardoryData data,
    required String password,
    String? recoveryKey,
  }) => create(
    plaintext: utf8.encode(jsonEncode(data.toJson())),
    password: password,
    recoveryKey: recoveryKey,
  );

  Future<List<int>> openWithPassword(
    List<int> container,
    String password,
  ) async {
    _validatePassword(password);
    final parsed = _parse(container);
    final slot = _slot(parsed.header, CardoryKeySlotType.password);
    try {
      final salt = _requiredBytes(slot, 'salt', expectedLength: 16);
      final iterations = _requiredInt(slot, 'iterations');
      if (iterations < 100000 || iterations > 10000000) {
        throw const FormatException('密码派生参数无效');
      }
      final wrappingKey = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
      final dataKey = await _unwrapKey(slot, wrappingKey);
      return await _decryptPayload(parsed, dataKey);
    } on CardoryContainerException {
      rethrow;
    } on SecretBoxAuthenticationError catch (error) {
      throw CardoryContainerException(
        CardoryContainerError.invalidCredential,
        '密码不正确或容器已损坏。',
        error,
      );
    } on FormatException catch (error) {
      throw CardoryContainerException(
        CardoryContainerError.invalidFormat,
        '容器密钥槽格式无效。',
        error,
      );
    }
  }

  Future<List<int>> openWithRecoveryKey(
    List<int> container,
    String recoveryKey,
  ) async {
    final parsed = _parse(container);
    final slot = _slot(parsed.header, CardoryKeySlotType.recovery);
    final recoveryKeyBytes = _decodeRecoveryKey(recoveryKey);
    try {
      final dataKey = await _unwrapKey(slot, SecretKey(recoveryKeyBytes));
      return await _decryptPayload(parsed, dataKey);
    } on CardoryContainerException {
      rethrow;
    } on SecretBoxAuthenticationError catch (error) {
      throw CardoryContainerException(
        CardoryContainerError.invalidCredential,
        '恢复密钥不正确或容器已损坏。',
        error,
      );
    } on FormatException catch (error) {
      throw CardoryContainerException(
        CardoryContainerError.invalidFormat,
        '容器密钥槽格式无效。',
        error,
      );
    }
  }

  Future<CardoryData> openDataWithPassword(
    List<int> container,
    String password,
  ) async => _decodeData(await openWithPassword(container, password));

  Future<CardoryData> openDataWithRecoveryKey(
    List<int> container,
    String recoveryKey,
  ) async => _decodeData(await openWithRecoveryKey(container, recoveryKey));

  Future<List<int>> updateDataWithPassword(
    List<int> container,
    CardoryData data,
    String password,
  ) async {
    _validatePassword(password);
    final parsed = _parse(container);
    final slot = _slot(parsed.header, CardoryKeySlotType.password);
    try {
      final salt = _requiredBytes(slot, 'salt', expectedLength: 16);
      final iterations = _requiredInt(slot, 'iterations');
      final wrappingKey = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
      return _replacePayload(
        parsed,
        utf8.encode(jsonEncode(data.toJson())),
        await _unwrapKey(slot, wrappingKey),
      );
    } on SecretBoxAuthenticationError catch (error) {
      throw CardoryContainerException(
        CardoryContainerError.invalidCredential,
        '密码不正确或容器已损坏。',
        error,
      );
    }
  }

  Future<List<int>> updateDataWithRecoveryKey(
    List<int> container,
    CardoryData data,
    String recoveryKey,
  ) async {
    final parsed = _parse(container);
    final slot = _slot(parsed.header, CardoryKeySlotType.recovery);
    try {
      return _replacePayload(
        parsed,
        utf8.encode(jsonEncode(data.toJson())),
        await _unwrapKey(slot, SecretKey(_decodeRecoveryKey(recoveryKey))),
      );
    } on SecretBoxAuthenticationError catch (error) {
      throw CardoryContainerException(
        CardoryContainerError.invalidCredential,
        '恢复密钥不正确或容器已损坏。',
        error,
      );
    }
  }

  Future<List<int>> replaceWithPassword(
    List<int> container,
    List<int> plaintext,
    String password,
  ) async {
    _validatePassword(password);
    final parsed = _parse(container);
    final dataKey = await _dataKeyWithPassword(parsed, password);
    return _replacePayload(parsed, plaintext, dataKey);
  }

  Future<List<int>> replaceWithRecoveryKey(
    List<int> container,
    List<int> plaintext,
    String recoveryKey,
  ) async {
    final parsed = _parse(container);
    final dataKey = await _dataKeyWithRecoveryKey(parsed, recoveryKey);
    return _replacePayload(parsed, plaintext, dataKey);
  }

  Future<List<int>> changePassword(
    List<int> container, {
    required String currentPassword,
    required String newPassword,
  }) async {
    _validatePassword(newPassword);
    final parsed = _parse(container);
    final dataKey = await _dataKeyWithPassword(parsed, currentPassword);
    final plaintext = await _decryptPayload(parsed, dataKey);
    final dataKeyBytes = await dataKey.extractBytes();
    final recoverySlot = Map<String, dynamic>.from(
      _slot(parsed.header, CardoryKeySlotType.recovery),
    );
    return _replacePayload(
      parsed,
      plaintext,
      dataKey,
      keySlots: [
        await _createPasswordSlot(dataKeyBytes, newPassword),
        recoverySlot,
      ],
    );
  }

  Future<List<int>> changePasswordWithRecoveryKey(
    List<int> container, {
    required String recoveryKey,
    required String newPassword,
  }) async {
    _validatePassword(newPassword);
    final parsed = _parse(container);
    final dataKey = await _dataKeyWithRecoveryKey(parsed, recoveryKey);
    final plaintext = await _decryptPayload(parsed, dataKey);
    final dataKeyBytes = await dataKey.extractBytes();
    final recoverySlot = Map<String, dynamic>.from(
      _slot(parsed.header, CardoryKeySlotType.recovery),
    );
    return _replacePayload(
      parsed,
      plaintext,
      dataKey,
      keySlots: [
        await _createPasswordSlot(dataKeyBytes, newPassword),
        recoverySlot,
      ],
    );
  }

  CardoryContainerInfo inspect(List<int> container) {
    final parsed = _parse(container);
    final slots = _requiredList(parsed.header, 'keySlots')
        .map((value) {
          if (value is! Map<String, dynamic>) throw const FormatException();
          final type = _parseSlotType(value['type']);
          return CardoryKeySlotInfo(
            id: _requiredString(value, 'id'),
            type: type,
            algorithm: _requiredString(value, 'kdf'),
          );
        })
        .toList(growable: false);
    return CardoryContainerInfo(
      version: currentVersion,
      cipher: _requiredString(parsed.header, 'cipher'),
      keySlots: slots,
      payloadLength: parsed.cipherText.length,
    );
  }

  Future<Map<String, dynamic>> _createPasswordSlot(
    List<int> dataKey,
    String password,
  ) async {
    final salt = _randomBytes(16);
    final wrappingKey = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _passwordIterations,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    return _createSlot(
      type: CardoryKeySlotType.password,
      kdf: _passwordKdfName,
      wrappingKey: wrappingKey,
      dataKey: dataKey,
      extra: {'salt': _encode(salt), 'iterations': _passwordIterations},
    );
  }

  Future<Map<String, dynamic>> _createRecoverySlot(
    List<int> dataKey,
    List<int> recoveryKey,
  ) => _createSlot(
    type: CardoryKeySlotType.recovery,
    kdf: _recoveryKdfName,
    wrappingKey: SecretKey(recoveryKey),
    dataKey: dataKey,
  );

  Future<Map<String, dynamic>> _createSlot({
    required CardoryKeySlotType type,
    required String kdf,
    required SecretKey wrappingKey,
    required List<int> dataKey,
    Map<String, dynamic> extra = const {},
  }) async {
    final id = _encode(_randomBytes(16));
    final nonce = _randomBytes(12);
    final aad = utf8.encode('Cardory/$currentVersion/${type.name}/$id');
    final box = await _aes.encrypt(
      dataKey,
      secretKey: wrappingKey,
      nonce: nonce,
      aad: aad,
    );
    return <String, dynamic>{
      'id': id,
      'type': type.name,
      'kdf': kdf,
      ...extra,
      'nonce': _encode(nonce),
      'wrappedKey': _encode(box.cipherText),
      'mac': _encode(box.mac.bytes),
    };
  }

  Future<SecretKey> _unwrapKey(
    Map<String, dynamic> slot,
    SecretKey wrappingKey,
  ) async {
    final id = _requiredString(slot, 'id');
    final type = _parseSlotType(slot['type']);
    final nonce = _requiredBytes(slot, 'nonce', expectedLength: 12);
    final wrappedKey = _requiredBytes(slot, 'wrappedKey', expectedLength: 32);
    final mac = _requiredBytes(slot, 'mac', expectedLength: 16);
    final aad = utf8.encode('Cardory/$currentVersion/${type.name}/$id');
    final bytes = await _aes.decrypt(
      SecretBox(wrappedKey, nonce: nonce, mac: Mac(mac)),
      secretKey: wrappingKey,
      aad: aad,
    );
    if (bytes.length != 32) throw const FormatException('数据密钥长度无效');
    return SecretKey(bytes);
  }

  Future<SecretKey> _dataKeyWithPassword(
    _ParsedContainer parsed,
    String password,
  ) async {
    final slot = _slot(parsed.header, CardoryKeySlotType.password);
    try {
      final salt = _requiredBytes(slot, 'salt', expectedLength: 16);
      final iterations = _requiredInt(slot, 'iterations');
      if (iterations < 100000 || iterations > 10000000) {
        throw const FormatException('密码派生参数无效');
      }
      final wrappingKey = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
      return await _unwrapKey(slot, wrappingKey);
    } on CardoryContainerException {
      rethrow;
    } on SecretBoxAuthenticationError catch (error) {
      throw CardoryContainerException(
        CardoryContainerError.invalidCredential,
        '密码不正确或容器已损坏。',
        error,
      );
    } on FormatException catch (error) {
      throw CardoryContainerException(
        CardoryContainerError.invalidFormat,
        '容器密钥槽格式无效。',
        error,
      );
    }
  }

  Future<SecretKey> _dataKeyWithRecoveryKey(
    _ParsedContainer parsed,
    String recoveryKey,
  ) async {
    final slot = _slot(parsed.header, CardoryKeySlotType.recovery);
    final recoveryKeyBytes = _decodeRecoveryKey(recoveryKey);
    try {
      return await _unwrapKey(slot, SecretKey(recoveryKeyBytes));
    } on CardoryContainerException {
      rethrow;
    } on SecretBoxAuthenticationError catch (error) {
      throw CardoryContainerException(
        CardoryContainerError.invalidCredential,
        '恢复密钥不正确或容器已损坏。',
        error,
      );
    } on FormatException catch (error) {
      throw CardoryContainerException(
        CardoryContainerError.invalidFormat,
        '容器密钥槽格式无效。',
        error,
      );
    }
  }

  Future<List<int>> _replacePayload(
    _ParsedContainer parsed,
    List<int> plaintext,
    SecretKey dataKey, {
    List<Map<String, dynamic>>? keySlots,
  }) async {
    final protectedHeader = Map<String, dynamic>.from(parsed.header)
      ..remove('payloadMac')
      ..['payloadNonce'] = _encode(_randomBytes(12));
    if (keySlots != null) protectedHeader['keySlots'] = keySlots;
    final nonce = _requiredBytes(
      protectedHeader,
      'payloadNonce',
      expectedLength: 12,
    );
    final payloadBox = await _aes.encrypt(
      plaintext,
      secretKey: dataKey,
      nonce: nonce,
      aad: _canonicalJson(protectedHeader),
    );
    final header = <String, dynamic>{
      ...protectedHeader,
      'payloadMac': _encode(payloadBox.mac.bytes),
    };
    final headerBytes = _canonicalJson(header);
    return (BytesBuilder(copy: false)
          ..add(_magic)
          ..addByte(currentVersion)
          ..add(_uint32(headerBytes.length))
          ..add(headerBytes)
          ..add(payloadBox.cipherText))
        .takeBytes();
  }

  Future<List<int>> _decryptPayload(
    _ParsedContainer parsed,
    SecretKey dataKey,
  ) async {
    final protectedHeader = Map<String, dynamic>.from(parsed.header)
      ..remove('payloadMac');
    final nonce = _requiredBytes(
      parsed.header,
      'payloadNonce',
      expectedLength: 12,
    );
    final mac = _requiredBytes(parsed.header, 'payloadMac', expectedLength: 16);
    try {
      return await _aes.decrypt(
        SecretBox(parsed.cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: dataKey,
        aad: _canonicalJson(protectedHeader),
      );
    } on SecretBoxAuthenticationError catch (error) {
      throw CardoryContainerException(
        CardoryContainerError.invalidCredential,
        '凭据不正确或容器完整性校验失败。',
        error,
      );
    }
  }

  _ParsedContainer _parse(List<int> input) {
    try {
      if (input.length < _prefixLength ||
          !_sameBytes(input.sublist(0, _magic.length), _magic)) {
        throw const FormatException('容器标识无效');
      }
      final version = input[_magic.length];
      if (version != currentVersion) {
        throw CardoryContainerException(
          CardoryContainerError.unsupportedVersion,
          '不支持的 Cardory 容器版本：$version。',
        );
      }
      final prefix = ByteData.sublistView(Uint8List.fromList(input), 9, 13);
      final headerLength = prefix.getUint32(0, Endian.big);
      if (headerLength == 0 ||
          headerLength > _maxHeaderLength ||
          _prefixLength + headerLength > input.length) {
        throw const FormatException('容器头长度无效');
      }
      final headerValue = jsonDecode(
        utf8.decode(input.sublist(_prefixLength, _prefixLength + headerLength)),
      );
      if (headerValue is! Map<String, dynamic>) {
        throw const FormatException('容器头无效');
      }
      if (_requiredString(headerValue, 'cipher') != cipherName) {
        throw const FormatException('加密算法无效');
      }
      _requiredList(headerValue, 'keySlots');
      return _ParsedContainer(
        headerValue,
        input.sublist(_prefixLength + headerLength),
      );
    } on CardoryContainerException {
      rethrow;
    } on FormatException catch (error) {
      throw CardoryContainerException(
        CardoryContainerError.invalidFormat,
        '不是有效的 .cardory 容器。',
        error,
      );
    } on Object catch (error) {
      throw CardoryContainerException(
        CardoryContainerError.invalidFormat,
        '不是有效的 .cardory 容器。',
        error,
      );
    }
  }

  Map<String, dynamic> _slot(
    Map<String, dynamic> header,
    CardoryKeySlotType type,
  ) {
    for (final value in _requiredList(header, 'keySlots')) {
      if (value is Map<String, dynamic> && value['type'] == type.name) {
        return value;
      }
    }
    throw CardoryContainerException(
      CardoryContainerError.missingKeySlot,
      '容器中没有 ${type.name} 密钥槽。',
    );
  }

  CardoryData _decodeData(List<int> bytes) {
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic>) throw const FormatException();
      return CardoryData.fromJson(value);
    } on Object catch (error) {
      throw CardoryContainerException(
        CardoryContainerError.invalidFormat,
        '容器正文不是有效的 Cardory 数据。',
        error,
      );
    }
  }

  void _validatePassword(String password) {
    if (password.isEmpty) {
      throw ArgumentError.value(password, 'password', '密码不能为空');
    }
  }

  List<int> _decodeRecoveryKey(String value) {
    try {
      final normalized = value.trim().replaceAll('-', '').replaceAll(' ', '');
      final bytes = base64.decode(base64.normalize(normalized));
      if (bytes.length != 32) throw const FormatException();
      return bytes;
    } on Object catch (error) {
      throw CardoryContainerException(
        CardoryContainerError.invalidRecoveryKey,
        '恢复密钥格式无效。',
        error,
      );
    }
  }

  static String _encodeRecoveryKey(List<int> bytes) {
    final encoded = base64.encode(bytes).replaceAll('=', '');
    return List.generate((encoded.length / 8).ceil(), (index) {
      final start = index * 8;
      final end = min(start + 8, encoded.length);
      return encoded.substring(start, end);
    }).join('-');
  }

  static Uint8List _canonicalJson(Map<String, dynamic> value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));

  static Uint8List _uint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.big);
    return data.buffer.asUint8List();
  }

  static String _encode(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static List<int> _requiredBytes(
    Map<String, dynamic> map,
    String key, {
    required int expectedLength,
  }) {
    final value = _requiredString(map, key);
    final bytes = base64Url.decode(base64Url.normalize(value));
    if (bytes.length != expectedLength) throw FormatException('$key 长度无效');
    return bytes;
  }

  static String _requiredString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! String || value.isEmpty) throw FormatException('$key 无效');
    return value;
  }

  static int _requiredInt(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! int) throw FormatException('$key 无效');
    return value;
  }

  static List<dynamic> _requiredList(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! List<dynamic>) throw FormatException('$key 无效');
    return value;
  }

  static CardoryKeySlotType _parseSlotType(Object? value) =>
      CardoryKeySlotType.values.firstWhere(
        (type) => type.name == value,
        orElse: () => throw const FormatException('密钥槽类型无效'),
      );

  static bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  static List<int> _secureRandomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}

class _ParsedContainer {
  const _ParsedContainer(this.header, this.cipherText);

  final Map<String, dynamic> header;
  final List<int> cipherText;
}
