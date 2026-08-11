// 加密容器相关的纯数据结构定义。
//
// 不含业务逻辑，仅定义密钥槽类型、密钥槽信息、容器信息、容器创建参数、
// 恢复密钥轮换请求等值类，以及容器操作异常类型。

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
