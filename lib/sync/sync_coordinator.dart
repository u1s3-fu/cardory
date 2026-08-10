/// 多平台同步协调器。
///
/// 统一管理目录同步、WebDAV 和自建服务三种同步后端。负责同步流程编排
///（检查连接→拉取→推送→冲突检测），通过 SHA-256 哈希和修订版本号判断
/// 本地与远端的差异。

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../data/cardory_store.dart';
import '../domain/cardory_models.dart';
import 'directory_sync_provider.dart';
import 'self_hosted_api_sync_provider.dart';
import 'sync_credentials.dart';
import 'sync_models.dart';
import 'sync_provider.dart';
import 'webdav_sync_provider.dart';

typedef SyncProviderFactory =
    Future<SyncProvider> Function(AppSettings settings);

class SyncCoordinator extends ChangeNotifier {
  SyncCoordinator({
    required this.repository,
    required this.credentialStore,
    SyncProviderFactory? providerFactory,
  }) : _providerFactory = providerFactory;

  static const documentKey = 'cardory-current-data.cardory';

  final CardoryRepository repository;
  final SyncCredentialStore credentialStore;
  final SyncProviderFactory? _providerFactory;
  SyncStatus _status = const SyncStatus();

  SyncStatus get status => _status;

  Future<AppSettings> synchronize(AppSettings settings) async {
    if (_status.isRunning) return settings;
    if (settings.syncProvider == SyncProviderType.none) {
      return _fail(settings, '请先选择同步方式');
    }
    final providerId = settings.syncProvider.name;
    try {
      _setStatus(SyncStatus(phase: SyncPhase.checking, providerId: providerId));
      final provider =
          await (_providerFactory?.call(settings) ?? _createProvider(settings));
      await provider.checkConnection();
      final local = await repository.exportContainer();
      final localHash = await _hash(local);
      _setStatus(SyncStatus(phase: SyncPhase.pulling, providerId: provider.id));
      final remote = await provider.read(documentKey);
      final lastHash = settings.syncLocalHash;
      final remoteChanged =
          remote != null &&
          settings.syncRevision != null &&
          remote.revision != settings.syncRevision;
      final localChanged = lastHash != null && localHash != lastHash;

      if (remote == null) {
        return _push(provider, local, settings, localHash);
      }
      if (lastHash == null) {
        throw const SyncConflictException('远端已有 Cardory 数据，请先确认使用哪个版本');
      }
      if (remoteChanged && localChanged) {
        throw const SyncConflictException('本地与远端均有修改，未自动覆盖任何数据');
      }
      if (remoteChanged) {
        final remoteHash = await _hash(remote.bytes);
        final syncedAt = DateTime.now().toUtc();
        final updated = settings.copyWith(
          syncRevision: remote.revision,
          syncLocalHash: remoteHash,
          lastSyncedAt: syncedAt,
        );
        await repository.importContainer(remote.bytes, updated);
        await repository.saveSettings(updated);
        _setStatus(
          SyncStatus(
            phase: SyncPhase.success,
            providerId: provider.id,
            message: '已下载远端更新',
            lastSyncedAt: syncedAt,
          ),
        );
        return updated;
      }
      if (localChanged) return _push(provider, local, settings, localHash);

      final syncedAt = DateTime.now().toUtc();
      final updated = settings.copyWith(lastSyncedAt: syncedAt);
      await repository.saveSettings(updated);
      _setStatus(
        SyncStatus(
          phase: SyncPhase.success,
          providerId: provider.id,
          message: '本地与远端已是最新',
          lastSyncedAt: syncedAt,
        ),
      );
      return updated;
    } on SyncConflictException catch (error) {
      _setStatus(
        SyncStatus(
          phase: SyncPhase.conflict,
          providerId: providerId,
          message: error.message,
          lastSyncedAt: settings.lastSyncedAt,
        ),
      );
      return settings;
    } catch (error) {
      return _fail(settings, _messageFor(error));
    }
  }

  Future<AppSettings> _push(
    SyncProvider provider,
    List<int> local,
    AppSettings settings,
    String localHash,
  ) async {
    _setStatus(SyncStatus(phase: SyncPhase.pushing, providerId: provider.id));
    final result = await provider.write(
      documentKey,
      local,
      expectedRevision: settings.syncRevision,
    );
    final syncedAt = DateTime.now().toUtc();
    final updated = settings.copyWith(
      syncRevision: result.revision,
      syncLocalHash: localHash,
      lastSyncedAt: syncedAt,
    );
    await repository.saveSettings(updated);
    _setStatus(
      SyncStatus(
        phase: SyncPhase.success,
        providerId: provider.id,
        message: '同步完成',
        lastSyncedAt: syncedAt,
      ),
    );
    return updated;
  }

  Future<SyncProvider> _createProvider(AppSettings settings) async {
    switch (settings.syncProvider) {
      case SyncProviderType.none:
        throw const SyncUnavailableException('尚未配置同步');
      case SyncProviderType.directory:
        if (settings.syncDirectoryPath.trim().isEmpty) {
          throw const SyncProviderException('请选择同步目录');
        }
        return DirectorySyncProvider(
          directory: Directory(settings.syncDirectoryPath.trim()),
        );
      case SyncProviderType.webdav:
        final uri = Uri.tryParse(settings.webDavUrl.trim());
        if (uri == null || !uri.hasScheme) {
          throw const SyncProviderException('WebDAV 地址无效');
        }
        final credentials = await credentialStore.readWebDav();
        if (credentials == null) {
          throw const SyncProviderException('WebDAV 密码尚未保存');
        }
        return WebDavSyncProvider(
          baseUrl: uri,
          username: settings.webDavUsername,
          password: credentials.password,
        );
      case SyncProviderType.selfHosted:
        final uri = Uri.tryParse(settings.selfHostedUrl.trim());
        if (uri == null || !uri.hasScheme) {
          throw const SyncProviderException('自建服务地址无效');
        }
        return SelfHostedApiSyncProvider(
          endpoint: uri,
          credentialStore: credentialStore,
        );
    }
  }

  Future<String> _hash(List<int> bytes) async {
    final value = await Sha256().hash(bytes);
    return base64Url.encode(value.bytes);
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
    _ => '同步失败：$error',
  };

  void _setStatus(SyncStatus value) {
    _status = value;
    notifyListeners();
  }
}
