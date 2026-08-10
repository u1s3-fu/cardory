/// 加密卡片容器的核心业务逻辑。
///
/// 管理卡片数据的加解密、导入导出和版本控制。通过 [CardoryRepository] 抽象
/// 持久化层，不直接依赖具体的存储实现。

enum CardoryKeySlotType { password, recovery }

class CardoryKeySlotInfo {
  const CardoryKeySlotInfo({
    required this.id,
    required this.type,
    required this.algorithm,
  });

  final String id;
  final CardoryKeySlotType type;
  final String algorithm;
}

class CardoryContainerInfo {
  const CardoryContainerInfo({
    required this.version,
    required this.cipher,
    required this.keySlots,
    required this.payloadLength,
  });

  final int version;
  final String cipher;
  final List<CardoryKeySlotInfo> keySlots;
  final int payloadLength;
}

class CardoryContainerCreation {
  const CardoryContainerCreation({
    required this.bytes,
    required this.recoveryKey,
  });

  final List<int> bytes;
  final String recoveryKey;
}

class CardoryRecoveryRotation {
  const CardoryRecoveryRotation({
    required this.bytes,
    required this.recoveryKey,
  });

  final List<int> bytes;
  final String recoveryKey;
}

enum CardoryContainerError {
  invalidFormat,
  unsupportedVersion,
  invalidCredential,
  missingKeySlot,
  invalidRecoveryKey,
}

class CardoryContainerException implements Exception {
  const CardoryContainerException(this.error, this.message, [this.cause]);

  final CardoryContainerError error;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
