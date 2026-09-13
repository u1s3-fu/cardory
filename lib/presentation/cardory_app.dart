// 启动时通过 Riverpod 注入持久化与凭据实现；构造参数仍保留给测试和嵌入方。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../application/workspace_controller_factory.dart';
import '../application/row_level_workspace_store.dart';
import '../data/attachment_store.dart';
import '../domain/attachment_repository.dart';
import '../domain/cardory_models.dart';
import '../domain/cardory_repository.dart';
import '../domain/sync_credentials.dart';
import '../domain/widget_data_service.dart';
import '../providers/app_providers.dart';
import '../routing/app_router.dart';
import '../services/github_update_service.dart';
import '../services/home_widget_data_service.dart';
import '../sync/sync_coordinator.dart';
import '../sync/sync_credentials.dart'
    show SecureSyncCredentialStore, SecureVaultCredentialStore;
import '../sync/sync_debug_log.dart';
import '../sync/sync_provider_registry.dart';
import 'cardory_theme.dart';
import 'model_colors.dart';
import 'pages/home_page.dart';
import 'pages/vault_gate.dart';
import 'vault_auto_lock_controller.dart';

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
    RowLevelWorkspaceStoreBuilder? rowLevelStoreBuilder,
    Future<void> Function(AppSettings, SyncCredentials)? connectionTester,
    GithubUpdateService? updateService,
  }) : credentialStore = credentialStore ?? SecureSyncCredentialStore(),
       vaultCredentialStore =
           vaultCredentialStore ?? SecureVaultCredentialStore(),
       // ignore: prefer_initializing_formals
       _providerFactory = providerFactory,
       _widgetDataService = widgetDataService ?? const HomeWidgetDataService(),
       _attachmentRepositoryFactory =
           attachmentRepositoryFactory ?? AttachmentStore.forDataFile,
       // ignore: prefer_initializing_formals
       _rowLevelStoreBuilder = rowLevelStoreBuilder,
       // ignore: prefer_initializing_formals
       _connectionTester = connectionTester,
       // ignore: prefer_initializing_formals
       _updateService = updateService;

  final VaultRepository vaultRepository;
  final WorkspaceRepository workspaceRepository;
  final SyncRepository syncRepository;
  final VaultSessionRepository? vaultSession;
  final SyncCredentialStore credentialStore;
  final VaultCredentialStore vaultCredentialStore;
  final SyncProviderFactory? _providerFactory;
  final WidgetDataService _widgetDataService;
  final AttachmentRepositoryFactory _attachmentRepositoryFactory;
  final RowLevelWorkspaceStoreBuilder? _rowLevelStoreBuilder;
  final Future<void> Function(AppSettings, SyncCredentials)? _connectionTester;
  final GithubUpdateService? _updateService;

  /// 更新检查服务；测试可注入假实现，null 时由 HomePage 使用默认 GitHub 服务。
  GithubUpdateService? get updateService => _updateService;

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
        rowLevelStoreBuilder: _rowLevelStoreBuilder,
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

/// 应用级会话状态。
///
/// 门禁解锁后由本 State 持有工作台会话（已加载结果、自动锁定与锁定清理），
/// 并把工作台作为受保护路由 [workbenchRoutePath] 承载；锁定 / 应用进入后台时
/// 统一在这里关闭数据库会话、清除已保存密码与桌面小组件摘要并回到门禁页。
class _CardoryAppState extends State<CardoryApp> {
  AppSettings _settings = const AppSettings();

  /// 门禁路由的构建代际：锁定后自增，强制门禁页重建并重新检测保险库状态。
  int _vaultEpoch = 0;

  /// 当前保险库是否已解锁（redirect 门禁依据）。
  bool _unlocked = false;

  /// 解锁成功携带的加载结果，供工作台路由以无重复加载方式初始化。
  CardoryLoadResult? _latestResult;

  /// 通知 go_router 重新评估 redirect（状态切换的兜底门禁）。
  final ValueNotifier<bool> _vaultUnlockedNotifier = ValueNotifier<bool>(false);

  /// 负责清理业务页残留导航栈（详情页等 Navigator.push 的页面）。
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  VaultAutoLockController? _autoLock;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _enableSyncDebugLog();
    _router = createAppRouter(
      navigatorKey: _navigatorKey,
      vaultGateBuilder: _buildVaultGate,
      workbenchShellBuilder: _buildWorkbenchShell,
      workbenchContentBuilder: _buildWorkbenchContent,
      isVaultUnlocked: () => _unlocked,
      refreshListenable: _vaultUnlockedNotifier,
      vaultPageEpoch: () => _vaultEpoch,
    );
  }

  /// 启用同步调试日志：写入应用文档目录 Cardory/cardory-sync-debug.log，
  /// 便于手动复现同步问题后查看原始异常。失败时静默降级为仅控制台输出。
  Future<void> _enableSyncDebugLog() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      initSyncDebugLog(p.join(directory.path, 'Cardory'));
    } catch (_) {
      // 文档目录不可用时无需处理，日志器已内置降级。
    }
  }

  @override
  void dispose() {
    _disarmAutoLock();
    _vaultUnlockedNotifier.dispose();
    _router.dispose();
    super.dispose();
  }

  void _applySettings(AppSettings settings) {
    setState(() => _settings = settings);
    // 自动锁定开关可能在设置中变化：按当前会话重新装配。
    _armAutoLockIfNeeded();
  }

  /// 门禁解锁 / 自动解锁成功回调：切换受保护工作台路由。
  void _handleUnlocked(CardoryLoadResult result) {
    setState(() {
      _unlocked = true;
      _latestResult = result;
    });
    _vaultUnlockedNotifier.value = true;
    _armAutoLockIfNeeded();
    _router.go(workbenchRoutePath);
  }

  /// 自动锁定：应用进入后台且开启自动锁定时触发。
  Future<void> _handleAutoLock() async => _lockSession();

  /// 统一锁定流程（fail-closed）：
  /// 关闭数据库会话 → 删除已保存密码 → 清除桌面小组件摘要 → 回到门禁页。
  Future<void> _lockSession() async {
    if (!_unlocked) return;
    _disarmAutoLock();
    try {
      await widget.vaultSession?.lock();
    } catch (_) {
      // 会话关闭失败也不能让凭据与小组件摘要继续暴露。
    }
    await widget.vaultCredentialStore.deletePassword();
    await widget.widgetDataService.clearWidgetData();
    if (!mounted) return;
    setState(() {
      _unlocked = false;
      _latestResult = null;
      _vaultEpoch += 1;
    });
    _vaultUnlockedNotifier.value = false;
    // 清掉业务页残留导航栈（详情页等），并让门禁页以新代际重建重新检测。
    _navigatorKey.currentState?.popUntil((route) => route.isFirst);
    _router.go(vaultRoutePath);
  }

  void _armAutoLockIfNeeded() {
    if (!_unlocked || !_settings.autoLockEnabled) {
      _disarmAutoLock();
      return;
    }
    if (_autoLock != null) return;
    _autoLock = VaultAutoLockController(onLock: _handleAutoLock)..start();
  }

  void _disarmAutoLock() {
    _autoLock?.stop();
    _autoLock = null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '板记 Cardory',
      debugShowCheckedModeBanner: false,
      theme: buildCardoryTheme(
        _settings.themeColor,
        background: Color(_settings.backgroundColorValue),
      ),
      // 扁平化：桌面端隐藏滚动条（保留滚轮/键盘/触控板滚动）。
      scrollBehavior: const CardoryScrollBehavior(),
      routerConfig: _router,
    );
  }

  Widget _buildVaultGate(BuildContext context) => CardoryVaultGate(
    vaultRepository: widget.vaultRepository,
    workspaceRepository: widget.workspaceRepository,
    credentialStore: widget.credentialStore,
    vaultCredentialStore: widget.vaultCredentialStore,
    attachmentRepositoryFactory: widget.attachmentRepositoryFactory,
    onSettingsChanged: _applySettings,
    onUnlocked: _handleUnlocked,
  );

  /// 工作台 Shell：持有控制器与导航框架，内容区来自路由子页。
  Widget _buildWorkbenchShell(BuildContext context, Widget child) => HomePage(
    controllerFactory: widget.controllerFactory,
    vaultRepository: widget.vaultRepository,
    credentialStore: widget.credentialStore,
    vaultCredentialStore: widget.vaultCredentialStore,
    onSettingsChanged: _applySettings,
    initialResult: _latestResult,
    attachmentRepositoryFactory: widget.attachmentRepositoryFactory,
    connectionTester: widget.connectionTester,
    updateService: widget.updateService,
    child: child,
  );

  /// 工作台内容区：按路由位置渲染分区 / 项目详情（作用域由 Shell 提供）。
  Widget _buildWorkbenchContent(
    BuildContext context,
    WorkbenchLocation location,
  ) => WorkbenchSectionContent(location: location);
}

void runCardoryApp() {
  runApp(
    ProviderScope(
      child: Consumer(
        builder: (context, ref, child) => CardoryApp(
          vaultRepository: ref.watch(vaultRepositoryProvider),
          workspaceRepository: ref.watch(workspaceRepositoryProvider),
          syncRepository: ref.watch(syncRepositoryProvider),
          vaultSession: ref.watch(vaultSessionRepositoryProvider),
          credentialStore: ref.watch(syncCredentialStoreProvider),
          vaultCredentialStore: ref.watch(vaultCredentialStoreProvider),
          providerFactory: ref.watch(syncProviderFactoryProvider),
          widgetDataService: ref.watch(widgetDataServiceProvider),
          attachmentRepositoryFactory: ref.watch(
            attachmentRepositoryFactoryProvider,
          ),
          rowLevelStoreBuilder: ref.watch(rowLevelStoreBuilderProvider),
          connectionTester: ref.watch(syncConnectionTesterProvider),
        ),
      ),
    ),
  );
}
