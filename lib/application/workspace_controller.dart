import 'package:flutter/foundation.dart';

import '../domain/calendar_push_registry.dart';
import '../domain/calendar_sync.dart';
import '../domain/cardory_models.dart';
import '../domain/attachment_repository.dart';
import '../domain/cardory_repository.dart';
import '../domain/dependency_schedule.dart';
import '../domain/due_reminder_service.dart';
import '../domain/schedule_queries.dart';
import '../domain/sync_status.dart';
import '../services/system_calendar_service.dart';
import '../domain/widget_data_service.dart';
import '../domain/workspace_sync_service.dart';
import 'row_level_workspace_store.dart';
import 'workspace_mutation_service.dart';
import 'workspace_settings_service.dart';

/// 独立于界面组件管理工作区状态与业务事务。
///
/// 读取侧：内存中的 [CardoryData] 是数据库的投影，写入成功后从数据库回读；
/// 写入侧：全部业务写入经 [RowLevelWorkspaceStore] 以行级单事务提交，
/// 不再构建整包 CardoryData 快照（快照写入仅保留给同步导入路径）。
class WorkspaceController implements WorkspaceObservable, Listenable {
  WorkspaceController({
    required this.repository,
    required this.vaultRepository,
    required this.settingsService,
    required this.syncService,
    required this.attachmentRepositoryFactory,
    this.rowLevelStore,
    WidgetDataService widgetDataService = const NullWidgetDataService(),
    // ignore: prefer_initializing_formals —— 命名参数不能以下划线开头。
    DueReminderService dueReminderService = const NullDueReminderService(),
    SystemCalendarService? systemCalendarService,
    CalendarPushRegistry? calendarPushRegistry,
    // ignore: prefer_initializing_formals —— 命名参数不能以下划线开头，无法用 this._widgetDataService。
  }) : _widgetDataService = widgetDataService,
       // ignore: prefer_initializing_formals —— 命名参数不能以下划线开头。
       _dueReminderService = dueReminderService,
       // ignore: prefer_initializing_formals —— 命名参数不能以下划线开头。
       _systemCalendarService = systemCalendarService,
       // ignore: prefer_initializing_formals —— 命名参数不能以下划线开头。
       _calendarPushRegistry = calendarPushRegistry {
    syncService.addListener(_notifySyncChanged);
  }

  final WorkspaceRepository repository;
  final VaultRepository vaultRepository;
  final WorkspaceSettingsService settingsService;
  final WorkspaceSyncService syncService;
  final AttachmentRepositoryFactory attachmentRepositoryFactory;
  final RowLevelWorkspaceStore? rowLevelStore;
  final WidgetDataService _widgetDataService;
  final DueReminderService _dueReminderService;

  /// 系统日历服务与推送登记表：null 时跳过日历回收对账（测试/未启用）。
  final SystemCalendarService? _systemCalendarService;
  final CalendarPushRegistry? _calendarPushRegistry;

  /// 用户拒绝通知权限后本会话内不再重复请求（可去系统设置里重新开启）。
  bool _dueReminderPermissionDenied = false;
  static const _mutations = WorkspaceMutationService();
  final _listeners = <WorkspaceListener>{};

  CardoryData _data = const CardoryData.empty();
  AppSettings _settings = const AppSettings();
  String _dataPath = '';
  String? _error;
  bool _loading = true;
  bool _recoveredFromBackup = false;
  AttachmentRepository? _attachmentRepository;

  /// 行级写入存储；未注入时任何业务写入都会抛错，防止界面悄悄退化回
  /// 整包快照写入。
  RowLevelWorkspaceStore get _rowLevel {
    final store = rowLevelStore;
    if (store == null) {
      throw StateError('行级写入存储未注入，无法执行业务写入。');
    }
    return store;
  }

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
    // SQLCipher 保险库（破坏性版本）不存在旧版 base64 内嵌附件：附件一律以
    // 加密文件落盘并登记 storageKey，因此这里不再有 legacyFileBytes 迁移分支。
    final data = result.data;

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
    await _runDueReminders();
    await _reconcileSystemCalendar();
  }

  /// 以数据库回读结果刷新内存投影（不触发附件迁移/清理等一次性逻辑）。
  ///
  /// 回读失败只说明投影刷新不可用——此时数据库已成功提交，保留刚写入的
  /// 内存快照（与提交内容一致）比回滚到更旧的状态更安全，因此静默继续。
  Future<void> _refreshFromRepository() async {
    try {
      final refreshed = await repository.load();
      _data = refreshed.data;
      _settings = refreshed.settings;
      _dataPath = refreshed.path;
      _notifyListeners();
    } catch (_) {
      // 见上方注释：静默保留已提交的本地投影。
    }
  }

  /// 行级写入成功后的统一收尾：回读投影 + 刷新桌面小组件摘要 + 刷新到期提醒。
  Future<void> _afterWrite() async {
    await _refreshFromRepository();
    _updateWidget();
    await _runDueReminders();
    await _reconcileSystemCalendar();
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
    await _runDueReminders();
    await _reconcileSystemCalendar();
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

  // ---- 项目 ----

  Future<void> addProject(ProjectData project) async {
    try {
      await _rowLevel.addProject(project);
    } catch (_) {
      await _deleteAttachments(project.attachments);
      rethrow;
    }
    await _afterWrite();
  }

  Future<void> editProject(ProjectData project) async {
    final original = _data.projects.firstWhere(
      (item) => item.id == project.id,
      orElse: () => throw StateError('项目不存在：${project.id}'),
    );
    final removed = original.attachments
        .where((item) => !project.attachments.any((a) => a.id == item.id))
        .toList();
    final added = project.attachments
        .where((item) => !original.attachments.any((a) => a.id == item.id))
        .toList();
    final restoreSettings = await _queueAttachmentDeletes(
      removed.map((item) => item.storageKey),
    );
    try {
      await _rowLevel.updateProject(original, project);
      await _deleteAttachments(removed);
    } catch (_) {
      await restoreSettings();
      await _deleteAttachments(added);
      rethrow;
    }
    await _afterWrite();
  }

  Future<void> deleteProject(String projectId) async {
    final attachments = _data.projects
        .where((project) => project.id == projectId)
        .expand((project) => project.attachments)
        .toList();
    final restoreSettings = await _queueAttachmentDeletes(
      attachments.map((item) => item.storageKey),
    );
    try {
      await _rowLevel.deleteProject(projectId);
    } catch (_) {
      await restoreSettings();
      rethrow;
    }
    await _deleteAttachments(attachments);
    await _afterWrite();
  }

  /// 看板拖拽排序：按传入顺序写入项目阶段与 sortOrder。
  Future<void> reorderProjects(List<ProjectData> orderedProjects) async {
    await _rowLevel.reorderProjects(orderedProjects);
    await _afterWrite();
  }

  // ---- 待办与子待办 ----

  Future<void> addTodo(TodoData todo) async {
    await _rowLevel.addTodo(todo);
    await _afterWrite();
  }

  Future<void> updateTodo(TodoData todo) async {
    final original = _data.todos.firstWhere(
      (item) => item.id == todo.id,
      orElse: () => throw StateError('待办不存在：${todo.id}'),
    );
    await _rowLevel.updateTodo(original, todo);
    // 日期变更会改变对后继任务的约束，触发依赖自动排期传播。
    if (original.startDate != todo.startDate ||
        original.endDate != todo.endDate) {
      await _applyDependencySchedule({todo.id});
    }
    await _afterWrite();
  }

  Future<void> deleteTodo(String todoId) async {
    await _rowLevel.deleteTodo(todoId);
    await _afterWrite();
  }

  Future<TodoData> toggleTodo(TodoData todo) async {
    final updated = _mutations.toggleTodo(todo);
    await _rowLevel.setTodoDone(todo.id, done: updated.done);
    // 前置任务完成：后继任务自动排期（撤销完成不重排）。
    if (updated.done && !todo.done) {
      await _applyDependencySchedule({todo.id});
    }
    await _afterWrite();
    return updated;
  }

  /// 依赖约束传播：seed（完成/改期的任务）沿后继链自动排期，
  /// 逐条写回行级存储（各自进入同步通道）。失败只留日志不阻断保存。
  Future<void> _applyDependencySchedule(Set<String> seedTodoIds) async {
    try {
      // 传播前回读投影，确保种子任务刚写入的新日期/完成状态参与约束。
      await _refreshFromRepository();
      final updates = propagateDependencySchedule(
        todos: _data.todos,
        dependencies: await _rowLevel.loadDependencies(),
        seedTodoIds: seedTodoIds,
      );
      for (final update in updates) {
        await _rowLevel.updateTodo(update.original, update.updated);
      }
    } catch (error) {
      debugPrint('WorkspaceController.applyDependencySchedule failed: $error');
    }
  }

  Future<TodoData> toggleSubTodo(TodoData todo, SubTodoData subTodo) async {
    final updated = _mutations.toggleSubTodo(todo, subTodo);
    final toggled = updated.subTodos.firstWhere(
      (item) => item.id == subTodo.id,
    );
    await _rowLevel.setSubTodoDone(subTodo.id, done: toggled.done);
    await _afterWrite();
    return updated;
  }

  Future<void> addSubTodo(TodoData todo, SubTodoData subTodo) async {
    await _rowLevel.addSubTodo(todo, subTodo);
    await _afterWrite();
  }

  // ---- 资产与标签 ----

  Future<AssetData> addAsset(AssetData asset) async {
    final recorded = _mutations.recordNewAsset(asset);
    await _rowLevel.addAsset(recorded);
    await _afterWrite();
    return recorded;
  }

  Future<AssetData> editAsset(AssetData original, AssetData updated) async {
    final recorded = _mutations.recordAssetUpdate(original, updated);
    await _rowLevel.editAsset(original, recorded);
    await _afterWrite();
    return recorded;
  }

  Future<void> deleteAsset(AssetData asset) async {
    await _rowLevel.deleteAsset(asset.id);
    await _afterWrite();
  }

  Future<AssetTag> addAssetTag(AssetTag tag) async {
    await _rowLevel.addAssetTag(tag);
    await _afterWrite();
    return tag;
  }

  Future<AssetTag> updateAssetTag(AssetTag tag) async {
    await _rowLevel.updateAssetTag(tag);
    await _afterWrite();
    return tag;
  }

  Future<void> deleteAssetTag(String tagId) async {
    await _rowLevel.deleteAssetTag(tagId);
    await _afterWrite();
  }

  Future<void> updateAssetsTags(
    Set<String> assetIds,
    Set<String> tagIds,
  ) async {
    await _rowLevel.updateAssetsTags(assetIds, tagIds);
    await _afterWrite();
  }

  // ---- 附件文件清理 ----

  /// 把待删除的附件存储键写入设置队列（同步侧据其清理云端残留），
  /// 返回失败回滚用的恢复函数。
  Future<Future<void> Function()> _queueAttachmentDeletes(
    Iterable<String> keys,
  ) async {
    final storageKeys = keys.where((key) => key.isNotEmpty).toSet();
    if (storageKeys.isEmpty) return () async {};
    final previousSettings = _settings;
    final updatedSettings = previousSettings.copyWith(
      pendingAttachmentDeletes: {
        ...previousSettings.pendingAttachmentDeletes,
        ...storageKeys,
      }.toList(),
    );
    await repository.saveSettings(updatedSettings);
    _settings = updatedSettings;
    return () async {
      _settings = previousSettings;
      try {
        await repository.saveSettings(previousSettings);
      } catch (_) {
        // 下次启动会保留一份更完整的删除任务清单，这是安全的：
        // 同步绝不会删除仍被元数据引用的键。
      }
      _notifyListeners();
    };
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
    _widgetDataService.updateWidgetData(_data).onError((e, _) {
      // 小组件更新失败不影响主流程，但留日志便于排查
      debugPrint('WorkspaceController.updateWidgetData failed: $e');
    });
  }

  /// 扫描资产到期并驱动系统通知（解锁加载、数据写入、设置变更后调用）。
  ///
  /// 提醒失败绝不阻断主流程；未开启时清空全部预约通知。
  Future<void> _runDueReminders() async {
    try {
      if (!_settings.dueRemindersEnabled) {
        await _dueReminderService.cancelAll();
        return;
      }
      final today = localDayKey(DateTime.now());
      final horizon = today.add(Duration(days: _settings.dueReminderLeadDays));
      List<AssetDueEntry> entriesIn(DateTime start, DateTime end) =>
          assetDueEntries(
            _data.assets,
            _settings.assetTemplates,
            bounds: (start, end),
          );
      final notifiedKeys = await _dueReminderService.loadNotifiedKeys();
      final plan = planDueReminders(
        overdue: entriesIn(
          today.subtract(const Duration(days: 3)),
          today.subtract(const Duration(days: 1)),
        ),
        dueToday: entriesIn(today, today),
        upcoming: entriesIn(today.add(const Duration(days: 1)), horizon),
        notifiedKeys: notifiedKeys,
      );
      if (!_dueReminderPermissionDenied &&
          (plan.immediate.isNotEmpty || plan.scheduled.isNotEmpty)) {
        final granted = await _dueReminderService.ensurePermissions();
        if (!granted) {
          _dueReminderPermissionDenied = true;
          return;
        }
      }
      await _dueReminderService.cancelAll();
      for (final payload in plan.immediate) {
        await _dueReminderService.notify(payload);
      }
      for (final reminder in plan.scheduled) {
        await _dueReminderService.schedule(reminder);
      }
      await _dueReminderService.saveNotifiedKeys(plan.nextState);
    } catch (error) {
      // 提醒是附加能力：扫描或通知失败只留日志，不影响数据操作。
      debugPrint('WorkspaceController.runDueReminders failed: $error');
    }
  }

  /// 对账系统日历推送登记：回收失效日程，跟随到期日/标题变更删旧建新。
  ///
  /// 加载后对账天然覆盖多设备同步删除资产的场景（数据回读发现登记失效
  /// 即回收）。任何失败只留日志，不影响数据操作；事件删除失败时保留
  /// 登记下次重试，替换时新建失败则仅移除登记（可在日历页手动重推）。
  Future<void> _reconcileSystemCalendar() async {
    final calendarService = _systemCalendarService;
    final registry = _calendarPushRegistry;
    if (calendarService == null || registry == null) return;
    try {
      final entries = await registry.load();
      if (entries.isEmpty) return;
      final plan = planCalendarSync(
        registry: entries,
        currentDues: assetDueEntries(_data.assets, _settings.assetTemplates),
      );
      for (final eventId in plan.eventIdsToDelete) {
        await calendarService.deleteEvent(eventId);
      }
      for (final replacement in plan.replacements) {
        final deleted = await calendarService.deleteEvent(
          replacement.oldEventId,
        );
        if (!deleted) {
          // 旧事件删除失败：保留原登记，下次对账重试整条替换。
          final original = entries[replacement.key];
          if (original != null) {
            plan.nextRegistry[replacement.key] = original;
          }
          continue;
        }
        final day = replacement.due.date;
        final created = await calendarService.createEvent(
          title: replacement.due.title,
          start: day,
          end: day.add(const Duration(days: 1)),
          note: '${replacement.due.assetName} · ${replacement.due.fieldLabel}',
        );
        if (created.success && created.eventId != null) {
          plan.nextRegistry[replacement.key] = CalendarPushRecord(
            eventId: created.eventId!,
            date: day.toIso8601String().substring(0, 10),
            title: replacement.due.title,
          );
        }
      }
      await registry.save(plan.nextRegistry);
    } catch (error) {
      debugPrint('WorkspaceController.reconcileSystemCalendar failed: $error');
    }
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
