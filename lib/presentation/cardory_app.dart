// Cardory 应用入口。
//
// 以项目看板和待办为核心的跨平台进度管理工具。数据通过 AES-256-GCM
// 加密容器持久化，支持目录同步 / WebDAV / 自建服务 / S3 兼容存储同步。
// 启动时注入 [CardoryStore] 和 [SecureSyncCredentialStore] 作为实现。

import 'package:flutter/material.dart';

import '../application/workspace_controller_factory.dart';
import '../domain/attachment_repository.dart';
import '../domain/sync_credentials.dart';
import '../domain/widget_data_service.dart';
import '../data/attachment_store.dart';
import '../data/cardory_store.dart';
import '../domain/cardory_models.dart';
import '../services/home_widget_data_service.dart';
import '../sync/sync_credentials.dart'
    show SecureSyncCredentialStore, SecureVaultCredentialStore;
import '../sync/sync_coordinator.dart';
import '../sync/sync_provider_registry.dart';
import 'cardory_theme.dart';
import 'model_colors.dart';
import 'pages/vault_gate.dart';

// 以下 re-export 作为统一入口，供 main.dart 与 widget 测试
// （test/widget_test.dart 经 package:cardory/main.dart）消费公共类型，
// 请勿随意删除，以免破坏测试编译。
export 'dialogs/progress_dialog.dart';
export 'dialogs/security_dialogs.dart';
export '../application/workspace_controller_factory.dart';
export 'pages/asset_dialog.dart';
export 'pages/home_page.dart';
export 'pages/project_page.dart';
export 'pages/settings_page.dart';
export 'pages/settings_panel.dart';
export 'pages/vault_gate.dart';
export 'widgets/app_top_bar.dart';
export 'widgets/hero_header.dart';
export 'widgets/overview.dart';
export 'widgets/progress_timeline.dart';
export 'widgets/project_dialog.dart';
export 'widgets/project_list_panel.dart';
export 'widgets/subtodo_dialogs.dart';
export 'widgets/todo_dialog.dart';
export 'settings_models.dart';
export 'widgets/asset_detail_dialog.dart';
export 'widgets/kanban_board.dart';
export 'widgets/password_text_field.dart';
export 'widgets/reminder_panel.dart';
export 'widgets/todo_panel.dart';

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
    Future<void> Function(AppSettings, SyncCredentials)? connectionTester,
  }) : credentialStore = credentialStore ?? SecureSyncCredentialStore(),
       vaultCredentialStore =
           vaultCredentialStore ?? SecureVaultCredentialStore(),
       _providerFactory = providerFactory,
       _widgetDataService = widgetDataService ?? const HomeWidgetDataService(),
       _attachmentRepositoryFactory =
           attachmentRepositoryFactory ?? AttachmentStore.forDataFile,
       _connectionTester = connectionTester;

  final VaultRepository vaultRepository;
  final WorkspaceRepository workspaceRepository;
  final SyncRepository syncRepository;
  final VaultSessionRepository? vaultSession;
  final SyncCredentialStore credentialStore;
  final VaultCredentialStore vaultCredentialStore;
  final SyncProviderFactory? _providerFactory;
  final WidgetDataService _widgetDataService;
  final AttachmentRepositoryFactory _attachmentRepositoryFactory;
  final Future<void> Function(AppSettings, SyncCredentials)? _connectionTester;

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
  Future<void> Function(AppSettings, SyncCredentials) get connectionTester =>
      _connectionTester ?? testSyncConnection;

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
      // 扁平化：桌面端隐藏滚动条（保留滚轮/键盘/触控板滚动）。
      scrollBehavior: const CardoryScrollBehavior(),
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
        connectionTester: widget.connectionTester,
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
