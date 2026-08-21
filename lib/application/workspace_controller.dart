import '../domain/cardory_models.dart';
import 'attachment_repository.dart';
import 'cardory_repository.dart';
import 'sync_status.dart';
import 'widget_data_service.dart';
import 'workspace_settings_service.dart';
import 'workspace_sync_service.dart';
import 'workspace_mutation_service.dart';

/// 独立于界面组件管理工作区状态与业务事务。
class WorkspaceController implements WorkspaceObservable {
  WorkspaceController({
    required this.repository,
    required this.vaultRepository,
    required this.settingsService,
    required this.syncService,
    required this.attachmentRepositoryFactory,
    WidgetDataService widgetDataService = const NullWidgetDataService(),
  }) : _widgetDataService = widgetDataService {
    syncService.addListener(_notifySyncChanged);
  }

  final WorkspaceRepository repository;
  final VaultRepository vaultRepository;
  final WorkspaceSettingsService settingsService;
  final WorkspaceSyncService syncService;
  final AttachmentRepositoryFactory attachmentRepositoryFactory;
  final WidgetDataService _widgetDataService;
  static const _mutations = WorkspaceMutationService();
  final _listeners = <WorkspaceListener>{};

  CardoryData _data = const CardoryData.empty();
  AppSettings _settings = const AppSettings();
  String _dataPath = '';
  String? _error;
  bool _loading = true;
  bool _recoveredFromBackup = false;
  AttachmentRepository? _attachmentRepository;

  CardoryData get data => _data;
  AppSettings get settings => _settings;
  String get dataPath => _dataPath;
  String? get error => _error;
  bool get loading => _loading;
  bool get recoveredFromBackup => _recoveredFromBackup;
  AttachmentRepository? get attachmentRepository => _attachmentRepository;
  SyncStatus get syncStatus => syncService.status;

  Future<void> initialize([CardoryLoadResult? initialResult]) async {
    _loading = true;
    _error = null;
    _notifyListeners();
    try {
      await applyLoadResult(initialResult ?? await repository.load());
    } catch (error) {
      _loading = false;
      _error = error.toString();
      _notifyListeners();
    }
  }

  Future<void> reload() => initialize();

  Future<void> applyLoadResult(CardoryLoadResult result) async {
    final attachments = attachmentRepositoryFactory(result.path);
    var data = result.data;
    var migrated = false;
    final projects = <ProjectData>[];
    for (final project in data.projects) {
      final migratedAttachments = <AttachmentData>[];
      for (final attachment in project.attachments) {
        if (attachment.needsMigration) {
          migratedAttachments.add(await attachments.migrateLegacy(attachment));
          migrated = true;
        } else {
          migratedAttachments.add(attachment);
        }
      }
      projects.add(project.copyWith(attachments: migratedAttachments));
    }
    if (migrated) {
      data = data.copyWith(projects: projects);
      await repository.save(data, result.settings);
    }

    _attachmentRepository = attachments;
    await attachments.prune(
      data.projects
          .expand((project) => project.attachments)
          .map((attachment) => attachment.storageKey)
          .where((key) => key.isNotEmpty)
          .toSet(),
    );
    _data = data;
    _settings = result.settings;
    _dataPath = result.path;
    _recoveredFromBackup = result.recoveredFromBackup;
    _loading = false;
    _error = null;
    _notifyListeners();
    _updateWidget();
  }

  Future<void> saveData(CardoryData data) async {
    final previous = _data;
    _data = data;
    _notifyListeners();
    try {
      await repository.save(data, _settings);
      _updateWidget();
    } catch (_) {
      _data = previous;
      _notifyListeners();
      rethrow;
    }
  }

  Future<void> applySettings(
    AppSettings settings, {
    SyncCredentialUpdate credentials = const SyncCredentialUpdate(),
  }) async {
    // 记录本地配置最近一次修改时间，供配置云同步比较新旧使用。
    final withTimestamp = settings.copyWith(
      lastConfigUpdatedAt: DateTime.now().toUtc(),
    );
    await settingsService.apply(withTimestamp, credentials: credentials);
    _settings = withTimestamp;
    _notifyListeners();
  }

  Future<void> synchronize() async {
    _settings = await syncService.synchronize(_settings);
    _notifyListeners();
    if (syncService.status.requiresReload) {
      await reload();
    }
  }

  Future<void> resolveSyncConflict(
    SyncConflictChoice choice, {
    Map<String, SyncConflictSide> itemChoices = const {},
  }) async {
    _settings = await syncService.resolveConflict(
      choice,
      itemChoices: itemChoices,
    );
    _notifyListeners();
    if (syncService.status.requiresReload) {
      await reload();
    }
  }

  Future<void> changePassword(String currentPassword, String newPassword) =>
      vaultRepository.changePassword(currentPassword, newPassword);

  Future<CardoryLoadResult> restoreBackup(
    List<int> bytes,
    String password,
  ) async {
    final result = await vaultRepository.restoreFromBackup(
      bytes,
      password,
    );
    await applyLoadResult(result);
    return result;
  }

  Future<void> addProject(ProjectData project) async {
    try {
      await saveData(_mutations.addProject(_data, project));
    } catch (_) {
      await _deleteAttachments(project.attachments);
      rethrow;
    }
  }

  Future<void> updateProject(ProjectData project) => editProject(project);

  Future<void> editProject(ProjectData project) async {
    final original = _data.projects.firstWhere(
      (item) => item.id == project.id,
      orElse: () => throw StateError('项目不存在：${project.id}'),
    );
    final result = _mutations.editProject(_data, original, project);
    try {
      await _saveDataWithAttachmentDeletes(
        result.data,
        result.removedAttachments,
      );
      await _deleteAttachments(result.removedAttachments);
    } catch (_) {
      await _deleteAttachments(result.addedAttachments);
      rethrow;
    }
  }

  Future<void> deleteProject(String projectId) async {
    final result = _mutations.deleteProject(_data, projectId);
    await _saveDataWithAttachmentDeletes(result.data, result.attachments);
    await _deleteAttachments(result.attachments);
  }

  Future<void> addTodo(TodoData todo) =>
      saveData(_mutations.addTodo(_data, todo));

  Future<void> updateTodo(TodoData todo) =>
      saveData(_mutations.updateTodo(_data, todo));

  Future<void> deleteTodo(String todoId) =>
      saveData(_mutations.deleteTodo(_data, todoId));

  Future<TodoData> toggleTodo(TodoData todo) async {
    final updated = _mutations.toggleTodo(todo);
    await updateTodo(updated);
    return updated;
  }

  Future<TodoData> toggleSubTodo(TodoData todo, SubTodoData subTodo) async {
    final updated = _mutations.toggleSubTodo(todo, subTodo);
    await updateTodo(updated);
    return updated;
  }

  Future<void> addSubTodo(TodoData todo, SubTodoData subTodo) =>
      updateTodo(todo.copyWith(subTodos: [...todo.subTodos, subTodo]));

  Future<AssetData> addAsset(AssetData asset) async {
    final recorded = _mutations.recordNewAsset(asset);
    await saveData(_data.copyWith(assets: [..._data.assets, recorded]));
    return recorded;
  }

  Future<AssetData> editAsset(AssetData original, AssetData updated) async {
    final result = _mutations.editAsset(_data, original, updated);
    await saveData(result.data);
    return result.recorded;
  }

  Future<void> deleteAsset(AssetData asset) async {
    await saveData(_mutations.deleteAsset(_data, asset));
  }

  Future<AssetTag> addAssetTag(AssetTag tag) async {
    await saveData(_data.copyWith(assetTags: [..._data.assetTags, tag]));
    return tag;
  }

  Future<AssetTag> updateAssetTag(AssetTag tag) async {
    await saveData(
      _data.copyWith(
        assetTags: [
          for (final item in _data.assetTags)
            if (item.id == tag.id) tag else item,
        ],
      ),
    );
    return tag;
  }

  Future<void> deleteAssetTag(String tagId) async {
    await saveData(
      _data.copyWith(
        assetTags: _data.assetTags
            .where((item) => item.id != tagId)
            .toList(),
        assets: _data.assets
            .map((asset) {
              if (!asset.tagIds.contains(tagId)) return asset;
              final remaining = asset.tagIds
                  .where((id) => id != tagId)
                  .toList();
              return asset.copyWith(
                tagIds: remaining,
                clearTagIds: remaining.isEmpty,
              );
            })
            .toList(),
      ),
    );
  }

  Future<void> updateAssetsTags(
    Set<String> assetIds,
    Set<String> tagIds,
  ) async {
    await saveData(
      _data.copyWith(
        assets: _data.assets
            .map((asset) {
              if (!assetIds.contains(asset.id)) return asset;
              return asset.copyWith(
                tagIds: tagIds.toList(),
                clearTagIds: tagIds.isEmpty,
              );
            })
            .toList(),
      ),
    );
  }

  Future<void> _saveDataWithAttachmentDeletes(
    CardoryData data,
    Iterable<AttachmentData> attachments,
  ) async {
    final keys = attachments
        .map((attachment) => attachment.storageKey)
        .where((key) => key.isNotEmpty)
        .toSet();
    if (keys.isEmpty) return saveData(data);

    final previousSettings = _settings;
    final updatedSettings = _settings.copyWith(
      pendingAttachmentDeletes: {
        ..._settings.pendingAttachmentDeletes,
        ...keys,
      }.toList(),
    );
    await repository.saveSettings(updatedSettings);
    _settings = updatedSettings;
    try {
      await saveData(data);
    } catch (_) {
      _settings = previousSettings;
      try {
        await repository.saveSettings(previousSettings);
      } catch (_) {
        // 下次启动会保留一份更完整的删除任务清单，这是安全的：
        // 同步绝不会删除仍被元数据引用的键。
      }
      _notifyListeners();
      rethrow;
    }
  }

  Future<void> _deleteAttachments(Iterable<AttachmentData> attachments) async {
    final store = _attachmentRepository;
    if (store == null) return;
    for (final attachment in attachments) {
      try {
        await store.delete(attachment);
      } catch (_) {
        // 以元数据为准；孤儿清理可另行重试。
      }
    }
  }

  void _updateWidget() {
    _widgetDataService.updateWidgetData(_data).onError((_, _) {});
  }

  void _notifySyncChanged() => _notifyListeners();

  @override
  void addListener(WorkspaceListener listener) => _listeners.add(listener);

  @override
  void removeListener(WorkspaceListener listener) =>
      _listeners.remove(listener);

  void _notifyListeners() {
    for (final listener in List<WorkspaceListener>.of(_listeners)) {
      listener();
    }
  }

  @override
  void dispose() {
    syncService
      ..removeListener(_notifySyncChanged)
      ..dispose();
    _listeners.clear();
  }
}
