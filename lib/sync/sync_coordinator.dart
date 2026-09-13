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
import 'sync_debug_log.dart';
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
    required this.kind,
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
  final SyncConflictKind kind;
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
      // 状态复位到空闲，清空冲突上下文（冲突列表与场景信息已不再适用）。
      _setStatus(
        SyncStatus(
          phase: SyncPhase.idle,
          providerId: pending.providerId,
          message: pending.kind == SyncConflictKind.unreadableRemote
              ? '已跳过该次同步：云端快照保持原样，本地数据未改变'
              : '已取消冲突处理，本地数据未改变',
          lastSyncedAt: pending.settings.lastSyncedAt,
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
        // 云端已前进一步：保留冲突列表与场景信息，提示用户后由界面重新发起选择。
        _setStatus(
          _status.copyWith(
            phase: SyncPhase.conflict,
            providerId: pending.providerId,
            message: '云端数据已变化，请重新确认覆盖方向',
            lastSyncedAt: pending.settings.lastSyncedAt,
          ),
        );
        return pending.settings;
      }
      // 云端快照无法解密时，唯一合法的写操作是「用本地覆盖云端」（keepLocal）。
      // 其余选项需要读取云端内容（manualMerge / keepRemote），在该场景下不成立，
      // 在协调器层直接拒绝，不依赖界面是否隐藏了对应按钮。
      if (pending.kind == SyncConflictKind.unreadableRemote &&
          choice != SyncConflictChoice.keepLocal) {
        return _fail(
          pending.settings,
          '云端数据无法解密，无法读取其内容进行合并或使用；'
          '请选择“用本地数据覆盖云端”或“跳过”。',
        );
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
        // 说明：这里把带锚点的 updated 一并写盘是有意为之——syncLocalHash
        // 仍指向冲突发生时导出的 pending.localHash（而非 merged 数据的哈希）。
        // 若随后的云端写入失败，本地库已是 merged 数据而锚点仍指向旧哈希，
        // 下次同步会判定“本地有变更”走推送分支重新收敛，而不是误判已同步。
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
        // 使用云端数据意味着本地当前库即将被整体替换。先把本地数据留底，
        // 供误操作或在别处找回原本地库使用。
        final localBackup = await _saveConflictSnapshot(pending.local);
        final localResult = await repository.load();
        final attachmentStore = attachmentRepositoryFactory(localResult.path);
        final remoteHash = await _hash(pending.remote.bytes);
        final syncedAt = DateTime.now().toUtc();
        final updated = pending.settings.copyWith(
          syncRevision: pending.remote.revision,
          syncLocalHash: remoteHash,
          lastSyncedAt: syncedAt,
        );
        try {
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
        } catch (_) {
          // 与下载分支一致：导入或附件准备中途失败时，回滚到冲突发生前的
          // 本地库，避免出现“本地已被整体替换但附件/设置未完成”的半完成
          // 状态。快照（localBackup）仍保留，可人工找回。
          await repository.importContainer(pending.local, pending.settings);
          await repository.saveSettings(pending.settings);
          rethrow;
        }
        _pendingConflict = null;
        _setStatus(
          SyncStatus(
            phase: SyncPhase.success,
            providerId: provider.id,
            message: '已使用云端数据，本地已更新（覆盖前本地数据已备份：$localBackup）',
            lastSyncedAt: syncedAt,
            requiresReload: true,
          ),
        );
        return updated;
      }

      // 「用本地覆盖云端」会以本机加密快照替换云端原有快照。若云端快照本身
      // 无法解密（unreadableRemote），覆盖前必须确保云端原文件已成功留底——
      // 否则云端原文件可能是唯一可被另一台设备读取的副本，覆盖即永久销毁。
      final isUnreadableOverwrite =
          pending.kind == SyncConflictKind.unreadableRemote;
      String? remoteBackup;
      if (isUnreadableOverwrite) {
        remoteBackup = _snapshotFailed(pending.snapshot)
            ? null
            : pending.snapshot;
        remoteBackup ??= await _saveConflictSnapshot(pending.remote.bytes);
        if (_snapshotFailed(remoteBackup)) {
          return _fail(
            pending.settings,
            '无法备份云端原文件，已取消“用本地数据覆盖云端”，以保护云端数据。'
            '请检查磁盘空间后重试。',
          );
        }
      }

      final localResult = await repository.load();
      final attachmentStore = attachmentRepositoryFactory(localResult.path);
      final pushed = await _push(
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
      if (isUnreadableOverwrite) {
        _setStatus(
          SyncStatus(
            phase: SyncPhase.success,
            providerId: provider.id,
            message: '已用本地数据覆盖云端（原云端快照已备份：$remoteBackup）',
            lastSyncedAt: pushed.lastSyncedAt,
          ),
        );
      }
      return pushed;
    } catch (error, stackTrace) {
      logSync('解决冲突失败', error: error, stackTrace: stackTrace);
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
    logSync('开始同步（同步方式=${settings.syncProvider.name}）');
    final providerId = settings.syncProvider.name;
    SyncProvider? provider;
    try {
      _setStatus(SyncStatus(phase: SyncPhase.checking, providerId: providerId));
      final activeProvider = await _createProvider(settings);
      provider = activeProvider;
      logSync('同步提供者已初始化（${activeProvider.id}），执行连接检查');
      await activeProvider.checkConnection();
      logSync('连接检查通过');
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
      if (remote != null) {
        final head = remote.bytes
            .take(4)
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
        logSync(
          '远端文档字节数=${remote.bytes.length}，首 4 字节 hex=$head'
          '（疑似文本/HTML 时通常首字节为 0x3c）',
        );
      }
      logSync(
        '读取远端文档完成：远端=${remote == null ? '无' : 'rev=${remote.revision}'}'
        '，本地有变更=$localChanged，远端有变更=$remoteChanged',
      );

      if (remote == null) {
        logSync('远端不存在数据文档，将执行首次上传');
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
          final CardoryData remoteData;
          try {
            remoteData = await _inspectRemote(repository, remote.bytes);
          } on CardorySnapshotUndecryptableException catch (error, stackTrace) {
            logSync(
              '首次同步发现云端快照无法解密，转入手动选择',
              error: error,
              stackTrace: stackTrace,
            );
            return await _suspendForUndecryptableRemote(
              settings: settings,
              providerId: providerId,
              local: local,
              localHash: localHash,
              localData: localResult.data,
              remote: remote,
              snapshot: snapshot,
            );
          }
          final conflicts = buildSyncConflictItems(
            localResult.data,
            remoteData,
          );
          return await _suspendForConflict(
            settings: settings,
            providerId: providerId,
            local: local,
            localHash: localHash,
            localData: localResult.data,
            remote: remote,
            snapshot: snapshot,
            remoteData: remoteData,
            conflicts: conflicts,
            kind: SyncConflictKind.firstSync,
          );
        }
        final remoteHash = await _hash(remote.bytes);
        final syncedAt = DateTime.now().toUtc();
        final updated = settings.copyWith(
          syncRevision: remote.revision,
          syncLocalHash: remoteHash,
          lastSyncedAt: syncedAt,
        );
        final CardoryData remoteData;
        try {
          remoteData = await repository.importContainer(remote.bytes, updated);
        } on CardorySnapshotUndecryptableException catch (error, stackTrace) {
          logSync(
            '首次同步（本地为空）时云端快照无法解密，转入手动选择',
            error: error,
            stackTrace: stackTrace,
          );
          final snapshot = await _saveConflictSnapshot(remote.bytes);
          return await _suspendForUndecryptableRemote(
            settings: settings,
            providerId: providerId,
            local: local,
            localHash: localHash,
            localData: localResult.data,
            remote: remote,
            snapshot: snapshot,
          );
        }
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
        final CardoryData remoteData;
        try {
          remoteData = await _inspectRemote(repository, remote.bytes);
        } on CardorySnapshotUndecryptableException catch (error, stackTrace) {
          logSync(
            '双向修改场景下云端快照无法解密，转入手动选择',
            error: error,
            stackTrace: stackTrace,
          );
          return await _suspendForUndecryptableRemote(
            settings: settings,
            providerId: providerId,
            local: local,
            localHash: localHash,
            localData: localResult.data,
            remote: remote,
            snapshot: snapshot,
          );
        }
        final conflicts = buildSyncConflictItems(localResult.data, remoteData);
        return await _suspendForConflict(
          settings: settings,
          providerId: providerId,
          local: local,
          localHash: localHash,
          localData: localResult.data,
          remote: remote,
          snapshot: snapshot,
          remoteData: remoteData,
          conflicts: conflicts,
          kind: SyncConflictKind.concurrent,
        );
      }
      if (remoteChanged) {
        logSync('远端有更新，开始下载并应用到本地');
        final remoteHash = await _hash(remote.bytes);
        final syncedAt = DateTime.now().toUtc();
        final updated = settings.copyWith(
          syncRevision: remote.revision,
          syncLocalHash: remoteHash,
          lastSyncedAt: syncedAt,
        );
        final CardoryData remoteData;
        try {
          remoteData = await repository.importContainer(remote.bytes, updated);
        } on CardorySnapshotUndecryptableException catch (error, stackTrace) {
          logSync('远端快照无法解密，转入手动选择', error: error, stackTrace: stackTrace);
          final snapshot = await _saveConflictSnapshot(remote.bytes);
          return await _suspendForUndecryptableRemote(
            settings: settings,
            providerId: providerId,
            local: local,
            localHash: localHash,
            localData: localResult.data,
            remote: remote,
            snapshot: snapshot,
          );
        }
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
        logSync('本地有更新，执行上传同步');
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

      logSync('本地与远端均无数据变更，执行附件一致性校验');
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
    } catch (error, stackTrace) {
      // 内容冲突已在同步主流程内挂起并返回，不再经过异常路径。这里捕获的
      // SyncConflictException 仅剩 provider 层的 409/412（云端被其他设备抢先
      // 修改导致写入被拒），如实提示用户重新同步以重新比对，而非弹冲突框。
      logSync('同步执行失败', error: error, stackTrace: stackTrace);
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
    logSync('开始推送本地数据到远端');
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
    logSync('主数据文档写入成功（revision=${result.revision}）');
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
    logSync('本地设置已保存，开始同步云端配置文档');
    final withConfig = await _configSync.sync(provider, updated, _hash);
    logSync('云端配置文档同步完成，发布附件清单');
    await _publishAttachmentManifest(provider, data);
    logSync('推送同步成功');
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

  /// 云端快照无法解密（[CardorySnapshotUndecryptableException]）时统一挂起为
  /// [SyncConflictKind.unreadableRemote]。云端内容不可读，因此没有冲突列表、
  /// 没有可用的远端数据，只等用户手动决定「用本地覆盖云端」或「跳过」。
  Future<AppSettings> _suspendForUndecryptableRemote({
    required AppSettings settings,
    required String providerId,
    required List<int> local,
    required String localHash,
    required CardoryData localData,
    required SyncDocument remote,
    required String snapshot,
  }) async {
    return await _suspendForConflict(
      settings: settings,
      providerId: providerId,
      local: local,
      localHash: localHash,
      localData: localData,
      remote: remote,
      snapshot: snapshot,
      remoteData: const CardoryData(projects: [], todos: []),
      conflicts: const [],
      kind: SyncConflictKind.unreadableRemote,
    );
  }

  /// 统一挂起一次同步冲突：记录冲突上下文、进入冲突状态并返回未修改的配置。
  ///
  /// 首次同步发现本地数据（[SyncConflictKind.firstSync]）与自上次同步后的
  /// 双向修改（[SyncConflictKind.concurrent]）都经由这里收敛，保证冲突场景
  /// 语义、冲突列表与界面文案保持一致。冲突不通过异常上抛——配置原样返回，
  /// 由界面依据状态相位决定如何提示与引导处理。
  Future<AppSettings> _suspendForConflict({
    required AppSettings settings,
    required String providerId,
    required List<int> local,
    required String localHash,
    required CardoryData localData,
    required SyncDocument remote,
    required String snapshot,
    required CardoryData remoteData,
    required List<SyncConflictItem> conflicts,
    required SyncConflictKind kind,
  }) async {
    final message = switch (kind) {
      SyncConflictKind.firstSync =>
        '首次同步发现本地数据（${_countItems(localData)} 项），'
            '本地与云端尚未同步过，已暂停覆盖，请选择保留方向',
      SyncConflictKind.concurrent =>
        '检测到 ${conflicts.length} 项本地与远端差异，已暂停自动覆盖，请选择处理方式',
      SyncConflictKind.unreadableRemote =>
        '云端数据无法解密：文件可能已损坏，或由使用不同保险库密码的设备上传。'
            '本地数据未改变，已暂停自动同步，请手动选择处理方式',
    };
    logSync(message);
    _pendingConflict = _PendingSyncConflict(
      local: local,
      localHash: localHash,
      localData: localData,
      settings: settings,
      remote: remote,
      providerId: providerId,
      snapshot: snapshot,
      remoteData: remoteData,
      conflicts: conflicts,
      kind: kind,
    );
    _setStatus(
      SyncStatus(
        phase: SyncPhase.conflict,
        providerId: providerId,
        message: message,
        lastSyncedAt: settings.lastSyncedAt,
        conflicts: conflicts,
        conflictKind: kind,
      ),
    );
    return settings;
  }

  int _countItems(CardoryData data) =>
      data.projects.length + data.todos.length + data.assets.length;

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

  /// 快照留底是否失败：空路径或返回了「保存失败」说明未能落盘。
  bool _snapshotFailed(String snapshot) =>
      snapshot.isEmpty || snapshot.startsWith('保存失败');

  AppSettings _fail(AppSettings settings, String message) {
    logSync('同步失败，界面提示：$message');
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
    SyncConflictException value => value.message,
    CardoryStorageException value => value.message,
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
    } catch (error, stackTrace) {
      // 读取失败时按“云端无清单”处理（退化到旧的一致性校验），但留下
      // 完整日志，避免瞬断或异常被当作“老版本云端无清单”而难以排查。
      logSync('读取云端附件清单失败（按缺失处理）', error: error, stackTrace: stackTrace);
      return null;
    }
  }

  /// 每次同步成功收敛后，把当前快照的附件集合以 manifest 幂等重写回云端，
  /// 保证云端始终有该快照引用的附件权威枚举（供恢复、完整性校验与孤儿清理）。
  ///
  /// 该写入是**尽力而为**：失败只记录日志，不把已成功的同步结果翻转成失败。
  /// manifest 只描述附件归属，随后任何一次成功的同步（含无变化的 F 分支）都会
  /// 以当时的快照重新覆盖它，因此这里失败不会留下不可自愈的云端状态。
  Future<void> _publishAttachmentManifest(
    SyncProvider provider,
    CardoryData data,
  ) async {
    try {
      await provider.write(
        attachmentManifestKey,
        AttachmentManifest.build(_attachmentsOf(data)).toBytes(),
      );
    } catch (error, stackTrace) {
      logSync(
        '发布云端附件清单失败（已降级处理，下次同步会重写）',
        error: error,
        stackTrace: stackTrace,
      );
    }
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
