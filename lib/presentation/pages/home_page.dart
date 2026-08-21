import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../application/attachment_repository.dart';
import '../../application/cardory_repository.dart';
import '../../application/sync_status.dart';
import '../../application/workspace_controller.dart';
import '../../application/workspace_controller_factory.dart';
import '../../application/workspace_settings_service.dart';
import '../../domain/cardory_models.dart';
import '../../application/sync_credentials.dart';
import '../../sync/sync_credentials.dart' show VaultCredentialStore;
import '../app_section.dart';
import '../cardory_theme.dart';
import '../dialogs/security_dialogs.dart';
import '../settings_models.dart';
import '../widgets/section_nav.dart';
import '../widgets/sidebar.dart';
import 'asset_dialog.dart';
import 'dashboard.dart';
import 'project_page.dart';
import 'settings_page.dart';
import 'task_dialogs.dart';

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
  });

  final WorkspaceControllerFactory controllerFactory;
  final VaultRepository vaultRepository;
  final SyncCredentialStore credentialStore;
  final VaultCredentialStore vaultCredentialStore;
  final ValueChanged<AppSettings> onSettingsChanged;
  final CardoryLoadResult? initialResult;
  final AttachmentRepositoryFactory attachmentRepositoryFactory;

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
    final choice = await showDialog<SyncConflictChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('同步冲突'),
        content: SizedBox(
          width: 460,
          child: conflicts.isEmpty
              ? const Text('本地和云端都存在未同步的修改。请选择要保留的数据版本。')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('发现 ${conflicts.length} 项差异：'),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: conflicts.length,
                        itemBuilder: (_, index) {
                          final item = conflicts[index];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              item.side == SyncConflictSide.local
                                  ? Icons.computer
                                  : Icons.cloud_outlined,
                            ),
                            title: Text(item.title),
                            subtitle: Text('${item.category} · ${item.side == SyncConflictSide.local ? '本地有变化' : '远端新增'}'),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(SyncConflictChoice.cancel),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(SyncConflictChoice.manualMerge),
            child: const Text('手动合并'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(SyncConflictChoice.keepRemote),
            child: const Text('使用远端'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(SyncConflictChoice.keepLocal),
            child: const Text('保留本地'),
          ),
        ],
      ),
    );
    if (choice == null || choice == SyncConflictChoice.cancel || !mounted) return;

    Map<String, SyncConflictSide> itemChoices = const {};
    if (choice == SyncConflictChoice.manualMerge) {
      final selected = await _chooseManualMerge(conflicts);
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

  Future<Map<String, SyncConflictSide>?> _chooseManualMerge(
    List<SyncConflictItem> conflicts,
  ) async {
    final choices = <String, SyncConflictSide>{
      for (final item in conflicts) item.id: item.side,
    };
    return showDialog<Map<String, SyncConflictSide>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('手动合并'),
          content: SizedBox(
            width: 460,
            child: ListView(
              shrinkWrap: true,
              children: conflicts.map((item) {
                final selected = choices[item.id] ?? item.side;
                return ListTile(
                  title: Text(item.title),
                  subtitle: Text(item.category),
                  trailing: DropdownButton<SyncConflictSide>(
                    value: selected,
                    items: const [
                      DropdownMenuItem(value: SyncConflictSide.local, child: Text('本地')),
                      DropdownMenuItem(value: SyncConflictSide.remote, child: Text('远端')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => choices[item.id] = value);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, choices), child: const Text('应用合并')),
          ],
        ),
      ),
    );
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除项目'),
        content: Text('确定删除“${project.title}”吗？关联待办和资产也会一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除待办'),
        content: Text('确定删除“${todo.title}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
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
      await _controller.updateProject(project);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除资产'),
        content: Text('确定删除“${asset.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
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
          dataPath: _dataPath,
          syncStatus: _syncStatus,
          onSync: _sync,
          onOpenSettings: _openSettings,
          onChangePassword: _changePassword,
          onRestoreBackup: _restoreBackupFromSettings,
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
                      color: CardoryColors.error,
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              CardoryColors.gray50,
              CardoryColors.gray100,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
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
                                    duration: const Duration(milliseconds: 240),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
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
