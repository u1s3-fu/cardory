// 多平台同步协调器。
//
// 统一管理目录同步、WebDAV、自建服务和 S3 兼容存储四种同步后端。负责同步流程编排
//（检查连接→拉取→推送→冲突检测），通过 SHA-256 哈希和修订版本号判断
// 本地与远端的差异。

import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import '../domain/attachment_repository.dart';
import '../domain/workspace_sync_service.dart';
import '../domain/cardory_repository.dart';
import '../domain/cardory_models.dart';
import 'sync_config_sync.dart';
import 'sync_data_merger.dart';
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

  /// 云端配置文档 key（转发自 [CloudConfigSync]）。
  static const configKey = CloudConfigSync.configKey;

  final SyncRepository repository;
  final SyncProviderFactory providerFactory;
  final AttachmentRepositoryFactory attachmentRepositoryFactory;
  final Duration providerInitializationTimeout;
  SyncStatus _status = const SyncStatus();
  _PendingSyncConflict? _pendingConflict;
  final _listeners = <WorkspaceListener>{};
  late final CloudConfigSync _configSync = CloudConfigSync(repository: repository);

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
        final mergedData = mergeSyncData(
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
          final conflicts = buildSyncConflictItems(localResult.data, remoteData);
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
        final withConfig = await _configSync.sync(activeProvider, updated, _hash);
        return withConfig.copyWith(pendingAttachmentDeletes: remainingDeletes);
      }
      if (remoteChanged && localChanged) {
        final snapshot = await _saveConflictSnapshot(remote.bytes);
        final remoteData = await _inspectRemote(repository, remote.bytes);
        final conflicts = buildSyncConflictItems(localResult.data, remoteData);
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
        final withConfig = await _configSync.sync(activeProvider, updated, _hash);
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
      return await _configSync.sync(activeProvider, updated, _hash);
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
        // 已完成的同步不应因客户端关闭与平台传输层关停的竞态而变为失败。
      }
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
    final withConfig = await _configSync.sync(provider, updated, _hash);
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
      // 存储键不可变且带版本号。在元数据容器提交成功之前，
      // 绝不覆盖已有对象。
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
        // 导入的或当前的元数据仍持有该附件，
        // 其先前记录的删除意图已失效，不应一直留存。
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
