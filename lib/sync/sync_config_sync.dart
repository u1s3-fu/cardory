// 配置文档同步服务：将可同步的配置子集推送到云端 / 从云端拉取。

import 'dart:convert';

import '../domain/app_settings.dart';
import '../domain/cardory_repository.dart';
import 'sync_provider.dart';

/// 云端配置文档同步服务。
///
/// 读取/写入固定 key 的配置文档，采用"最后写入者获胜"策略：
/// - 本地有未同步的配置变更，且云端不更新 → 推送本地配置覆盖云端
/// - 云端配置比本地更新 → 拉取云端配置应用到本地
class CloudConfigSync {
  CloudConfigSync({required SyncRepository repository})
    : _repository = repository;

  /// 云端配置文档 key，与数据文档并列，保存可同步的配置子集。
  static const configKey = 'cardory-current-config.json';

  final SyncRepository _repository;

  /// 同步配置文档到云端（双向）。
  ///
  /// 返回更新后的 [AppSettings]，并持久化到本地。
  Future<AppSettings> sync(
    SyncProvider provider,
    AppSettings settings,
    Future<String> Function(List<int> bytes) hash,
  ) async {
    try {
      final localJson = settings.toSyncConfigJson();
      final localHash = await hash(utf8.encode(jsonEncode(localJson)));

      final cloudDoc = await provider.read(configKey);

      if (cloudDoc == null) {
        // 云端没有配置文档：若本地有未同步的配置，则上传。
        if (settings.configSyncHash != localHash) {
          return await _pushConfig(provider, settings, localJson, hash);
        }
        return settings;
      }

      final cloud = _decodeConfig(cloudDoc.bytes);
      if (cloud == null) {
        // 云端配置文档损坏，忽略，尝试用本地覆盖。
        if (settings.configSyncHash != localHash) {
          return await _pushConfig(provider, settings, localJson, hash);
        }
        return settings;
      }

      final cloudHash = await hash(utf8.encode(jsonEncode(cloud.settings)));
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
        return await _pushConfig(provider, settings, localJson, hash);
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
    Future<String> Function(List<int> bytes) hash,
  ) async {
    final now = DateTime.now().toUtc();
    final payload = {
      'v': 1,
      'updatedAt': now.toIso8601String(),
      'settings': localJson,
    };
    final bytes = utf8.encode(jsonEncode(payload));
    final localHash = await hash(utf8.encode(jsonEncode(localJson)));
    await provider.write(configKey, bytes);
    final updated = settings.copyWith(
      configSyncHash: localHash,
      lastConfigUpdatedAt: now,
    );
    await _repository.saveSettings(updated);
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
    await _repository.saveSettings(updated);
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
}
