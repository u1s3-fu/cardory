// 启动时通过 Riverpod 注入持久化与凭据实现；构造参数仍保留给测试和嵌入方。

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../application/workspace_controller_factory.dart';
import '../application/row_level_workspace_store.dart';
import '../application/time_tracking_store.dart';
import '../data/attachment_store.dart';
import '../data/db/app_database.dart' as db;
import '../domain/attachment_repository.dart';
import '../domain/calendar_push_registry.dart';
import '../domain/cardory_models.dart';
import '../domain/cardory_repository.dart';
import '../domain/due_reminder_service.dart';
import '../domain/sync_credentials.dart';
import '../domain/widget_data_service.dart';
import '../providers/app_providers.dart';
import '../routing/app_router.dart';
import '../services/github_update_service.dart';
import '../services/home_widget_data_service.dart';
import '../services/system_calendar_service.dart';
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
    DueReminderService? dueReminderService,
    AttachmentRepositoryFactory? attachmentRepositoryFactory,
    RowLevelWorkspaceStoreBuilder? rowLevelStoreBuilder,
    TimeTrackingStoreBuilder? timeTrackingStoreBuilder,
    SystemCalendarService? systemCalendar,
    CalendarPushRegistry? calendarPushRegistry,
    String? Function()? deltaKeyProvider,
    db.AppDatabase? Function()? deltaDatabaseProvider,
    Future<void> Function(AppSettings, SyncCredentials)? connectionTester,
    GithubUpdateService? updateService,
  }) : credentialStore = credentialStore ?? SecureSyncCredentialStore(),
       vaultCredentialStore =
           vaultCredentialStore ?? SecureVaultCredentialStore(),
       // ignore: prefer_initializing_formals
       _providerFactory = providerFactory,
       _widgetDataService = widgetDataService ?? createWidgetDataService(),
       _dueReminderService =
           dueReminderService ?? const NullDueReminderService(),
       _attachmentRepositoryFactory =
           attachmentRepositoryFactory ?? AttachmentStore.forDataFile,
       // ignore: prefer_initializing_formals
       _rowLevelStoreBuilder = rowLevelStoreBuilder,
       // ignore: prefer_initializing_formals
       _timeTrackingStoreBuilder = timeTrackingStoreBuilder,
       // ignore: prefer_initializing_formals
       _systemCalendar = systemCalendar,
       // ignore: prefer_initializing_formals
       _calendarPushRegistry = calendarPushRegistry,
       // ignore: prefer_initializing_formals
       _deltaKeyProvider = deltaKeyProvider,
       // ignore: prefer_initializing_formals
       _deltaDatabaseProvider = deltaDatabaseProvider,
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
  final DueReminderService _dueReminderService;
  final AttachmentRepositoryFactory _attachmentRepositoryFactory;
  final RowLevelWorkspaceStoreBuilder? _rowLevelStoreBuilder;
  final TimeTrackingStoreBuilder? _timeTrackingStoreBuilder;
  final SystemCalendarService? _systemCalendar;
  final CalendarPushRegistry? _calendarPushRegistry;
  final String? Function()? _deltaKeyProvider;
  final db.AppDatabase? Function()? _deltaDatabaseProvider;
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
          deltaKeyProvider: _deltaKeyProvider,
          deltaDatabaseProvider: _deltaDatabaseProvider,
        ),
        attachmentRepositoryFactory: attachmentRepositoryFactory,
        rowLevelStoreBuilder: _rowLevelStoreBuilder,
        widgetDataService: widgetDataService,
        dueReminderService: _dueReminderService,
        systemCalendarService: effectiveSystemCalendar,
        calendarPushRegistry: _calendarPushRegistry,
      );

  SyncProviderFactory get providerFactory =>
      _providerFactory ?? defaultSyncProviderFactory(credentialStore);
  WidgetDataService get widgetDataService => _widgetDataService;
  DueReminderService get dueReminderService => _dueReminderService;

  /// 系统日历服务：注入优先，缺省按平台创建（每会话缓存，控制器对账与
  /// 日历页共用同一实例，避免重复初始化移动端日历插件 / 桌面 .ics 目录）。
  late final SystemCalendarService effectiveSystemCalendar =
      _systemCalendar ?? createSystemCalendarService();
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
    final app = MaterialApp.router(
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
    // Windows 专用：摘除整棵语义树，消除控制台 AXTree 刷屏。
    //
    // 背景（Flutter 引擎已知缺陷，非本项目代码问题）：
    //  - #98099：Windows 无障碍桥接 AXTree 更新失败的通用形态，
    //    2022 年至今未修；
    //  - #182444：精确机理——Tooltip 用 OverlayPortal 把浮层语义节点
    //    「嫁接」到目标节点下，而 ListView/GridView 的 two-pane 语义
    //    合成 _innerNode 间接层，使嫁接子节点被摘除时其语义父节点
    //    收不到通知；悬停切换时发出的语义更新引用了一个不在树里的
    //    节点 ID，Windows 的 AXTree::Unserialize 拒绝该更新并逐次打印
    //    「Failed to update ui::AXTree, error: N will not be in the
    //    tree and is not the new root」——鼠标悬停/滚轮滚动时持续刷屏；
    //  - #193588：同一形态在 macOS 上会在下一次 AX 查询时崩溃
    //    （EXC_BAD_ACCESS），需 VoiceOver 等辅助技术激活才触发。
    // framework 侧修复（#190344）已关闭未合入；截至 Flutter 3.47.4，
    // 应用侧没有任何「半修」手段：Tooltip(excludeFromSemantics: true)
    // 只移除浮层文字注解，OverlayPortal 照常创建、嫁接照常发生。
    //
    // 代价：Windows 上读屏软件完全失效（语义树为空）。
    // 取舍依据：单用户本地优先应用，产品定位不以无障碍为卖点；且
    // Windows 读屏本就受该缺陷破坏（悬停即产生不一致的语义树）。
    // 恢复读屏：删掉本包裹即可（报错会回来，属引擎缺陷）。
    //
    // 为何用 defaultTargetPlatform 而非 dart:io Platform：widget 测试
    // 默认模拟 android 平台，不会被误伤（byTooltip 等语义断言照常工作）。
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return ExcludeSemantics(child: app);
    }
    return app;
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
    timeTrackingStore: widget._timeTrackingStoreBuilder?.call(),
    rowLevelStore: widget._rowLevelStoreBuilder?.call(),
    systemCalendar: widget.effectiveSystemCalendar,
    calendarPushRegistry: widget._calendarPushRegistry,
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
          dueReminderService: ref.watch(dueReminderServiceProvider),
          calendarPushRegistry: ref.watch(calendarPushRegistryProvider),
          attachmentRepositoryFactory: ref.watch(
            attachmentRepositoryFactoryProvider,
          ),
          rowLevelStoreBuilder: ref.watch(rowLevelStoreBuilderProvider),
          timeTrackingStoreBuilder: ref.watch(timeTrackingStoreBuilderProvider),
          deltaKeyProvider: () =>
              ref.read(sqlCipherVaultStoreProvider).currentVaultKey,
          deltaDatabaseProvider: () =>
              ref.read(sqlCipherVaultStoreProvider).database,
          connectionTester: ref.watch(syncConnectionTesterProvider),
        ),
      ),
    ),
  );
}
