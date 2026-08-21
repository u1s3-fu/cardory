import '../domain/cardory_models.dart';

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

/// Persistent workspace state used by the application controller.
abstract interface class WorkspaceRepository {
  Future<CardoryLoadResult> load();
  Future<void> save(CardoryData data, AppSettings settings);
  Future<void> saveSettings(AppSettings settings);
}

abstract interface class SyncContainerInspector {
  Future<CardoryData> inspectContainer(List<int> bytes);
}

/// Encrypted-container operations required by synchronization.
abstract interface class SyncRepository implements WorkspaceRepository {
  Future<List<int>> exportContainer();
  Future<String> saveSyncConflictSnapshot(
    List<int> bytes, {
    DateTime? timestamp,
  });
  Future<CardoryData> importContainer(List<int> bytes, AppSettings settings);
}

/// Vault lifecycle and password operations required by the security UI.
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

/// Compatibility aggregate for infrastructure implementations.
///
/// UI and application services should depend on one of the narrower contracts
/// above instead of this aggregate.
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
