import 'attachment_repository.dart';
import 'cardory_repository.dart';
import 'sync_credentials.dart';
import 'widget_data_service.dart';
import 'workspace_controller.dart';
import 'workspace_settings_service.dart';
import 'workspace_sync_service.dart';

typedef WorkspaceSyncServiceFactory = WorkspaceSyncService Function();

/// Composition boundary for the workspace application services.
///
/// Presentation code receives this factory instead of constructing concrete
/// synchronization and settings services itself.
class WorkspaceControllerFactory {
  const WorkspaceControllerFactory({
    required this.workspaceRepository,
    required this.vaultRepository,
    required this.syncRepository,
    required this.credentialStore,
    required this.syncServiceFactory,
    required this.attachmentRepositoryFactory,
    this.widgetDataService = const NullWidgetDataService(),
  });

  final WorkspaceRepository workspaceRepository;
  final VaultRepository vaultRepository;
  final SyncRepository syncRepository;
  final SyncCredentialStore credentialStore;
  final WorkspaceSyncServiceFactory syncServiceFactory;
  final AttachmentRepositoryFactory attachmentRepositoryFactory;
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
    widgetDataService: widgetDataService,
  );
}
