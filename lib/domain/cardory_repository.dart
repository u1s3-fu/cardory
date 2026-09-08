import 'cardory_models.dart';

class CardoryLoadResult {
  const CardoryLoadResult({
    required this.data,
    required this.settings,
    required this.path,
    this.recoveredFromBackup = false,
  });

  final CardoryData data;
  final AppSettings settings;
  final String path;
  final bool recoveredFromBackup;
}

enum CardoryAccessState { setupRequired, locked, unlocked }

/// 应用控制器使用的持久化工作区状态。
abstract interface class WorkspaceRepository {
  Future<CardoryLoadResult> load();
  Future<void> save(CardoryData data, AppSettings settings);
  Future<void> saveSettings(AppSettings settings);
}

abstract interface class SyncContainerInspector {
  Future<CardoryData> inspectContainer(List<int> bytes);
}

/// 同步所需的加密容器操作。
abstract interface class SyncRepository implements WorkspaceRepository {
  Future<List<int>> exportContainer();
  Future<String> saveSyncConflictSnapshot(
    List<int> bytes, {
    DateTime? timestamp,
  });
  Future<CardoryData> importContainer(List<int> bytes, AppSettings settings);
}

/// 安全界面所需的保险库生命周期与密码操作。
abstract interface class VaultRepository {
  Future<CardoryAccessState> accessState();
  Future<CardoryLoadResult> setup(String password);
  Future<CardoryLoadResult> unlockWithPassword(String password);
  Future<CardoryLoadResult> restoreFromBackup(List<int> bytes, String password);
  Future<void> changePassword(String currentPassword, String newPassword);
}

/// 供基础设施实现使用的兼容性聚合接口。
///
/// 界面与应用服务应依赖上文更窄的契约之一，而非此聚合接口。
abstract interface class CardoryRepository
    implements WorkspaceRepository, SyncRepository, VaultRepository {}

class CardoryStorageException implements Exception {
  const CardoryStorageException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// 云端/远端数据快照无法用本地保险库密钥解密。
///
/// 可能原因：文件在上传/传输中损坏，或快照由使用不同保险库密码的设备上传。
/// 同步协调器据此把“自动失败”转为可供用户选择的手动处理状态，而不是抛出
/// 一条无从措手的失败提示。
class CardorySnapshotUndecryptableException extends CardoryStorageException {
  const CardorySnapshotUndecryptableException(super.message, [super.cause]);
}

abstract interface class VaultSessionRepository {
  Future<void> lock();
}
