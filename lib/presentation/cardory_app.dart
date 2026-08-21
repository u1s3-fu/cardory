// Cardory 应用入口。
//
// 以项目看板和待办为核心的跨平台进度管理工具。数据通过 AES-256-GCM
// 加密容器持久化，支持目录同步 / WebDAV / 自建服务 / S3 兼容存储同步。
// 启动时注入 [CardoryStore] 和 [SecureSyncCredentialStore] 作为实现。

import 'package:flutter/material.dart';

import '../application/attachment_repository.dart';
import '../application/sync_credentials.dart';
import '../application/widget_data_service.dart';
import '../application/workspace_controller_factory.dart';
import '../data/attachment_store.dart';
import '../data/cardory_store.dart';
import '../domain/cardory_models.dart';
import '../services/home_widget_data_service.dart';
import '../sync/sync_credentials.dart' show SecureSyncCredentialStore, SecureVaultCredentialStore, VaultCredentialStore;
import '../sync/sync_coordinator.dart';
import '../sync/sync_provider_registry.dart';
import 'cardory_theme.dart';
import 'model_colors.dart';
import 'pages/vault_gate.dart';

export 'dialogs/progress_dialog.dart';
export 'dialogs/security_dialogs.dart';
export '../application/workspace_controller_factory.dart';
export 'pages/asset_dialog.dart';
export 'pages/dashboard.dart';
export 'pages/home_page.dart';
export 'pages/project_page.dart';
export 'pages/settings_page.dart';
export 'pages/task_dialogs.dart';
export 'pages/vault_gate.dart';
export 'settings_models.dart';
export 'widgets/password_text_field.dart';

class CardoryApp extends StatefulWidget {
  CardoryApp({
    super.key,
    required this.vaultRepository,
    required this.workspaceRepository,
    required this.syncRepository,
    this.vaultSession,
    SyncCredentialStore? credentialStore,
    VaultCredentialStore? vaultCredentialStore,
    SyncProviderFactory? providerFactory,
    WidgetDataService? widgetDataService,
    AttachmentRepositoryFactory? attachmentRepositoryFactory,
  }) : credentialStore = credentialStore ?? SecureSyncCredentialStore(),
       vaultCredentialStore =
           vaultCredentialStore ?? SecureVaultCredentialStore(),
       _providerFactory = providerFactory,
       _widgetDataService = widgetDataService ?? const HomeWidgetDataService(),
       _attachmentRepositoryFactory =
           attachmentRepositoryFactory ?? AttachmentStore.forDataFile;

  final VaultRepository vaultRepository;
  final WorkspaceRepository workspaceRepository;
  final SyncRepository syncRepository;
  final VaultSessionRepository? vaultSession;
  final SyncCredentialStore credentialStore;
  final VaultCredentialStore vaultCredentialStore;
  final SyncProviderFactory? _providerFactory;
  final WidgetDataService _widgetDataService;
  final AttachmentRepositoryFactory _attachmentRepositoryFactory;

  WorkspaceControllerFactory get controllerFactory =>
      WorkspaceControllerFactory(
        workspaceRepository: workspaceRepository,
        vaultRepository: vaultRepository,
        syncRepository: syncRepository,
        credentialStore: credentialStore,
        syncServiceFactory: () => SyncCoordinator(
          repository: syncRepository,
          providerFactory: providerFactory,
          attachmentRepositoryFactory: attachmentRepositoryFactory,
        ),
        attachmentRepositoryFactory: attachmentRepositoryFactory,
        widgetDataService: widgetDataService,
      );

  SyncProviderFactory get providerFactory =>
      _providerFactory ?? defaultSyncProviderFactory(credentialStore);
  WidgetDataService get widgetDataService => _widgetDataService;
  AttachmentRepositoryFactory get attachmentRepositoryFactory =>
      _attachmentRepositoryFactory;

  @override
  State<CardoryApp> createState() => _CardoryAppState();
}

class _CardoryAppState extends State<CardoryApp> {
  AppSettings _settings = const AppSettings();

  void _applySettings(AppSettings settings) =>
      setState(() => _settings = settings);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '板记 Cardory',
      debugShowCheckedModeBanner: false,
      theme: buildCardoryTheme(
        _settings.themeColor,
        background: Color(_settings.backgroundColorValue),
      ),
      home: CardoryVaultGate(
        vaultRepository: widget.vaultRepository,
        workspaceRepository: widget.workspaceRepository,
        controllerFactory: widget.controllerFactory,
        vaultSession: widget.vaultSession,
        credentialStore: widget.credentialStore,
        vaultCredentialStore: widget.vaultCredentialStore,
        providerFactory: widget.providerFactory,
        autoLockEnabled: _settings.autoLockEnabled,
        onSettingsChanged: _applySettings,
        widgetDataService: widget.widgetDataService,
        attachmentRepositoryFactory: widget.attachmentRepositoryFactory,
      ),
    );
  }
}

void runCardoryApp() {
  final store = CardoryStore();
  runApp(
    CardoryApp(
      vaultRepository: store,
      workspaceRepository: store,
      syncRepository: store,
      vaultSession: store,
      credentialStore: SecureSyncCredentialStore(),
    ),
  );
}
