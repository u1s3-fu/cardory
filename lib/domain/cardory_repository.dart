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
  Future<CardoryLoadResult> restoreFromBackup(
    List<int> bytes,
    String password,
  );
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

abstract interface class VaultSessionRepository {
  Future<void> lock();
}
