// 设置对话框：按分区展示工作台偏好、安全、数据与同步配置。

import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../../domain/sync_credentials.dart';
import '../model_labels.dart';
import '../settings_models.dart';
import '../widgets/color_picker_section.dart';
import '../widgets/sync_settings_section.dart';
import 'settings_panel.dart' show isCloudSync;

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.settings,
    required this.credentialStore,
    this.currentDataPath = '',
    this.category,
    this.embedded = false,
    this.onSave,
    this.connectionTester,
  }) : assert(!embedded || onSave != null);

  final AppSettings settings;
  final SyncCredentialStore credentialStore;
  final String currentDataPath;
  final SettingsCategoryType? category;
  final bool embedded;
  final ValueChanged<SettingsResult>? onSave;
  final Future<void> Function(AppSettings, SyncCredentials)? connectionTester;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  // 工作台分区状态。
  late int _themeColorValue = widget.settings.themeColorValue;
  late int _backgroundColorValue = widget.settings.backgroundColorValue;
  late ProjectPriority _homeReminderPriorityThreshold =
      widget.settings.homeReminderPriorityThreshold;
  late bool _recordSubTodoCreatedAt = widget.settings.recordSubTodoCreatedAt;
  late bool _renameAttachmentsOnUpload =
      widget.settings.renameAttachmentsOnUpload;
  late bool _keepAttachmentExtensionOnRename =
      widget.settings.keepAttachmentExtensionOnRename;
  late bool _autoLockEnabled = widget.settings.autoLockEnabled;
  late final List<String> _serverTypes = [...widget.settings.serverTypes];
  final TextEditingController _newServerType = TextEditingController();

  // 本地数据分区状态。
  late final TextEditingController _localDataPath = TextEditingController(
    text: widget.currentDataPath,
  );

  // 同步分区（保存时经 GlobalKey 收集）。
  final _syncSectionKey = GlobalKey<SyncSettingsSectionState>();

  @override
  void dispose() {
    _newServerType.dispose();
    _localDataPath.dispose();
    super.dispose();
  }

  bool _shows(SettingsCategoryType category) =>
      widget.category == null || widget.category == category;

  Widget _buildFields(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_shows(SettingsCategoryType.workspace)) ...[
        const Text('外观', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        ColorPickerSection(
          initialBackgroundColor: _backgroundColorValue,
          initialThemeColor: _themeColorValue,
          onChanged: (background, theme) {
            _backgroundColorValue = background;
            _themeColorValue = theme;
          },
        ),
        const SizedBox(height: 22),
        const Text('工作台', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        DropdownButtonFormField<ProjectPriority>(
          key: const Key('home-reminder-priority-field'),
          initialValue: _homeReminderPriorityThreshold,
          decoration: const InputDecoration(
            labelText: '主页提醒优先级范围',
            helperText: '展示优先级不低于所选级别的未完成待办',
          ),
          items: ProjectPriority.values
              .map(
                (priority) => DropdownMenuItem(
                  value: priority,
                  child: Text(reminderPriorityRangeLabel(priority)),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _homeReminderPriorityThreshold = value);
            }
          },
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          key: const Key('record-subtodo-created-at'),
          contentPadding: EdgeInsets.zero,
          title: const Text('记录子任务添加时间'),
          subtitle: const Text('新建子任务时记录当前本地日期时间'),
          value: _recordSubTodoCreatedAt,
          onChanged: (value) => setState(() => _recordSubTodoCreatedAt = value),
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          key: const Key('rename-attachments-on-upload'),
          contentPadding: EdgeInsets.zero,
          title: const Text('上传附件时重命名'),
          subtitle: const Text('导入附件后弹出对话框以便修改文件名'),
          value: _renameAttachmentsOnUpload,
          onChanged: (value) =>
              setState(() => _renameAttachmentsOnUpload = value),
        ),
        SwitchListTile.adaptive(
          key: const Key('keep-attachment-extension-on-rename'),
          contentPadding: EdgeInsets.zero,
          title: const Text('重命名时保留文件扩展名'),
          subtitle: const Text('仅修改文件名主体部分，原扩展名保持不变'),
          value: _keepAttachmentExtensionOnRename,
          onChanged: (value) =>
              setState(() => _keepAttachmentExtensionOnRename = value),
        ),
        const SizedBox(height: 22),
        const Text('服务器类型', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text('用于硬件资产分类，例如物理服务器、虚拟机、NAS。'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newServerType,
                decoration: const InputDecoration(labelText: '新增服务器类型'),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                final type = _newServerType.text.trim();
                if (type.isNotEmpty && !_serverTypes.contains(type)) {
                  setState(() {
                    _serverTypes.add(type);
                    _newServerType.clear();
                  });
                }
              },
              child: const Text('添加'),
            ),
          ],
        ),
        if (_serverTypes.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _serverTypes
                .map(
                  (type) => InputChip(
                    label: Text(type),
                    onDeleted: () => setState(() => _serverTypes.remove(type)),
                  ),
                )
                .toList(),
          ),
        ],
      ],
      if (_shows(SettingsCategoryType.security)) ...[
        const SizedBox(height: 22),
        const Text('安全', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        SwitchListTile.adaptive(
          key: const Key('auto-lock-enabled'),
          contentPadding: EdgeInsets.zero,
          title: const Text('应用切到后台时自动锁定'),
          subtitle: const Text('锁定后需重新输入密码才能访问数据'),
          value: _autoLockEnabled,
          onChanged: (value) => setState(() => _autoLockEnabled = value),
        ),
      ],
      if (_shows(SettingsCategoryType.sync)) ...[
        const SizedBox(height: 22),
        const Text('数据与同步', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        SyncSettingsSection(
          key: _syncSectionKey,
          settings: widget.settings,
          credentialStore: widget.credentialStore,
          connectionTester: widget.connectionTester,
        ),
        if (!Platform.isAndroid &&
            !Platform.isIOS &&
            !isCloudSync(widget.settings.syncProvider)) ...[
          const SizedBox(height: 22),
          const Text('本地数据', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          TextField(
            controller: _localDataPath,
            readOnly: true,
            decoration: const InputDecoration(labelText: '本地数据文件存储路径'),
          ),
        ],
      ],
    ],
  );

  SettingsResult _result() {
    final sync = _syncSectionKey.currentState?.collect();
    return SettingsResult(
      settings: widget.settings.copyWith(
        themeColorValue: _themeColorValue,
        backgroundColorValue: _backgroundColorValue,
        homeReminderPriorityThreshold: _homeReminderPriorityThreshold,
        recordSubTodoCreatedAt: _recordSubTodoCreatedAt,
        renameAttachmentsOnUpload: _renameAttachmentsOnUpload,
        keepAttachmentExtensionOnRename: _keepAttachmentExtensionOnRename,
        autoLockEnabled: _autoLockEnabled,
        serverTypes: _serverTypes,
        syncProvider: sync?.provider == SyncProviderType.selfHosted
            ? SyncProviderType.none
            : sync?.provider ?? widget.settings.syncProvider,
        syncDirectoryPath:
            sync?.directoryPath ?? widget.settings.syncDirectoryPath,
        webDavUrl: sync?.webDavUrl ?? widget.settings.webDavUrl,
        webDavUsername: sync?.webDavUsername ?? widget.settings.webDavUsername,
        selfHostedUrl: sync?.selfHostedUrl ?? widget.settings.selfHostedUrl,
        s3Endpoint: sync?.s3Endpoint ?? widget.settings.s3Endpoint,
        s3Region: sync?.s3Region ?? widget.settings.s3Region,
        s3Bucket: sync?.s3Bucket ?? widget.settings.s3Bucket,
        s3Prefix: sync?.s3Prefix ?? widget.settings.s3Prefix,
        clearSyncState: sync?.clearSyncState ?? false,
      ),
      credentials: WebDavCredentials(password: sync?.webDavPassword ?? ''),
      selfHostedToken: sync?.selfHostedToken ?? '',
      s3: sync != null && sync.s3AccessKey.isNotEmpty && sync.s3SecretKey.isNotEmpty
          ? S3Credentials(
              accessKey: sync.s3AccessKey,
              secretKey: sync.s3SecretKey,
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final fields = _buildFields(context);
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          fields,
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => widget.onSave!(_result()),
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存设置'),
            ),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('设置'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: SingleChildScrollView(child: fields),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _result()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
