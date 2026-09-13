import '../domain/attachment_repository.dart';
import '../domain/cardory_repository.dart';
import '../domain/sync_credentials.dart';
import '../domain/widget_data_service.dart';
import '../domain/workspace_sync_service.dart';
import 'row_level_workspace_store.dart';
import 'workspace_controller.dart';
import 'workspace_settings_service.dart';

typedef WorkspaceSyncServiceFactory = WorkspaceSyncService Function();

/// 工作区应用服务的组合边界。
///
/// 表现层代码通过本工厂获取服务，而非自行构造具体的
/// 同步与设置服务。
class WorkspaceControllerFactory {
  const WorkspaceControllerFactory({
    required this.workspaceRepository,
    required this.vaultRepository,
    required this.syncRepository,
    required this.credentialStore,
    required this.syncServiceFactory,
    required this.attachmentRepositoryFactory,
    this.rowLevelStoreBuilder,
    this.widgetDataService = const NullWidgetDataService(),
  });

  final WorkspaceRepository workspaceRepository;
  final VaultRepository vaultRepository;
  final SyncRepository syncRepository;
  final SyncCredentialStore credentialStore;
  final WorkspaceSyncServiceFactory syncServiceFactory;
  final AttachmentRepositoryFactory attachmentRepositoryFactory;

  /// 惰性获取行级写入存储：保险库解锁后数据库才可用，控制器创建时
  /// 才调用；返回 null 时业务写入会在控制器处抛错。
  final RowLevelWorkspaceStoreBuilder? rowLevelStoreBuilder;
  final WidgetDataService widgetDataService;

  WorkspaceController create() => WorkspaceController(
    repository: workspaceRepository,
    vaultRepository: vaultRepository,
    settingsService: WorkspaceSettingsService(
      repository: workspaceRepository,
      credentialStore: credentialStore,
    ),
    syncService: syncServiceFactory(),
    attachmentRepositoryFactory: attachmentRepositoryFactory,
    rowLevelStore: rowLevelStoreBuilder?.call(),
    widgetDataService: widgetDataService,
  );
}
