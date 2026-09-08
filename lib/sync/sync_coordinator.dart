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
import 'attachment_manifest.dart';
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

  static const documentKey = 'cardory-snapshot-v2.db';

  /// 云端配置文档 key（转发自 [CloudConfigSync]）。
  static const configKey = CloudConfigSync.configKey;

  final SyncRepository repository;
  final SyncProviderFactory providerFactory;
  final AttachmentRepositoryFactory attachmentRepositoryFactory;
  final Duration providerInitializationTimeout;
  SyncStatus _status = const SyncStatus();
  _PendingSyncConflict? _pendingConflict;
  // 最近一次 synchronize 收到的设置。pending 冲突丢失时（过期请求、
  // 竞态重入）resolveConflict 用它兜底，避免把用户配置重置为出厂默认。
  AppSettings _lastKnownSettings = const AppSettings();
  final _listeners = <WorkspaceListener>{};
  late final CloudConfigSync _configSync = CloudConfigSync(
    repository: repository,
  );

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
    if (pending == null) return _lastKnownSettings;
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
      final remoteManifest = await _readAttachmentManifest(provider);
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
          remoteManifest: remoteManifest,
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
        await _synchronizeAttachments(
          provider,
          remoteData,
          attachmentStore,
          remoteManifest: remoteManifest,
        );
        await repository.saveSettings(updated);
        await _publishAttachmentManifest(provider, remoteData);
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
        remoteManifest: remoteManifest,
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
    _lastKnownSettings = settings;
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
      // 附件清单读取是尽力而为的：清单缺失/格式不支持/网络不可用时返回
      // null（更老版本云端无清单），只在确实读取到清单时做一致性校验。
      final remoteManifest = remote == null
          ? null
          : await _readAttachmentManifest(activeProvider);
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
          final conflicts = buildSyncConflictItems(
            localResult.data,
            remoteData,
          );
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
            remoteManifest: remoteManifest,
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
        // 附件已就位，重写云端附件清单（幂等），保证其与本地快照引用一致。
        await _publishAttachmentManifest(activeProvider, remoteData);
        final withConfig = await _configSync.sync(
          activeProvider,
          updated,
          _hash,
        );
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
        throw SyncConflictException('本地与远端均有修改，未自动覆盖任何数据。远端副本已保留：$snapshot');
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
            remoteManifest: remoteManifest,
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
        // 附件已就位，重写云端附件清单（幂等），保证其与本地快照引用一致。
        await _publishAttachmentManifest(activeProvider, remoteData);
        final withConfig = await _configSync.sync(
          activeProvider,
          updated,
          _hash,
        );
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
          remoteManifest: remoteManifest,
        );
      }

      await _synchronizeAttachments(
        activeProvider,
        localResult.data,
        attachmentStore,
        remoteManifest: remoteManifest,
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
      await _publishAttachmentManifest(activeProvider, localResult.data);
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
          message: _status.message ?? '检测到本地与远端均有更改，已暂停同步以避免覆盖数据。',
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
    AttachmentRepository attachmentStore, {
    AttachmentManifest? remoteManifest,
  }) async {
    _setStatus(SyncStatus(phase: SyncPhase.pushing, providerId: provider.id));
    await _synchronizeAttachments(
      provider,
      data,
      attachmentStore,
      remoteManifest: remoteManifest,
    );
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
    await _publishAttachmentManifest(provider, data);
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
    AttachmentRepository store, {
    AttachmentManifest? remoteManifest,
  }) async {
    final attachments = _attachmentsOf(data);
    if (attachments.isEmpty) return;
    if (provider is! AttachmentSyncProvider) {
      throw const SyncProviderException('当前同步方式不支持独立附件传输');
    }
    final attachmentProvider = provider as AttachmentSyncProvider;
    for (final attachment in attachments) {
      final key = attachmentFileKey(attachment.storageKey);
      final localExists = await store.contains(attachment);
      final remoteExists = await attachmentProvider.fileExists(key);
      // 存储键不可变且带版本号。在元数据快照提交成功之前，
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
        // 快照引用的附件在本地与云端都不存在。若云端清单明确不含该附件，
        // 说明远端快照与附件集合不一致，fail-closed，绝不把损坏状态导入本地；
        // 清单缺失（老版本云端）时维持原有错误提示。
        if (remoteManifest != null &&
            !remoteManifest.contains(attachment.storageKey)) {
          throw SyncProviderException(
            '远端快照引用的附件不在云端附件清单中：${attachment.fileName}，'
            '已停止同步以保护数据一致性。',
          );
        }
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
    final activeKeys = _attachmentsOf(
      data,
    ).map((attachment) => attachment.storageKey).toSet();
    final remaining = <String>[];
    for (final storageKey in pendingDeletes) {
      if (activeKeys.contains(storageKey)) {
        // 导入的或当前的元数据仍持有该附件，
        // 其先前记录的删除意图已失效，不应一直留存。
        continue;
      }
      try {
        await provider.delete(attachmentFileKey(storageKey));
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
    throw const SyncProviderException('当前本地存储实现无法安全解析远端加密快照，已停止同步以避免覆盖数据。');
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
      throw SyncProviderException('同步初始化超时，请检查系统安全存储后重试。', cause: error);
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

  List<AttachmentData> _attachmentsOf(CardoryData data) => data.projects
      .expand((project) => project.attachments)
      .where((attachment) => attachment.storageKey.isNotEmpty)
      .toList();

  /// 读取云端附件清单。清单不存在、格式不支持或网络不可用时返回 null
  /// （更老版本云端可能没有清单），由调用方决定是否跳过清单校验。
  Future<AttachmentManifest?> _readAttachmentManifest(
    SyncProvider provider,
  ) async {
    try {
      final doc = await provider.read(attachmentManifestKey);
      if (doc == null) return null;
      return AttachmentManifest.fromBytes(doc.bytes);
    } catch (_) {
      return null;
    }
  }

  /// 每次同步成功收敛后，把当前快照的附件集合以 manifest 幂等重写回云端，
  /// 保证云端始终有该快照引用的附件权威枚举（供恢复、完整性校验与孤儿清理）。
  Future<void> _publishAttachmentManifest(
    SyncProvider provider,
    CardoryData data,
  ) async {
    await provider.write(
      attachmentManifestKey,
      AttachmentManifest.build(_attachmentsOf(data)).toBytes(),
    );
  }

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
