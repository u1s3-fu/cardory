// 设置对话框：按分区展示工作台偏好、安全、数据与同步配置。

import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/asset_template.dart';
import '../../domain/cardory_models.dart';
import '../../domain/sync_credentials.dart';
import '../model_labels.dart';
import '../settings_models.dart';
import '../widgets/color_picker_section.dart';
import '../widgets/sync_settings_section.dart';
import 'asset_template_editor_dialog.dart';
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
  late final List<AssetTemplate> _assetTemplates = [
    ...widget.settings.assetTemplates,
  ];

  // 本地数据分区状态。
  late final TextEditingController _localDataPath = TextEditingController(
    text: widget.currentDataPath,
  );

  // 同步分区（保存时经 GlobalKey 收集）。
  final _syncSectionKey = GlobalKey<SyncSettingsSectionState>();

  @override
  void dispose() {
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
        const Text('资产模板', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        const Text('控制登记资产时可用的类型模板；可禁用内置模板，或新增自定义模板。'),
        const SizedBox(height: 10),
        for (var index = 0; index < _assetTemplates.length; index++)
          CheckboxListTile(
            key: Key('asset-template-${_assetTemplates[index].id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(_assetTemplates[index].name),
            subtitle: Text(_templateFieldSummary(_assetTemplates[index])),
            value: _assetTemplates[index].enabled,
            onChanged: (value) => setState(() {
              _assetTemplates[index] = _assetTemplates[index].copyWith(
                enabled: value ?? true,
              );
            }),
            secondary: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_assetTemplates[index].builtIn)
                  IconButton(
                    key: Key('edit-template-${_assetTemplates[index].id}'),
                    tooltip: '编辑模板',
                    onPressed: () => _editTemplate(index),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                // 所有模板（含内置）均可删除；内置模板删除后仍可作为
                // 自定义模板重建，旧数据由字段 key 兜底渲染。
                IconButton(
                  key: Key('delete-template-${_assetTemplates[index].id}'),
                  tooltip: '删除模板',
                  onPressed: () => _deleteTemplate(index),
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(
            key: const Key('add-asset-template'),
            onPressed: _addTemplate,
            icon: const Icon(Icons.add),
            label: const Text('新增自定义模板'),
          ),
        ),
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

  static String _templateFieldSummary(AssetTemplate template) =>
      template.fields.isEmpty
      ? '无自定义字段'
      : template.fields.map((f) => f.label).join('、');

  Future<void> _addTemplate() async {
    final template = await showDialog<AssetTemplate>(
      context: context,
      builder: (_) => const AssetTemplateEditorDialog(),
    );
    if (template == null) return;
    setState(() => _assetTemplates.add(template));
  }

  Future<void> _editTemplate(int index) async {
    final template = await showDialog<AssetTemplate>(
      context: context,
      builder: (_) =>
          AssetTemplateEditorDialog(initial: _assetTemplates[index]),
    );
    if (template == null) return;
    setState(() => _assetTemplates[index] = template);
  }

  Future<void> _deleteTemplate(int index) async {
    final template = _assetTemplates[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除模板'),
        content: Text('删除模板「${template.name}」？已登记的该类型资产将回退为通用字段展示。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _assetTemplates.removeAt(index));
  }

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
        assetTemplates: List.of(_assetTemplates),
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
      s3:
          sync != null &&
              sync.s3AccessKey.isNotEmpty &&
              sync.s3SecretKey.isNotEmpty
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
