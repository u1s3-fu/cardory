import 'cardory_models.dart';
import 'sync_status.dart';

typedef WorkspaceListener = void Function();

abstract interface class WorkspaceObservable {
  void addListener(WorkspaceListener listener);
  void removeListener(WorkspaceListener listener);
  void dispose();
}

/// 面向应用的同步边界，供工作区状态使用。
abstract interface class WorkspaceSyncService implements WorkspaceObservable {
  SyncStatus get status;
  bool get hasPendingConflict;
  Future<AppSettings> synchronize(AppSettings settings);
  Future<AppSettings> resolveConflict(
    SyncConflictChoice choice, {
    Map<String, SyncConflictSide> itemChoices = const {},
  });
  @override
  void dispose();
}
