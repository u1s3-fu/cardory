// 设置面板（工作台“设置”分区的入口卡片）。

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../../domain/sync_status.dart';
import '../cardory_theme.dart';
import '../model_labels.dart';
import '../settings_models.dart';
import '../widgets/section_title.dart';

/// 是否为云同步方式（远程/云端存储），用于决定是否隐藏本地数据选项。
bool isCloudSync(SyncProviderType type) => switch (type) {
  SyncProviderType.none => false,
  SyncProviderType.directory => false,
  SyncProviderType.webdav => true,
  SyncProviderType.selfHosted => true,
  SyncProviderType.s3 => true,
};

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.settings,
    required this.syncStatus,
    required this.onSync,
    required this.onOpenSettings,
    required this.onChangePassword,
    required this.onRestoreBackup,
    required this.onShowAbout,
  });

  final AppSettings settings;
  final SyncStatus syncStatus;
  final VoidCallback onSync;
  final ValueChanged<SettingsCategoryType> onOpenSettings;
  final VoidCallback onChangePassword;
  final VoidCallback onRestoreBackup;
  final VoidCallback onShowAbout;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: '设置', subtitle: '分别管理工作台、安全与同步'),
        const SizedBox(height: 16),
        _SettingsCategory(
          icon: Icons.tune_rounded,
          title: '工作台偏好',
          description:
              '主页提醒：${reminderPriorityRangeLabel(settings.homeReminderPriorityThreshold)}',
          onPressed: () => onOpenSettings(SettingsCategoryType.workspace),
        ),
        const SizedBox(height: 10),
        _SettingsCategory(
          icon: Icons.shield_outlined,
          title: '安全',
          description: settings.autoLockEnabled
              ? '切到后台时自动锁定已开启'
              : '切到后台时自动锁定已关闭',
          onPressed: () => onOpenSettings(SettingsCategoryType.security),
        ),
        const SizedBox(height: 10),
        _SettingsCategory(
          icon: Icons.sync_rounded,
          title: '数据与同步',
          description: '同步方式：${_syncProviderLabel(settings.syncProvider)}',
          onPressed: () => onOpenSettings(SettingsCategoryType.sync),
        ),
        const SizedBox(height: 10),
        _SettingsCategory(
          icon: Icons.info_outline_rounded,
          title: '关于',
          description: '版本、许可证与开源仓库信息',
          onPressed: onShowAbout,
        ),
        const SizedBox(height: 14),
        Text(
          _syncStatusText(syncStatus, settings),
          style: TextStyle(
            fontSize: 12.5,
            color:
                syncStatus.phase == SyncPhase.failure ||
                    syncStatus.phase == SyncPhase.conflict
                ? cardoryEnsureWhiteContrast(CardoryColors.error)
                : CardoryColors.gray500,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed:
                  settings.syncProvider == SyncProviderType.none ||
                      syncStatus.isRunning ||
                      settings.syncProvider == SyncProviderType.selfHosted
                  ? null
                  : onSync,
              icon: syncStatus.isRunning
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(syncStatus.isRunning ? '同步中' : '立即同步'),
            ),
            OutlinedButton.icon(
              onPressed: onChangePassword,
              icon: const Icon(Icons.password_rounded),
              label: const Text('修改密码'),
            ),
            OutlinedButton.icon(
              key: const Key('restore-data-backup'),
              onPressed: onRestoreBackup,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('恢复数据'),
            ),
          ],
        ),
      ],
    ),
  );

  static String _syncProviderLabel(SyncProviderType value) => switch (value) {
    SyncProviderType.none => '未启用',
    SyncProviderType.directory => '同步目录',
    SyncProviderType.webdav => 'WebDAV',
    // 保留提供者：维持持久化数据兼容性而不对外暴露。
    SyncProviderType.selfHosted => '未启用',
    SyncProviderType.s3 => 'S3 兼容存储',
  };

  static String _syncStatusText(SyncStatus status, AppSettings settings) {
    if (status.message != null) return status.message!;
    final last = settings.lastSyncedAt;
    if (last == null) return '尚未同步';
    final local = last.toLocal();
    return '上次同步：${formatDateTime(local)}';
  }
}

class _SettingsCategory extends StatelessWidget {
  const _SettingsCategory({
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: CardoryColors.gray50,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CardoryColors.gray500,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: CardoryColors.gray400),
          ],
        ),
      ),
    ),
  );
}
