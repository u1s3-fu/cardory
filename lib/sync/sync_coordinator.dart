// 多平台同步协调器。
//
// 统一管理目录同步、WebDAV、自建服务和 S3 兼容存储四种同步后端。负责同步流程编排
//（检查连接→拉取→推送→冲突检测），通过 SHA-256 哈希和修订版本号判断
// 本地与远端的差异。

import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import '../application/attachment_repository.dart';
import '../application/workspace_sync_service.dart';
import '../application/cardory_repository.dart';
import '../domain/cardory_models.dart';
import 'sync_models.dart';
import 'sync_provider.dart';

export 'sync_provider.dart' show SyncProviderFactory;

class _PendingSyncConflict {
  const _PendingSyncConflict({
    required this.local,
    required this.localHash,
    required this.localData,
    required this.settings,
    required this.remote,
    required this.providerId,
    required this.snapshot,
    required this.remoteData,
    required this.conflicts,
  });

  final List<int> local;
  final String localHash;
  final CardoryData localData;
  final AppSettings settings;
  final SyncDocument remote;
  final String providerId;
  final String snapshot;
  final CardoryData remoteData;
  final List<SyncConflictItem> conflicts;
}

class SyncCoordinator implements WorkspaceSyncService {
  static const defaultProviderInitializationTimeout = Duration(seconds: 20);

  SyncCoordinator({
    required this.repository,
    required this.providerFactory,
    required this.attachmentRepositoryFactory,
    this.providerInitializationTimeout = defaultProviderInitializationTimeout,
  });

  static const documentKey = 'cardory-current-data.cardory';

  /// 云端配置文档 key，与数据文档并列，保存可同步的配置子集。
  static const configKey = 'cardory-current-config.json';

  final SyncRepository repository;
  final SyncProviderFactory providerFactory;
  final AttachmentRepositoryFactory attachmentRepositoryFactory;
  final Duration providerInitializationTimeout;
  SyncStatus _status = const SyncStatus();
  _PendingSyncConflict? _pendingConflict;
  final _listeners = <WorkspaceListener>{};

  @override
  SyncStatus get status => _status;

  @override
  bool get hasPendingConflict => _pendingConflict != null;

  @override
  Future<AppSettings> resolveConflict(
    SyncConflictChoice choice, {
    Map<String, SyncConflictSide> itemChoices = const {},
  }) async {
    final pending = _pendingConflict;
    if (pending == null) return const AppSettings();
    if (choice == SyncConflictChoice.cancel) {
      _pendingConflict = null;
      _setStatus(
        _status.copyWith(
          phase: SyncPhase.idle,
          message: '已取消冲突处理，本地数据未改变',
          requiresReload: false,
        ),
      );
      return pending.settings;
    }

    SyncProvider? provider;
    try {
      provider = await _createProvider(pending.settings);
      await provider.checkConnection();
      final currentRemote = await provider.read(documentKey);
      if (currentRemote?.revision != pending.remote.revision ||
          pending.remote.revision == null) {
        _setStatus(
          SyncStatus(
            phase: SyncPhase.conflict,
            providerId: pending.providerId,
            message: '云端数据已变化，请重新确认覆盖方向',
            lastSyncedAt: pending.settings.lastSyncedAt,
          ),
        );
        return pending.settings;
      }
      if (choice == SyncConflictChoice.manualMerge) {
        final mergedData = _mergeData(
          pending.localData,
          pending.remoteData,
          itemChoices,
        );
        final updated = pending.settings.copyWith(
          syncRevision: pending.remote.revision,
          syncLocalHash: pending.localHash,
          lastSyncedAt: DateTime.now().toUtc(),
        );
        final localResult = await repository.load();
        final attachmentStore = attachmentRepositoryFactory(localResult.path);
        await repository.save(mergedData, updated);
        final mergedBytes = await repository.exportContainer();
        final pushed = await _push(
          provider,
          mergedBytes,
          updated,
          await _hash(mergedBytes),
          mergedData,
          attachmentStore,
        );
        _pendingConflict = null;
        _setStatus(
          SyncStatus(
            phase: SyncPhase.success,
            providerId: provider.id,
            message: '已完成手动合并并同步',
            lastSyncedAt: pushed.lastSyncedAt,
            summary: SyncResultSummary(mergedItems: pending.conflicts.length),
          ),
        );
        return pushed;
      }

      if (choice == SyncConflictChoice.keepRemote) {
        final localResult = await repository.load();
        final attachmentStore = attachmentRepositoryFactory(localResult.path);
        final remoteHash = await _hash(pending.remote.bytes);
        final syncedAt = DateTime.now().toUtc();
        final updated = pending.settings.copyWith(
          syncRevision: pending.remote.revision,
          syncLocalHash: remoteHash,
          lastSyncedAt: syncedAt,
        );
        final remoteData = await repository.importContainer(
          pending.remote.bytes,
          updated,
        );
        await _synchronizeAttachments(provider, remoteData, attachmentStore);
        await repository.saveSettings(updated);
        _pendingConflict = null;
        _setStatus(
          SyncStatus(
            phase: SyncPhase.success,
            providerId: provider.id,
            message: '已使用云端数据，本地已更新',
            lastSyncedAt: syncedAt,
            requiresReload: true,
          ),
        );
        return updated;
      }

      final localResult = await repository.load();
      final attachmentStore = attachmentRepositoryFactory(localResult.path);
      final updated = await _push(
        provider,
        pending.local,
        pending.settings.copyWith(
          syncRevision: pending.remote.revision,
          syncLocalHash: pending.localHash,
        ),
        pending.localHash,
        pending.localData,
        attachmentStore,
      );
      _pendingConflict = null;
      return updated;
    } catch (error) {
      return _fail(pending.settings, _messageFor(error));
    } finally {
      await provider?.dispose();
    }
  }

  @override
  Future<AppSettings> synchronize(AppSettings settings) async {
    if (_status.isRunning) return settings;
    if (settings.syncProvider == SyncProviderType.none) {
      return _fail(settings, '请先选择同步方式');
    }
    final providerId = settings.syncProvider.name;
    SyncProvider? provider;
    try {
      _setStatus(SyncStatus(phase: SyncPhase.checking, providerId: providerId));
      final activeProvider = await _createProvider(settings);
      provider = activeProvider;
      await activeProvider.checkConnection();
      final localResult = await repository.load();
      final attachmentStore = attachmentRepositoryFactory(localResult.path);
      final local = await repository.exportContainer();
      final localHash = await _hash(local);
      _setStatus(
        SyncStatus(phase: SyncPhase.pulling, providerId: activeProvider.id),
      );
      final remote = await activeProvider.read(documentKey);
      final lastHash = settings.syncLocalHash;
      final remoteChanged =
          remote != null &&
          settings.syncRevision != null &&
          remote.revision != settings.syncRevision;
      final localChanged = lastHash != null && localHash != lastHash;

      if (remote == null) {
        return await _push(
          activeProvider,
          local,
          settings,
          localHash,
          localResult.data,
          attachmentStore,
        );
      }
      if (lastHash == null) {
        if (!_isEmpty(localResult.data)) {
          final snapshot = await _saveConflictSnapshot(remote.bytes);
          final remoteData = await _inspectRemote(repository, remote.bytes);
          final conflicts = _buildConflictItems(localResult.data, remoteData);
          _pendingConflict = _PendingSyncConflict(
            local: local,
            localHash: localHash,
            localData: localResult.data,
            settings: settings,
            remote: remote,
            providerId: providerId,
            snapshot: snapshot,
            remoteData: remoteData,
            conflicts: conflicts,
          );
          _setStatus(
            SyncStatus(
              phase: SyncPhase.conflict,
              providerId: providerId,
              message: '首次同步发现本地数据，已暂停覆盖，请选择同步方向',
              lastSyncedAt: settings.lastSyncedAt,
              conflicts: conflicts,
            ),
          );
          return settings;
        }
        final remoteHash = await _hash(remote.bytes);
        final syncedAt = DateTime.now().toUtc();
        final updated = settings.copyWith(
          syncRevision: remote.revision,
          syncLocalHash: remoteHash,
          lastSyncedAt: syncedAt,
        );
        final remoteData = await repository.importContainer(
          remote.bytes,
          updated,
        );
        var remainingDeletes = updated.pendingAttachmentDeletes;
        try {
          await _synchronizeAttachments(
            activeProvider,
            remoteData,
            attachmentStore,
          );
          remainingDeletes = await _deletePendingAttachments(
            activeProvider,
            remoteData,
            updated.pendingAttachmentDeletes,
          );
          await repository.saveSettings(
            updated.copyWith(pendingAttachmentDeletes: remainingDeletes),
          );
        } catch (_) {
          await repository.importContainer(local, settings);
          await repository.saveSettings(settings);
          rethrow;
        }
        _setStatus(
          SyncStatus(
            phase: SyncPhase.success,
            providerId: activeProvider.id,
            message: '已下载远端数据',
            lastSyncedAt: syncedAt,
            requiresReload: true,
          ),
        );
        final withConfig = await _syncConfig(activeProvider, updated);
        return withConfig.copyWith(pendingAttachmentDeletes: remainingDeletes);
      }
      if (remoteChanged && localChanged) {
        final snapshot = await _saveConflictSnapshot(remote.bytes);
        final remoteData = await _inspectRemote(repository, remote.bytes);
        final conflicts = _buildConflictItems(localResult.data, remoteData);
        _pendingConflict = _PendingSyncConflict(
          local: local,
          localHash: localHash,
          localData: localResult.data,
          settings: settings,
          remote: remote,
          providerId: providerId,
          snapshot: snapshot,
          remoteData: remoteData,
          conflicts: conflicts,
        );
        _setStatus(
          SyncStatus(
            phase: SyncPhase.conflict,
            providerId: providerId,
            message: '检测到 ${conflicts.length} 项本地与远端差异，请选择处理方式',
            lastSyncedAt: settings.lastSyncedAt,
            conflicts: conflicts,
          ),
        );
        throw SyncConflictException(
          '本地与远端均有修改，未自动覆盖任何数据。远端副本已保留：$snapshot',
        );
      }
      if (remoteChanged) {
        final remoteHash = await _hash(remote.bytes);
        final syncedAt = DateTime.now().toUtc();
        final updated = settings.copyWith(
          syncRevision: remote.revision,
          syncLocalHash: remoteHash,
          lastSyncedAt: syncedAt,
        );
        final remoteData = await repository.importContainer(
          remote.bytes,
          updated,
        );
        var remainingDeletes = updated.pendingAttachmentDeletes;
        try {
          await _synchronizeAttachments(
            activeProvider,
            remoteData,
            attachmentStore,
          );
          remainingDeletes = await _deletePendingAttachments(
            activeProvider,
            remoteData,
            updated.pendingAttachmentDeletes,
          );
          await repository.saveSettings(
            updated.copyWith(pendingAttachmentDeletes: remainingDeletes),
          );
        } catch (_) {
          await repository.importContainer(local, settings);
          await repository.saveSettings(settings);
          rethrow;
        }
        _setStatus(
          SyncStatus(
            phase: SyncPhase.success,
            providerId: activeProvider.id,
            message: '已下载远端更新',
            lastSyncedAt: syncedAt,
            requiresReload: true,
          ),
        );
        final withConfig = await _syncConfig(activeProvider, updated);
        return withConfig.copyWith(pendingAttachmentDeletes: remainingDeletes);
      }
      if (localChanged) {
        return await _push(
          activeProvider,
          local,
          settings,
          localHash,
          localResult.data,
          attachmentStore,
        );
      }

      await _synchronizeAttachments(
        activeProvider,
        localResult.data,
        attachmentStore,
      );

      final syncedAt = DateTime.now().toUtc();
      final remainingDeletes = await _deletePendingAttachments(
        activeProvider,
        localResult.data,
        settings.pendingAttachmentDeletes,
      );
      final updated = settings.copyWith(
        lastSyncedAt: syncedAt,
        pendingAttachmentDeletes: remainingDeletes,
      );
      await repository.saveSettings(updated);
      _setStatus(
        SyncStatus(
          phase: SyncPhase.success,
          providerId: activeProvider.id,
          message: '本地与远端已是最新',
          lastSyncedAt: syncedAt,
        ),
      );
      return await _syncConfig(activeProvider, updated);
    } on SyncConflictException {
      _setStatus(
        _status.copyWith(
          phase: SyncPhase.conflict,
          providerId: providerId,
          message: _status.message ??
              '检测到本地与远端均有更改，已暂停同步以避免覆盖数据。',
          lastSyncedAt: settings.lastSyncedAt,
        ),
      );
      return settings;
    } catch (error) {
      return _fail(settings, _messageFor(error));
    } finally {
      try {
        await provider?.dispose();
      } catch (_) {
        // A completed sync must not become a failure because a client close
        // races with the platform transport shutdown.
      }
    }
  }

  /// 同步配置文档到云端（双向）。
  ///
  /// 读取/写入固定 key 的配置文档（[configKey]），采用"最后写入者获胜"策略：
  /// - 本地有未同步的配置变更，且云端不更新 → 推送本地配置覆盖云端
  /// - 云端配置比本地更新 → 拉取云端配置应用到本地
  ///
  /// 返回更新后的 [AppSettings]，并持久化到本地。
  Future<AppSettings> _syncConfig(
    SyncProvider provider,
    AppSettings settings,
  ) async {
    try {
      final localJson = settings.toSyncConfigJson();
      final localHash = await _hash(utf8.encode(jsonEncode(localJson)));

      final cloudDoc = await provider.read(configKey);

      if (cloudDoc == null) {
        // 云端没有配置文档：若本地有未同步的配置，则上传。
        if (settings.configSyncHash != localHash) {
          return await _pushConfig(provider, settings, localJson);
        }
        return settings;
      }

      final cloud = _decodeConfig(cloudDoc.bytes);
      if (cloud == null) {
        // 云端配置文档损坏，忽略，尝试用本地覆盖。
        if (settings.configSyncHash != localHash) {
          return await _pushConfig(provider, settings, localJson);
        }
        return settings;
      }

      final cloudHash = await _hash(utf8.encode(jsonEncode(cloud.settings)));
      final cloudUpdatedAt = cloud.updatedAt;
      final localUpdatedAt = settings.lastConfigUpdatedAt;
      final localChanged = settings.configSyncHash != localHash;

      if (!localChanged && cloudHash == settings.configSyncHash) {
        // 本地与云端配置已一致。
        return settings;
      }

      final cloudIsNewer =
          localUpdatedAt == null || cloudUpdatedAt.isAfter(localUpdatedAt);

      if (localChanged && !cloudIsNewer) {
        // 本地有变更且不比云端旧，推送本地覆盖云端。
        return await _pushConfig(provider, settings, localJson);
      }

      // 云端更新（或无本地变更且云端较新），拉取云端配置应用到本地。
      return await _applyCloudConfig(
        settings,
        cloud.settings,
        cloudHash,
        cloudUpdatedAt,
      );
    } catch (error) {
      // 配置同步失败不应阻断数据同步主流程，忽略并返回原设置。
      return settings;
    }
  }

  Future<AppSettings> _pushConfig(
    SyncProvider provider,
    AppSettings settings,
    Map<String, dynamic> localJson,
  ) async {
    final now = DateTime.now().toUtc();
    final payload = {
      'v': 1,
      'updatedAt': now.toIso8601String(),
      'settings': localJson,
    };
    final bytes = utf8.encode(jsonEncode(payload));
    final localHash = await _hash(utf8.encode(jsonEncode(localJson)));
    await provider.write(configKey, bytes);
    final updated = settings.copyWith(
      configSyncHash: localHash,
      lastConfigUpdatedAt: now,
    );
    await repository.saveSettings(updated);
    return updated;
  }

  Future<AppSettings> _applyCloudConfig(
    AppSettings settings,
    Map<String, dynamic> cloudSettings,
    String cloudHash,
    DateTime cloudUpdatedAt,
  ) async {
    final applied = settings.applySyncConfig(cloudSettings);
    final updated = applied.copyWith(
      configSyncHash: cloudHash,
      lastConfigUpdatedAt: cloudUpdatedAt,
    );
    await repository.saveSettings(updated);
    return updated;
  }

  ({DateTime updatedAt, Map<String, dynamic> settings})? _decodeConfig(
    List<int> bytes,
  ) {
    try {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
      final settings = json['settings'];
      if (updatedAt == null || settings is! Map<String, dynamic>) return null;
      return (updatedAt: updatedAt, settings: settings);
    } catch (_) {
      return null;
    }
  }

  Future<AppSettings> _push(
    SyncProvider provider,
    List<int> local,
    AppSettings settings,
    String localHash,
    CardoryData data,
    AttachmentRepository attachmentStore,
  ) async {
    _setStatus(SyncStatus(phase: SyncPhase.pushing, providerId: provider.id));
    await _synchronizeAttachments(provider, data, attachmentStore);
    final result = await provider.write(
      documentKey,
      local,
      expectedRevision: settings.syncRevision,
    );
    final syncedAt = DateTime.now().toUtc();
    final committed = settings.copyWith(
      syncRevision: result.revision,
      syncLocalHash: localHash,
      lastSyncedAt: syncedAt,
    );
    await repository.saveSettings(committed);
    final remainingDeletes = await _deletePendingAttachments(
      provider,
      data,
      committed.pendingAttachmentDeletes,
    );
    final updated = committed.copyWith(
      pendingAttachmentDeletes: remainingDeletes,
    );
    if (updated != committed) await repository.saveSettings(updated);
    final withConfig = await _syncConfig(provider, updated);
    _setStatus(
      SyncStatus(
        phase: SyncPhase.success,
        providerId: provider.id,
        message: '同步完成',
        lastSyncedAt: syncedAt,
      ),
    );
    return withConfig;
  }

  Future<void> _synchronizeAttachments(
    SyncProvider provider,
    CardoryData data,
    AttachmentRepository store,
  ) async {
    final attachments = data.projects
        .expand((project) => project.attachments)
        .where((attachment) => attachment.storageKey.isNotEmpty)
        .toList();
    if (attachments.isEmpty) return;
    if (provider is! AttachmentSyncProvider) {
      throw const SyncProviderException('当前同步方式不支持独立附件传输');
    }
    final attachmentProvider = provider as AttachmentSyncProvider;
    for (final attachment in attachments) {
      final key = 'attachments/v1/${attachment.storageKey}';
      final localExists = await store.contains(attachment);
      final remoteExists = await attachmentProvider.fileExists(key);
      // Storage keys are immutable and versioned. Existing objects are never
      // overwritten before the metadata container commits successfully.
      if (localExists && !remoteExists) {
        await attachmentProvider.uploadFile(
          key,
          store.encryptedPath(attachment),
        );
      } else if (!localExists && remoteExists) {
        final target = await store.createDownloadTarget(attachment);
        await attachmentProvider.downloadFile(key, target);
        await store.installEncrypted(attachment, target);
      } else if (!localExists) {
        throw SyncProviderException('附件在本地和远端均不存在：${attachment.fileName}');
      }
    }
  }

  Future<List<String>> _deletePendingAttachments(
    SyncProvider provider,
    CardoryData data,
    List<String> pendingDeletes,
  ) async {
    if (pendingDeletes.isEmpty) return pendingDeletes;
    if (provider is! AttachmentSyncProvider) {
      throw const SyncProviderException('当前同步方式不支持独立附件传输');
    }
    final activeKeys = data.projects
        .expand((project) => project.attachments)
        .map((attachment) => attachment.storageKey)
        .toSet();
    final remaining = <String>[];
    for (final storageKey in pendingDeletes) {
      if (activeKeys.contains(storageKey)) {
        // The imported or current metadata still owns this attachment. Its
        // earlier deletion intent is obsolete and must not linger forever.
        continue;
      }
      try {
        await provider.delete('attachments/v1/$storageKey');
      } catch (_) {
        remaining.add(storageKey);
      }
    }
    return remaining;
  }

  Future<CardoryData> _inspectRemote(
    SyncRepository repository,
    List<int> bytes,
  ) async {
    if (repository is SyncContainerInspector) {
      return (repository as SyncContainerInspector).inspectContainer(bytes);
    }
    // 旧实现无法在不写盘的情况下解密远端，只提供保守的通用冲突项。
    return const CardoryData.empty();
  }

  bool _isEmpty(CardoryData data) =>
      data.projects.isEmpty && data.todos.isEmpty && data.assets.isEmpty;

  List<SyncConflictItem> _buildConflictItems(
    CardoryData local,
    CardoryData remote,
  ) {
    final result = <SyncConflictItem>[];
    void compare(
      String category,
      List<Map<String, dynamic>> localItems,
      List<Map<String, dynamic>> remoteItems,
    ) {
      final localById = {for (final item in localItems) '${item['id']}': item};
      final remoteById = {for (final item in remoteItems) '${item['id']}': item};
      for (final id in {...localById.keys, ...remoteById.keys}) {
        if (jsonEncode(localById[id]) != jsonEncode(remoteById[id])) {
          final item = localById[id] ?? remoteById[id]!;
          result.add(
            SyncConflictItem(
              id: id,
              category: category,
              title: '${item['title'] ?? item['fileName'] ?? id}',
              side: localById.containsKey(id)
                  ? SyncConflictSide.local
                  : SyncConflictSide.remote,
            ),
          );
        }
      }
    }

    compare(
      '项目',
      local.projects.map((item) => item.toJson()).toList(),
      remote.projects.map((item) => item.toJson()).toList(),
    );
    compare(
      '待办',
      local.todos.map((item) => item.toJson()).toList(),
      remote.todos.map((item) => item.toJson()).toList(),
    );
    compare(
      '资产',
      local.assets.map((item) => item.toJson()).toList(),
      remote.assets.map((item) => item.toJson()).toList(),
    );
    return result;
  }

  CardoryData _mergeData(
    CardoryData local,
    CardoryData remote,
    Map<String, SyncConflictSide> choices,
  ) {
    List<T> merge<T>(
      List<T> localItems,
      List<T> remoteItems,
      Map<String, dynamic> Function(T) toJson,
      T Function(Map<String, dynamic>) fromJson,
    ) {
      final localById = {
        for (final item in localItems) '${toJson(item)['id']}': item,
      };
      final remoteById = {
        for (final item in remoteItems) '${toJson(item)['id']}': item,
      };
      return [
        for (final id in {...localById.keys, ...remoteById.keys})
          (choices[id] == SyncConflictSide.remote
              ? remoteById[id]
              : localById[id] ?? remoteById[id]) as T,
      ];
    }

    return CardoryData(
      projects: merge(
        local.projects,
        remote.projects,
        (item) => item.toJson(),
        ProjectData.fromJson,
      ),
      todos: merge(
        local.todos,
        remote.todos,
        (item) => item.toJson(),
        TodoData.fromJson,
      ),
      assets: merge(
        local.assets,
        remote.assets,
        (item) => item.toJson(),
        AssetData.fromJson,
      ),
    );
  }

  Future<String> _hash(List<int> bytes) async {
    final value = await Sha256().hash(bytes);
    return base64Url.encode(value.bytes);
  }

  Future<SyncProvider> _createProvider(AppSettings settings) async {
    try {
      return await providerFactory(
        settings,
      ).timeout(providerInitializationTimeout);
    } on TimeoutException catch (error) {
      throw SyncProviderException(
        '同步初始化超时，请检查系统安全存储后重试。',
        cause: error,
      );
    }
  }

  Future<String> _saveConflictSnapshot(List<int> bytes) async {
    try {
      return await repository.saveSyncConflictSnapshot(bytes);
    } catch (error) {
      // 快照失败不应改变冲突判定，仍然阻止自动覆盖。
      return '保存失败（$error）';
    }
  }

  AppSettings _fail(AppSettings settings, String message) {
    _setStatus(
      SyncStatus(
        phase: SyncPhase.failure,
        providerId: settings.syncProvider.name,
        message: message,
        lastSyncedAt: settings.lastSyncedAt,
      ),
    );
    return settings;
  }

  String _messageFor(Object error) => switch (error) {
    SyncProviderException value => value.message,
    _ => '同步未完成，请稍后重试。',
  };

  void _setStatus(SyncStatus value) {
    _status = value;
    for (final listener in List<WorkspaceListener>.of(_listeners)) {
      listener();
    }
  }

  @override
  void addListener(WorkspaceListener listener) => _listeners.add(listener);

  @override
  void removeListener(WorkspaceListener listener) =>
      _listeners.remove(listener);

  @override
  void dispose() => _listeners.clear();
}
