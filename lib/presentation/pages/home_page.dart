import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../application/workspace_controller.dart';
import '../../application/workspace_controller_factory.dart';
import '../../application/workspace_settings_service.dart';
import '../../domain/attachment_repository.dart';
import '../../domain/cardory_models.dart';
import '../../domain/cardory_repository.dart';
import '../../domain/sync_credentials.dart';
import '../../domain/sync_status.dart';
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

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controllerFactory,
    required this.vaultRepository,
    required this.credentialStore,
    required this.vaultCredentialStore,
    required this.onSettingsChanged,
    this.initialResult,
    required this.attachmentRepositoryFactory,
    this.connectionTester,
  });

  final WorkspaceControllerFactory controllerFactory;
  final VaultRepository vaultRepository;
  final SyncCredentialStore credentialStore;
  final VaultCredentialStore vaultCredentialStore;
  final ValueChanged<AppSettings> onSettingsChanged;
  final CardoryLoadResult? initialResult;
  final AttachmentRepositoryFactory attachmentRepositoryFactory;
  final Future<void> Function(
    AppSettings,
    SyncCredentials,
  )? connectionTester;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _sidebarExpanded = true;
  AppSection _section = AppSection.home;
  late final WorkspaceController _controller;

  CardoryData get _data => _controller.data;
  AppSettings get _settings => _controller.settings;
  String get _dataPath => _controller.dataPath;
  String? get _error => _controller.error;
  bool get _loading => _controller.loading;
  SyncStatus get _syncStatus => _controller.syncStatus;
  AttachmentRepository? get _attachmentStore =>
      _controller.attachmentRepository;

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

  static final GithubUpdateService _updateService = GithubUpdateService();

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
    final comparison = compareVersions(current, info.version);
    if (comparison == VersionComparison.newer) {
      await showUpdateDialog(
        context,
        release: info,
        currentVersion: current,
      );
    } else if (manual) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已是最新版本（$current）。')));
    }
  }

  /// 获取本地应用版本号（读取一次后缓存）。
  Future<String> _currentAppVersion() async {
    if (_currentVersion != null) return _currentVersion!;
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
    } catch (_) {
      _currentVersion = '0.0.0';
    }
    return _currentVersion!;
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

  void _showError(
    Object error, {
    String message = '操作未完成，请检查设置后重试。',
  }) {
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
    final conflicts = _syncStatus.conflicts;
    final choice = await showSyncConflictDialog(context, conflicts);
    if (choice == null || choice == SyncConflictChoice.cancel || !mounted) return;

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
          SnackBar(content: Text(status.summary?.displayText ?? status.message ?? '同步完成')),
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

  Future<void> _restoreBackupFromSettings() async {
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['cardory'],
        allowMultiple: false,
        withData: true,
      );
      if (selected == null || !mounted) return;
      final file = selected.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const CardoryStorageException('无法读取所选备份文件。');
      }
      final password = await showDialog<String>(
        context: context,
        builder: (_) => BackupPasswordDialog(fileName: file.name),
      );
      if (password == null || !mounted) return;
      final result = await _controller.restoreBackup(
        bytes,
        password,
      );
      await widget.vaultCredentialStore.writePassword(password);
      if (!mounted) return;
      widget.onSettingsChanged(result.settings);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('数据已从备份恢复。')));
    } catch (error) {
      _showError(error, message: '恢复数据失败，请检查备份文件和密码。');
    }
  }

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

  Future<void> _updateProject(ProjectData project) async {
    try {
      await _controller.editProject(project);
    } catch (error) {
      _showError(error);
      rethrow;
    }
  }

  Future<void> _openProject(ProjectData project) async {
    final current = _data.projects.firstWhere(
      (item) => item.id == project.id,
      orElse: () => project,
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectDetailPage(
          project: current,
          todos: _data.todos
              .where((todo) => todo.projectId == current.id)
              .toList(),
          assets: _data.assets
              .where((asset) => asset.projectId == current.id)
              .toList(),
          onUpdateProject: _updateProject,
          onAddAsset: () => _addAsset(current),
          onEditAsset: _editAsset,
          onDeleteAsset: _deleteAsset,
          onToggleTodo: _toggleTodo,
          onToggleSubTodo: _toggleSubTodo,
          onOpenTodo: _openTodo,
          onAddTodo: _addProjectTodo,
          onDeleteTodo: _deleteTodo,
          assetTags: _data.assetTags,
          onUpdateAssetsTags: (assetIds, tagIds) =>
              _controller.updateAssetsTags(assetIds, tagIds),
          onAddAssetTag: (tag) => _controller.addAssetTag(tag),
          onUpdateAssetTag: (tag) => _controller.updateAssetTag(tag),
          onDeleteAssetTag: (tagId) => _controller.deleteAssetTag(tagId),
          attachmentStore: _attachmentStore,
          renameAttachmentsOnUpload: _settings.renameAttachmentsOnUpload,
          keepAttachmentExtensionOnRename:
              _settings.keepAttachmentExtensionOnRename,
        ),
      ),
    );
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

  Widget _buildContent() {
    switch (_section) {
      case AppSection.home:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HeroHeader(onAddProject: _addProject, onAddTodo: _addTodo),
            const SizedBox(height: 22),
            Overview(data: _data),
            const SizedBox(height: 22),
            KanbanBoard(
              data: _data,
              onAddProject: _addProject,
              onOpenProject: _openProject,
              onEditProject: _editProject,
              onDeleteProject: _deleteProject,
            ),
            const SizedBox(height: 22),
            ReminderPanel(
              todos: _data.todos,
              priorityThreshold: _settings.homeReminderPriorityThreshold,
              onToggleTodo: _toggleTodo,
              onToggleSubTodo: _toggleSubTodo,
              onAddSubTodo: _quickAddSubTodo,
              onOpenTodo: _openTodo,
            ),
          ],
        );
      case AppSection.todos:
        return TodoPanel(
          todos: _data.todos,
          onAddTodo: _addTodo,
          onToggle: _toggleTodo,
          onToggleSubTodo: _toggleSubTodo,
          onOpenTodo: _openTodo,
          onDeleteTodo: _deleteTodo,
        );
      case AppSection.projects:
        return ProjectListPanel(
          projects: _data.projects,
          onAddProject: _addProject,
          onOpenProject: _openProject,
          onEditProject: _editProject,
          onDeleteProject: _deleteProject,
        );
      case AppSection.settings:
        return SettingsPanel(
          settings: _settings,
          syncStatus: _syncStatus,
          onSync: _sync,
          onOpenSettings: _openSettings,
          onChangePassword: _changePassword,
          onRestoreBackup: _restoreBackupFromSettings,
          onShowAbout: () => showAboutCardoryDialog(
            context,
            onCheckForUpdate: () => _checkForUpdate(manual: true),
          ),
        );
    }
  }

  String get _sectionTitle => switch (_section) {
    AppSection.home => '看板',
    AppSection.todos => '待办事项',
    AppSection.projects => '项目',
    AppSection.settings => '设置',
  };

  void _selectSection(AppSection section) {
    if (section == _section) return;
    setState(() => _section = section);
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

    return Scaffold(
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
                        selected: _section,
                        expanded: !medium && _sidebarExpanded,
                        onToggleExpanded: medium
                            ? null
                            : () => setState(
                                () => _sidebarExpanded = !_sidebarExpanded,
                              ),
                        onSelected: _selectSection,
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
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
                                  constraints: const BoxConstraints(
                                    maxWidth: 1680,
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: cardoryAnimDuration(
                                      context,
                                      CardoryMotion.base,
                                    ),
                                    switchInCurve: CardoryMotion.outCubic,
                                    switchOutCurve: CardoryMotion.inCubic,
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                          opacity: animation,
                                          child: SlideTransition(
                                            position: Tween<Offset>(
                                              begin: const Offset(0.025, 0),
                                              end: Offset.zero,
                                            ).animate(animation),
                                            child: child,
                                          ),
                                        ),
                                    child: KeyedSubtree(
                                      key: ValueKey(_section),
                                      child: _buildContent(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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
              selected: _section,
              compact: true,
              onSelected: _selectSection,
            )
          : null,
    );
  }
}
