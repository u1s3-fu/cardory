import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../application/workspace_controller.dart';
import '../../application/workspace_controller_factory.dart';
import '../../application/workspace_settings_service.dart';
import '../../domain/attachment_repository.dart';
import '../../domain/cardory_models.dart';
import '../../domain/cardory_repository.dart';
import '../../domain/sync_credentials.dart';
import '../../domain/sync_status.dart';
import '../../routing/app_router.dart';
import '../../services/github_update_service.dart';
import '../app_section.dart';
import '../cardory_theme.dart';
import '../dialogs/about_dialog.dart';
import '../dialogs/security_dialogs.dart';
import '../dialogs/update_dialog.dart';
import '../settings_models.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/confirm_dialogs.dart';
import '../widgets/hero_header.dart';
import '../widgets/kanban_board.dart';
import '../widgets/overview.dart';
import '../widgets/project_dialog.dart';
import '../widgets/project_list_panel.dart';
import '../widgets/reminder_panel.dart';
import '../widgets/section_nav.dart';
import '../widgets/sidebar.dart';
import '../widgets/subtodo_dialogs.dart';
import '../widgets/sync_conflict_dialogs.dart';
import '../widgets/todo_dialog.dart';
import '../widgets/todo_panel.dart';
import 'asset_dialog.dart';
import 'project_page.dart';
import 'settings_page.dart';
import 'settings_panel.dart';

/// 工作台 Shell：持有工作区控制器、顶部栏、侧栏与底部导航；
/// 内容区由路由（[WorkbenchLocation] 对应的子路由）驱动，
/// /projects 与 /projects/:projectId 是独立的受门禁路由。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controllerFactory,
    required this.vaultRepository,
    required this.credentialStore,
    required this.vaultCredentialStore,
    required this.onSettingsChanged,
    required this.child,
    this.initialResult,
    required this.attachmentRepositoryFactory,
    this.connectionTester,
    this.updateService,
  });

  final WorkspaceControllerFactory controllerFactory;
  final VaultRepository vaultRepository;
  final SyncCredentialStore credentialStore;
  final VaultCredentialStore vaultCredentialStore;
  final ValueChanged<AppSettings> onSettingsChanged;
  final CardoryLoadResult? initialResult;
  final AttachmentRepositoryFactory attachmentRepositoryFactory;
  final Future<void> Function(AppSettings, SyncCredentials)? connectionTester;

  /// 更新检查服务；测试可注入假实现，缺省使用 GitHub Releases。
  final GithubUpdateService? updateService;

  /// ShellRoute 注入的路由子内容（当前分区 / 项目详情）。
  final Widget child;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final WorkspaceController _controller;

  CardoryData get _data => _controller.data;
  AppSettings get _settings => _controller.settings;
  String get _dataPath => _controller.dataPath;
  String? get _error => _controller.error;
  bool get _loading => _controller.loading;
  SyncStatus get _syncStatus => _controller.syncStatus;
  AttachmentRepository? get _attachmentStore =>
      _controller.attachmentRepository;

  /// 侧栏 / 底部导航的当前分区：由路由路径推导（详情页高亮「项目」）。
  AppSection get _currentSection {
    final path = GoRouterState.of(context).uri.path;
    if (path.startsWith(projectsRoutePath)) return AppSection.projects;
    if (path == todosRoutePath) return AppSection.todos;
    if (path == settingsRoutePath) return AppSection.settings;
    return AppSection.home;
  }

  String get _sectionTitle => switch (_currentSection) {
    AppSection.home => '看板',
    AppSection.todos => '待办事项',
    AppSection.projects =>
      GoRouterState.of(context).uri.path == projectsRoutePath ? '项目' : '项目详情',
    AppSection.settings => '设置',
  };

  @override
  void initState() {
    super.initState();
    _controller = widget.controllerFactory.create()
      ..addListener(_onWorkspaceChanged);
    _initialize();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onWorkspaceChanged)
      ..dispose();
    super.dispose();
  }

  void _onWorkspaceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    await _controller.initialize(widget.initialResult);
    if (!mounted || _controller.error != null) return;
    widget.onSettingsChanged(_settings);
    if (_controller.recoveredFromBackup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('主数据文件损坏，已从备份恢复。')));
      });
    }
    // 启动完成后静默检查一次更新：无新版本或检查失败均不打扰用户。
    _checkForUpdate();
  }

  static final GithubUpdateService _defaultUpdateService =
      GithubUpdateService();

  GithubUpdateService get _updateService =>
      widget.updateService ?? _defaultUpdateService;

  String? _currentVersion;

  /// 检查 GitHub 是否有新版本。
  ///
  /// [manual] 为 true 时来自设置面板手动点击：无更新提示"已是最新版本"，
  /// 检查失败提示错误；为 false 时（启动静默检查）任何情况都不提示。
  Future<void> _checkForUpdate({bool manual = false}) async {
    if (!mounted) return;
    final info = await _updateService.fetchLatestRelease();
    if (!mounted) return;
    if (info == null) {
      if (manual) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('检查更新失败，请稍后重试。')));
      }
      return;
    }
    final current = await _currentAppVersion();
    if (!mounted) return;
    if (current == null) {
      if (manual) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法读取本地版本号，请稍后重试。')));
      }
      return;
    }
    final comparison = compareVersions(current, info.version);
    if (comparison == VersionComparison.newer) {
      await showUpdateDialog(context, release: info, currentVersion: current);
    } else if (manual) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已是最新版本（$current）。')));
    }
  }

  /// 获取本地应用版本号（读取一次后缓存）。
  ///
  /// 读取失败返回 null 且不缓存失败结果，调用方应跳过版本比较：
  /// 回退到可比较的假版本号（如 '0.0.0'）会被判为“有新版本”造成误报。
  Future<String?> _currentAppVersion() async {
    final cached = _currentVersion;
    if (cached != null) return cached;
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
    } catch (_) {
      return null;
    }
    return _currentVersion;
  }

  Future<void> _load() async {
    await _controller.reload();
    if (mounted && _controller.error == null) {
      widget.onSettingsChanged(_settings);
    }
  }

  Future<bool> _perform(Future<void> Function() operation) async {
    try {
      await operation();
      return true;
    } catch (error) {
      _showError(error);
      return false;
    }
  }

  void _showError(Object error, {String message = '操作未完成，请检查设置后重试。'}) {
    if (!mounted) return;
    debugPrint('Cardory operation failed: $error');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSettings([SettingsCategoryType? category]) async {
    final result = await showDialog<SettingsResult>(
      context: context,
      builder: (_) => SettingsDialog(
        settings: _settings,
        credentialStore: widget.credentialStore,
        currentDataPath: _dataPath,
        category: category,
        connectionTester: widget.connectionTester,
      ),
    );
    if (result == null) return;
    final settings = result.settings;
    try {
      await _controller.applySettings(
        settings,
        credentials: SyncCredentialUpdate(
          webDavPassword: result.credentials.password,
          selfHostedToken: result.selfHostedToken,
          s3: result.s3,
        ),
      );
      if (!mounted) return;
      widget.onSettingsChanged(settings);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _sync() async {
    await _controller.synchronize();
    if (!mounted) return;
    final status = _syncStatus;
    if (status.phase == SyncPhase.conflict) {
      await _resolveSyncConflict();
      return;
    }
    if (status.phase == SyncPhase.failure && status.message != null) {
      _showError(status, message: status.message!);
      return;
    }
    if (status.phase == SyncPhase.success && status.message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(status.message!)));
    }
  }

  Future<void> _resolveSyncConflict() async {
    final status = _syncStatus;
    final conflicts = status.conflicts;
    final kind = status.conflictKind ?? SyncConflictKind.concurrent;
    final SyncConflictChoice? choice;
    if (kind == SyncConflictKind.unreadableRemote) {
      // 云端快照无法解密：不展示差异清单，只给「用本地覆盖云端 / 跳过」。
      choice = await showUndecryptableRemoteDialog(context);
    } else {
      choice = await showSyncConflictDialog(context, conflicts, kind: kind);
    }
    if (choice == null || choice == SyncConflictChoice.cancel || !mounted) {
      return;
    }

    // 云端快照无法解密时的「覆盖云端」会替换云端数据，且可能影响另一台
    // 密码不同的设备，需二次确认。
    if (kind == SyncConflictKind.unreadableRemote) {
      final confirmed = await confirmLocalOverwriteCloud(context);
      if (!confirmed || !mounted) return;
    }

    // 首次同步选「使用远端」会把本地从未上云的数据整体替换，需二次确认。
    if (choice == SyncConflictChoice.keepRemote &&
        kind == SyncConflictKind.firstSync) {
      final confirmed = await confirmDestructiveSyncOverride(
        context,
        isFirstSync: true,
        conflicts: conflicts,
      );
      if (!confirmed || !mounted) return;
    }

    Map<String, SyncConflictSide> itemChoices = const {};
    if (choice == SyncConflictChoice.manualMerge) {
      final selected = await showManualMergeDialog(context, conflicts);
      if (selected == null || !mounted) return;
      itemChoices = selected;
    }
    try {
      await _controller.resolveSyncConflict(choice, itemChoices: itemChoices);
      if (!mounted) return;
      final status = _syncStatus;
      if (status.phase == SyncPhase.failure && status.message != null) {
        _showError(status, message: status.message!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status.summary?.displayText ?? status.message ?? '同步完成',
            ),
          ),
        );
      }
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _changePassword() async {
    final passwords = await showDialog<PasswordChangeResult>(
      context: context,
      builder: (_) => const PasswordChangeDialog(),
    );
    if (passwords == null) return;
    try {
      await _controller.changePassword(
        passwords.currentPassword,
        passwords.newPassword,
      );
      await widget.vaultCredentialStore.writePassword(passwords.newPassword);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密码已修改。')));
      }
    } catch (error) {
      _showError(error, message: '密码修改失败，请确认当前密码后重试。');
    }
  }

  // ---- 项目 ----

  Future<void> _addProject() async {
    final project = await showDialog<ProjectData>(
      context: context,
      builder: (_) => const ProjectDialog(),
    );
    if (project == null) return;
    await _perform(() => _controller.addProject(project));
  }

  Future<void> _editProject(ProjectData project) async {
    final updated = await showDialog<ProjectData>(
      context: context,
      builder: (_) => ProjectDialog(project: project),
    );
    if (updated == null) return;
    await _perform(() => _controller.editProject(updated));
  }

  Future<void> _deleteProject(ProjectData project) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除项目',
      content: '确定删除“${project.title}”吗？关联待办和资产也会一并删除。',
      confirmLabel: '删除',
    );
    if (ok != true) return;
    await _perform(() => _controller.deleteProject(project.id));
  }

  /// 打开项目详情：拆分为独立受门禁路由 /projects/:projectId。
  Future<void> _openProject(ProjectData project) async {
    context.go('$projectsRoutePath/${project.id}');
  }

  // ---- 待办 ----

  Future<void> _addTodo() async {
    final todo = await showDialog<TodoData>(
      context: context,
      builder: (_) => TodoDialog(
        projects: _data.projects,
        recordSubTodoCreatedAt: _settings.recordSubTodoCreatedAt,
      ),
    );
    if (todo == null) return;
    await _perform(() => _controller.addTodo(todo));
  }

  Future<TodoData?> _openTodo(TodoData todo) async {
    final updated = await showDialog<TodoData>(
      context: context,
      builder: (_) => TodoDialog(
        projects: _data.projects,
        todo: todo,
        recordSubTodoCreatedAt: _settings.recordSubTodoCreatedAt,
      ),
    );
    if (updated == null) return null;
    return await _perform(() => _controller.updateTodo(updated))
        ? updated
        : null;
  }

  Future<bool> _deleteTodo(TodoData todo) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除待办',
      content: '确定删除“${todo.title}”吗？',
      confirmLabel: '删除',
    );
    if (confirmed != true) return false;
    return _perform(() => _controller.deleteTodo(todo.id));
  }

  Future<TodoData?> _addProjectTodo(ProjectData project) async {
    final todo = await showDialog<TodoData>(
      context: context,
      builder: (_) => TodoDialog(
        projects: _data.projects,
        initialProject: project,
        recordSubTodoCreatedAt: _settings.recordSubTodoCreatedAt,
      ),
    );
    if (todo == null) return null;
    return await _perform(() => _controller.addTodo(todo)) ? todo : null;
  }

  Future<TodoData> _toggleTodo(TodoData todo) async {
    try {
      return await _controller.toggleTodo(todo);
    } catch (error) {
      _showError(error);
      return todo;
    }
  }

  Future<TodoData> _toggleSubTodo(TodoData todo, SubTodoData subTodo) async {
    try {
      return await _controller.toggleSubTodo(todo, subTodo);
    } catch (error) {
      _showError(error);
      return todo;
    }
  }

  Future<void> _quickAddSubTodo(TodoData todo) async {
    final subTodo = await showDialog<SubTodoData>(
      context: context,
      builder: (_) => QuickAddSubTodoDialog(
        recordCreatedAt: _settings.recordSubTodoCreatedAt,
      ),
    );
    if (subTodo == null) return;
    await _perform(() => _controller.addSubTodo(todo, subTodo));
  }

  // ---- 资产 ----

  Future<void> _updateProject(ProjectData project) async {
    try {
      await _controller.editProject(project);
    } catch (error) {
      _showError(error);
      rethrow;
    }
  }

  Future<AssetData?> _addAsset(ProjectData project) async {
    final result = await showDialog<AssetDialogResult>(
      context: context,
      builder: (_) => AssetDialog(
        projectId: project.id,
        serverTypes: _settings.serverTypes,
        assetTags: _data.assetTags,
      ),
    );
    final asset = result?.asset;
    if (asset == null) return null;
    try {
      return await _controller.addAsset(asset);
    } catch (error) {
      _showError(error);
      return null;
    }
  }

  Future<AssetData?> _editAsset(AssetData asset) async {
    final result = await showDialog<AssetDialogResult>(
      context: context,
      builder: (_) => AssetDialog(
        asset: asset,
        serverTypes: _settings.serverTypes,
        assetTags: _data.assetTags,
      ),
    );
    final updated = result?.asset;
    if (updated == null) return null;
    try {
      return await _controller.editAsset(asset, updated);
    } catch (error) {
      _showError(error);
      return null;
    }
  }

  Future<void> _deleteAsset(AssetData asset) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除资产',
      content: '确定删除“${asset.name}”吗？',
      confirmLabel: '删除',
    );
    if (confirmed == true) {
      await _perform(() => _controller.deleteAsset(asset));
    }
  }

  void _selectSection(AppSection section) {
    final target = switch (section) {
      AppSection.home => workbenchRoutePath,
      AppSection.todos => todosRoutePath,
      AppSection.projects => projectsRoutePath,
      AppSection.settings => settingsRoutePath,
    };
    if (GoRouterState.of(context).uri.path == target) return;
    context.go(target);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 42,
                      color: cardoryEnsureWhiteContrast(
                        CardoryColors.error,
                        minRatio: 3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '无法加载本地数据',
                      style: TextStyle(
                        fontSize: 18,
                        letterSpacing: -0.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;
    final medium = width >= 720 && width < 1100;
    final section = _currentSection;
    final expandedSidebar = !medium && _sidebarExpanded;

    return _WorkbenchScope(
      state: this,
      child: Scaffold(
        body: DecoratedBox(
          // 扁平化：纯色背景，不再使用渐变。
          decoration: BoxDecoration(color: CardoryColors.gray50),
          child: SafeArea(
            child: Column(
              children: [
                AppTopBar(
                  compact: compact,
                  title: _sectionTitle,
                  onOpenSettings: _openSettings,
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!compact)
                        Sidebar(
                          selected: section,
                          expanded: expandedSidebar,
                          onToggleExpanded: medium
                              ? null
                              : () => setState(
                                  () => _sidebarExpanded = !_sidebarExpanded,
                                ),
                          onSelected: _selectSection,
                        ),
                      Expanded(
                        // Shell 对路由子内容的祖先结构必须恒定：子内容是带
                        // GlobalKey 的内层 Navigator，切换分区时改变它的容器
                        // （滚动 ↔ 直挂）会在过渡帧触发 GlobalKey 重挂异常。
                        // 滚动容器由各分区内容自行承担（见 WorkbenchScaffold）。
                        child: widget.child,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: compact
            ? SectionNavigation(
                key: const Key('bottom-navigation'),
                selected: section,
                compact: true,
                onSelected: _selectSection,
              )
            : null,
      ),
    );
  }

  bool _sidebarExpanded = true;
}

/// 把工作台 Shell 状态暴露给路由内容区的 InheritedWidget：
/// 分区内容与项目详情页通过它获取控制器投影与操作回调。
class _WorkbenchScope extends InheritedWidget {
  const _WorkbenchScope({required this.state, required super.child});

  final _HomePageState state;

  static _HomePageState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WorkbenchScope>()?.state ??
      (throw StateError('WorkbenchSectionContent 必须位于 HomePage Shell 内。'));

  @override
  bool updateShouldNotify(_WorkbenchScope oldWidget) => false;
}

/// 路由内容区入口：由 [createAppRouter] 的 workbenchContentBuilder 调用，
/// 按 [WorkbenchLocation] 渲染对应分区 / 项目详情。
class WorkbenchSectionContent extends StatelessWidget {
  const WorkbenchSectionContent({super.key, required this.location});

  final WorkbenchLocation location;

  @override
  Widget build(BuildContext context) {
    final scope = _WorkbenchScope.of(context);
    switch (location) {
      case WorkbenchToday():
        return _SectionScrollArea(child: _HomeSectionContent(state: scope));
      case WorkbenchTodos():
        return _SectionScrollArea(child: _TodosSectionContent(state: scope));
      case WorkbenchProjects():
        return _SectionScrollArea(child: _ProjectsSectionContent(state: scope));
      case WorkbenchProjectDetail(:final projectId):
        return _ProjectDetailContent(state: scope, projectId: projectId);
      case WorkbenchSettings():
        return _SectionScrollArea(child: _SettingsSectionContent(state: scope));
    }
  }
}

/// 分区内容的滚动容器：滚动由各分区内容自行承担，
/// 保证 Shell 对路由子内容的祖先结构恒定（见 HomePage build 注释）。
class _SectionScrollArea extends StatelessWidget {
  const _SectionScrollArea({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;
    return SingleChildScrollView(
      key: const Key('main-scroll-view'),
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 28,
        compact ? 16 : 24,
        compact ? 16 : 28,
        36,
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1680),
          child: child,
        ),
      ),
    );
  }
}

class _HomeSectionContent extends StatelessWidget {
  const _HomeSectionContent({required this.state});

  final _HomePageState state;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      HeroHeader(onAddProject: state._addProject, onAddTodo: state._addTodo),
      const SizedBox(height: 22),
      Overview(data: state._data),
      const SizedBox(height: 22),
      KanbanBoard(
        data: state._data,
        onAddProject: state._addProject,
        onOpenProject: state._openProject,
        onEditProject: state._editProject,
        onDeleteProject: state._deleteProject,
      ),
      const SizedBox(height: 22),
      ReminderPanel(
        todos: state._data.todos,
        priorityThreshold: state._settings.homeReminderPriorityThreshold,
        onToggleTodo: state._toggleTodo,
        onToggleSubTodo: state._toggleSubTodo,
        onAddSubTodo: state._quickAddSubTodo,
        onOpenTodo: state._openTodo,
      ),
    ],
  );
}

class _TodosSectionContent extends StatelessWidget {
  const _TodosSectionContent({required this.state});

  final _HomePageState state;

  @override
  Widget build(BuildContext context) => TodoPanel(
    todos: state._data.todos,
    onAddTodo: state._addTodo,
    onToggle: state._toggleTodo,
    onToggleSubTodo: state._toggleSubTodo,
    onOpenTodo: state._openTodo,
    onDeleteTodo: state._deleteTodo,
  );
}

class _ProjectsSectionContent extends StatelessWidget {
  const _ProjectsSectionContent({required this.state});

  final _HomePageState state;

  @override
  Widget build(BuildContext context) => ProjectListPanel(
    projects: state._data.projects,
    onAddProject: state._addProject,
    onOpenProject: state._openProject,
    onEditProject: state._editProject,
    onDeleteProject: state._deleteProject,
  );
}

class _SettingsSectionContent extends StatelessWidget {
  const _SettingsSectionContent({required this.state});

  final _HomePageState state;

  @override
  Widget build(BuildContext context) => SettingsPanel(
    settings: state._settings,
    syncStatus: state._syncStatus,
    onSync: state._sync,
    onOpenSettings: state._openSettings,
    onChangePassword: state._changePassword,
    onShowAbout: () => showAboutCardoryDialog(
      context,
      onCheckForUpdate: () => state._checkForUpdate(manual: true),
    ),
  );
}

class _ProjectDetailContent extends StatelessWidget {
  const _ProjectDetailContent({required this.state, required this.projectId});

  final _HomePageState state;
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final projects = state._data.projects;
    ProjectData? project;
    for (final item in projects) {
      if (item.id == projectId) {
        project = item;
        break;
      }
    }
    if (project == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('项目不存在或已被删除。'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => context.go(projectsRoutePath),
              icon: const Icon(Icons.folder_outlined),
              label: const Text('返回项目列表'),
            ),
          ],
        ),
      );
    }
    final current = project;
    return ProjectDetailPage(
      project: current,
      todos: state._data.todos
          .where((todo) => todo.projectId == current.id)
          .toList(),
      assets: state._data.assets
          .where((asset) => asset.projectId == current.id)
          .toList(),
      onUpdateProject: state._updateProject,
      onAddAsset: () => state._addAsset(current),
      onEditAsset: state._editAsset,
      onDeleteAsset: state._deleteAsset,
      onToggleTodo: state._toggleTodo,
      onToggleSubTodo: state._toggleSubTodo,
      onOpenTodo: state._openTodo,
      onAddTodo: state._addProjectTodo,
      onDeleteTodo: state._deleteTodo,
      assetTags: state._data.assetTags,
      onUpdateAssetsTags: (assetIds, tagIds) =>
          state._controller.updateAssetsTags(assetIds, tagIds),
      onAddAssetTag: (tag) => state._controller.addAssetTag(tag),
      onUpdateAssetTag: (tag) => state._controller.updateAssetTag(tag),
      onDeleteAssetTag: (tagId) => state._controller.deleteAssetTag(tagId),
      attachmentStore: state._attachmentStore,
      renameAttachmentsOnUpload: state._settings.renameAttachmentsOnUpload,
      keepAttachmentExtensionOnRename:
          state._settings.keepAttachmentExtensionOnRename,
    );
  }
}
