import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../application/sync_status.dart';
import '../../domain/cardory_models.dart';
import '../../application/sync_credentials.dart';
import '../../sync/sync_credentials.dart' as provider_credentials;
import '../../sync/sync_provider_registry.dart' show testSyncConnection;
import '../cardory_theme.dart';
import '../model_labels.dart';
import '../settings_models.dart';
import '../widgets/password_text_field.dart';
import '../widgets/section_title.dart';

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
  final Future<void> Function(
    AppSettings,
    provider_credentials.SyncCredentials,
  )?
  connectionTester;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
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
  late SyncProviderType _syncProvider = widget.settings.syncProvider;
  late final TextEditingController _syncDirectory = TextEditingController(
    text: widget.settings.syncDirectoryPath,
  );
  late final TextEditingController _webDavUrl = TextEditingController(
    text: widget.settings.webDavUrl,
  );
  late final TextEditingController _webDavUsername = TextEditingController(
    text: widget.settings.webDavUsername,
  );
  final TextEditingController _webDavPassword = TextEditingController();
  late final TextEditingController _selfHostedUrl = TextEditingController(
    text: widget.settings.selfHostedUrl,
  );
  final TextEditingController _selfHostedToken = TextEditingController();
  late final TextEditingController _s3Endpoint = TextEditingController(
    text: widget.settings.s3Endpoint,
  );
  late final TextEditingController _s3Region = TextEditingController(
    text: widget.settings.s3Region,
  );
  late final TextEditingController _s3Bucket = TextEditingController(
    text: widget.settings.s3Bucket,
  );
  late final TextEditingController _s3Prefix = TextEditingController(
    text: widget.settings.s3Prefix,
  );
  final TextEditingController _s3AccessKey = TextEditingController();
  final TextEditingController _s3SecretKey = TextEditingController();
  late final TextEditingController _localDataPath = TextEditingController(
    text: widget.currentDataPath,
  );
  late final TextEditingController _themeHex = TextEditingController(
    text: _themeColorHex(_themeColorValue),
  );
  late final TextEditingController _backgroundHex = TextEditingController(
    text: _themeColorHex(_backgroundColorValue),
  );
  bool _hasStoredWebDavPassword = false;
  bool _hasStoredS3Credentials = false;
  bool _testingConnection = false;
  bool _connectionSucceeded = false;
  String? _connectionMessage;
  // 强调色预设（品牌主色）。
  static const _colors = [
    0xFF6B62DF,
    0xFF0EA5E9,
    0xFF12B76A,
    0xFFF97316,
    0xFFCF79DF,
    0xFFEF7180,
    0xFF101828,
  ];
  // 背景色预设（页面底色）。
  static const _backgroundColors = [
    0xFFF5F6FC,
    0xFFFFFFFF,
    0xFFFAFAF7,
    0xFFFDF6EC,
    0xFFF7F2E7,
    0xFF0D1117,
    0xFF161B22,
  ];

  int _colorChannel(double value) =>
      (value * 255).round().clamp(0, 255).toInt();

  void _setThemeColor(int value, {bool updateHex = true}) {
    setState(() => _themeColorValue = value);
    if (updateHex) _themeHex.text = _themeColorHex(value);
  }

  void _setThemeChannel({int? red, int? green, int? blue}) {
    final current = Color(_themeColorValue);
    _setThemeColor(
      Color.fromARGB(
        255,
        red ?? _colorChannel(current.r),
        green ?? _colorChannel(current.g),
        blue ?? _colorChannel(current.b),
      ).toARGB32(),
    );
  }

  void _setThemeHex(String value) {
    final normalized = value.replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return;
    _setThemeColor(
      0xFF000000 | int.parse(normalized, radix: 16),
      updateHex: false,
    );
  }

  void _setBackgroundColor(int value, {bool updateHex = true}) {
    setState(() => _backgroundColorValue = value);
    if (updateHex) _backgroundHex.text = _themeColorHex(value);
  }

  void _setBackgroundChannel({int? red, int? green, int? blue}) {
    final current = Color(_backgroundColorValue);
    _setBackgroundColor(
      Color.fromARGB(
        255,
        red ?? _colorChannel(current.r),
        green ?? _colorChannel(current.g),
        blue ?? _colorChannel(current.b),
      ).toARGB32(),
    );
  }

  void _setBackgroundHex(String value) {
    final normalized = value.replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return;
    _setBackgroundColor(
      0xFF000000 | int.parse(normalized, radix: 16),
      updateHex: false,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.credentialStore.read().then((credentials) {
      if (!mounted) return;
      setState(() {
        _hasStoredWebDavPassword = credentials.webDav != null;
        _hasStoredS3Credentials = credentials.s3 != null;
      });
    });
  }

  bool _syncEndpointChanged() {
    if (_syncProvider != widget.settings.syncProvider) return true;
    return switch (_syncProvider) {
      SyncProviderType.none => false,
      SyncProviderType.directory =>
        _syncDirectory.text.trim() != widget.settings.syncDirectoryPath,
      SyncProviderType.webdav =>
        _webDavUrl.text.trim() != widget.settings.webDavUrl ||
            _webDavUsername.text.trim() != widget.settings.webDavUsername,
      SyncProviderType.selfHosted =>
        _selfHostedUrl.text.trim() != widget.settings.selfHostedUrl,
      SyncProviderType.s3 =>
        _s3Endpoint.text.trim() != widget.settings.s3Endpoint ||
            _s3Region.text.trim() != widget.settings.s3Region ||
            _s3Bucket.text.trim() != widget.settings.s3Bucket ||
            _s3Prefix.text.trim() != widget.settings.s3Prefix,
    };
  }

  void _clearConnectionResult() {
    if (_connectionMessage == null) return;
    setState(() {
      _connectionMessage = null;
      _connectionSucceeded = false;
    });
  }

  AppSettings _connectionSettings() => widget.settings.copyWith(
    syncProvider: _syncProvider,
    webDavUrl: _webDavUrl.text.trim(),
    webDavUsername: _webDavUsername.text.trim(),
    s3Endpoint: _s3Endpoint.text.trim(),
    s3Region: _s3Region.text.trim(),
    s3Bucket: _s3Bucket.text.trim(),
    s3Prefix: _s3Prefix.text.trim(),
  );

  Future<void> _testConnection() async {
    if (_testingConnection) return;
    setState(() {
      _testingConnection = true;
      _connectionMessage = null;
      _connectionSucceeded = false;
    });
    try {
      final stored = await widget.credentialStore.read();
      final hasS3AccessKey = _s3AccessKey.text.trim().isNotEmpty;
      final hasS3SecretKey = _s3SecretKey.text.isNotEmpty;
      if (hasS3AccessKey != hasS3SecretKey) {
        throw StateError('S3 凭据必须同时填写 Access Key 和 Secret Key');
      }
      final credentials = provider_credentials.SyncCredentials(
        webDav: _webDavPassword.text.isEmpty
            ? stored.webDav == null
                  ? null
                  : provider_credentials.WebDavCredentials(
                      password: stored.webDav!.password,
                    )
            : provider_credentials.WebDavCredentials(
                password: _webDavPassword.text,
              ),
        selfHostedToken: stored.selfHostedToken,
        s3: !hasS3AccessKey
            ? stored.s3 == null
                  ? null
                  : provider_credentials.S3Credentials(
                      accessKey: stored.s3!.accessKey,
                      secretKey: stored.s3!.secretKey,
                    )
            : provider_credentials.S3Credentials(
                accessKey: _s3AccessKey.text.trim(),
                secretKey: _s3SecretKey.text,
              ),
      );
      await (widget.connectionTester ?? testSyncConnection)(
        _connectionSettings(),
        credentials,
      );
      if (!mounted) return;
      setState(() {
        _connectionSucceeded = true;
        _connectionMessage = '连接成功，可以保存设置。';
      });
    } catch (error) {
      debugPrint('Sync connection test failed: $error');
      if (!mounted) return;
      setState(() {
        _connectionSucceeded = false;
        _connectionMessage = '连接失败，请检查地址、凭据和访问权限后重试。';
      });
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  Widget _connectionTestButton(String key) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 14),
      OutlinedButton.icon(
        key: Key(key),
        onPressed: _testingConnection ? null : _testConnection,
        icon: _testingConnection
            ? const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.network_check_rounded),
        label: Text(_testingConnection ? '正在测试' : '测试连接'),
      ),
      if (_connectionMessage != null) ...[
        const SizedBox(height: 8),
        Text(
          _connectionMessage!,
          style: TextStyle(
            fontSize: 12.5,
            color: _connectionSucceeded
                ? CardoryColors.success
                : Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    ],
  );

  @override
  void dispose() {
    _newServerType.dispose();
    _syncDirectory.dispose();
    _webDavUrl.dispose();
    _webDavUsername.dispose();
    _webDavPassword.dispose();
    _selfHostedUrl.dispose();
    _selfHostedToken.dispose();
    _s3Endpoint.dispose();
    _s3Region.dispose();
    _s3Bucket.dispose();
    _s3Prefix.dispose();
    _s3AccessKey.dispose();
    _s3SecretKey.dispose();
    _localDataPath.dispose();
    _themeHex.dispose();
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
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: CardoryColors.gray25,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: CardoryColors.gray200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('背景色', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Color(_backgroundColorValue),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: CardoryColors.gray200),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final color in _backgroundColors)
                    _ColorDot(
                      color: color,
                      selected: _backgroundColorValue == color,
                      onTap: () => _setBackgroundColor(color),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _ColorChannelSlider(
                channel: 'red',
                label: '红',
                value: _colorChannel(Color(_backgroundColorValue).r),
                color: Colors.red,
                keyPrefix: 'background-color',
                onChanged: (value) => _setBackgroundChannel(red: value),
              ),
              _ColorChannelSlider(
                channel: 'green',
                label: '绿',
                value: _colorChannel(Color(_backgroundColorValue).g),
                color: Colors.green,
                keyPrefix: 'background-color',
                onChanged: (value) => _setBackgroundChannel(green: value),
              ),
              _ColorChannelSlider(
                channel: 'blue',
                label: '蓝',
                value: _colorChannel(Color(_backgroundColorValue).b),
                color: Colors.blue,
                keyPrefix: 'background-color',
                onChanged: (value) => _setBackgroundChannel(blue: value),
              ),
              TextField(
                controller: _backgroundHex,
                maxLength: 7,
                decoration: const InputDecoration(
                  labelText: '背景色十六进制',
                  hintText: '#F5F6FC',
                  counterText: '',
                ),
                onChanged: _setBackgroundHex,
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              const Text('强调色', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Color(_themeColorValue),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: CardoryColors.gray200),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final color in _colors)
                    _ColorDot(
                      color: color,
                      selected: _themeColorValue == color,
                      onTap: () => _setThemeColor(color),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _ColorChannelSlider(
                channel: 'red',
                label: '红',
                value: _colorChannel(Color(_themeColorValue).r),
                color: Colors.red,
                onChanged: (value) => _setThemeChannel(red: value),
              ),
              _ColorChannelSlider(
                channel: 'green',
                label: '绿',
                value: _colorChannel(Color(_themeColorValue).g),
                color: Colors.green,
                onChanged: (value) => _setThemeChannel(green: value),
              ),
              _ColorChannelSlider(
                channel: 'blue',
                label: '蓝',
                value: _colorChannel(Color(_themeColorValue).b),
                color: Colors.blue,
                onChanged: (value) => _setThemeChannel(blue: value),
              ),
              TextField(
                controller: _themeHex,
                maxLength: 7,
                decoration: const InputDecoration(
                  labelText: '强调色十六进制',
                  hintText: '#6B62DF',
                  counterText: '',
                ),
                onChanged: _setThemeHex,
              ),
            ],
          ),
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
          onChanged: _renameAttachmentsOnUpload
              ? (value) => setState(
                  () => _keepAttachmentExtensionOnRename = value,
                )
              : null,
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
        const Text('同步', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        DropdownButtonFormField<SyncProviderType>(
          // The self-hosted provider remains an internal extension point, but
          // is intentionally not exposed in the settings UI yet.
          initialValue: _syncProvider == SyncProviderType.selfHosted
              ? SyncProviderType.none
              : _syncProvider,
          decoration: const InputDecoration(labelText: '同步方式'),
          items: const [
            DropdownMenuItem(value: SyncProviderType.none, child: Text('不同步')),
            DropdownMenuItem(
              value: SyncProviderType.directory,
              child: Text('同步目录'),
            ),
            DropdownMenuItem(
              value: SyncProviderType.webdav,
              child: Text('WebDAV'),
            ),
            DropdownMenuItem(
              value: SyncProviderType.s3,
              child: Text('S3 兼容存储'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _syncProvider = value;
                _connectionMessage = null;
                _connectionSucceeded = false;
              });
            }
          },
        ),
        if (_syncProvider == SyncProviderType.directory) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _syncDirectory,
            decoration: InputDecoration(
              labelText: '同步目录',
              suffixIcon: IconButton(
                tooltip: '选择目录',
                onPressed: () async {
                  final selected = await FilePicker.platform.getDirectoryPath();
                  if (selected != null) _syncDirectory.text = selected;
                },
                icon: const Icon(Icons.folder_open_rounded),
              ),
            ),
          ),
        ],
        if (_syncProvider == SyncProviderType.webdav) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _webDavUrl,
            keyboardType: TextInputType.url,
            onChanged: (_) => _clearConnectionResult(),
            decoration: const InputDecoration(
              labelText: 'WebDAV 地址',
              hintText: 'https://dav.example.com/cardory/',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _webDavUsername,
            onChanged: (_) => _clearConnectionResult(),
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          const SizedBox(height: 12),
          PasswordTextField(
            controller: _webDavPassword,
            onChanged: (_) => _clearConnectionResult(),
            decoration: InputDecoration(
              labelText: _hasStoredWebDavPassword ? '密码（已保存）' : '密码',
              helperText: _hasStoredWebDavPassword
                  ? '留空将保留系统安全凭据存储中的密码'
              : '密码仅保存到系统安全凭据存储',
            ),
          ),
          _connectionTestButton('test-webdav-connection'),
        ],
        if (_syncProvider == SyncProviderType.s3) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _s3Endpoint,
            keyboardType: TextInputType.url,
            onChanged: (_) => _clearConnectionResult(),
            decoration: const InputDecoration(
              labelText: 'S3 Endpoint',
              hintText: 'https://s3.example.com',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _s3Region,
            onChanged: (_) => _clearConnectionResult(),
            decoration: const InputDecoration(
              labelText: '区域（Region）',
              hintText: 'us-east-1',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _s3Bucket,
            onChanged: (_) => _clearConnectionResult(),
            decoration: const InputDecoration(labelText: '存储桶（Bucket）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _s3Prefix,
            onChanged: (_) => _clearConnectionResult(),
            decoration: const InputDecoration(
              labelText: '对象前缀',
              hintText: 'cardory',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _s3AccessKey,
            onChanged: (_) => _clearConnectionResult(),
            decoration: InputDecoration(
              labelText: _hasStoredS3Credentials
                  ? 'Access Key（已保存）'
                  : 'Access Key',
              helperText: _hasStoredS3Credentials ? '留空将保留已保存的密钥' : null,
            ),
          ),
          const SizedBox(height: 12),
          PasswordTextField(
            controller: _s3SecretKey,
            onChanged: (_) => _clearConnectionResult(),
            decoration: InputDecoration(
              labelText: _hasStoredS3Credentials
                  ? 'Secret Key（已保存）'
                  : 'Secret Key',
              helperText: _hasStoredS3Credentials
                  ? '留空将保留已保存的密钥'
              : '密钥仅保存到系统安全凭据存储',
            ),
          ),
          _connectionTestButton('test-s3-connection'),
        ],
      ],
      if (_shows(SettingsCategoryType.localData) &&
          !Platform.isAndroid &&
          !Platform.isIOS &&
          !_isCloudSync(widget.settings.syncProvider)) ...[
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
  );

  SettingsResult _result() => SettingsResult(
    settings: widget.settings.copyWith(
      themeColorValue: _themeColorValue,
      backgroundColorValue: _backgroundColorValue,
      homeReminderPriorityThreshold: _homeReminderPriorityThreshold,
      recordSubTodoCreatedAt: _recordSubTodoCreatedAt,
      renameAttachmentsOnUpload: _renameAttachmentsOnUpload,
      keepAttachmentExtensionOnRename: _keepAttachmentExtensionOnRename,
      autoLockEnabled: _autoLockEnabled,
      serverTypes: _serverTypes,
      syncProvider: _syncProvider == SyncProviderType.selfHosted
          ? SyncProviderType.none
          : _syncProvider,
      syncDirectoryPath: _syncDirectory.text.trim(),
      webDavUrl: _webDavUrl.text.trim(),
      webDavUsername: _webDavUsername.text.trim(),
      selfHostedUrl: _selfHostedUrl.text.trim(),
      s3Endpoint: _s3Endpoint.text.trim(),
      s3Region: _s3Region.text.trim(),
      s3Bucket: _s3Bucket.text.trim(),
      s3Prefix: _s3Prefix.text.trim(),
      clearSyncState: _syncEndpointChanged(),
    ),
    credentials: WebDavCredentials(password: _webDavPassword.text),
    selfHostedToken: _selfHostedToken.text,
    s3: _s3AccessKey.text.trim().isNotEmpty &&
            _s3SecretKey.text.isNotEmpty
        ? S3Credentials(
            accessKey: _s3AccessKey.text.trim(),
            secretKey: _s3SecretKey.text,
          )
        : null,
  );

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

/// 可点的预设色圆点，用于设置面板的颜色快捷选择。
class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorHex = _themeColorHex(color);
    return Semantics(
      button: true,
      selected: selected,
      label: '选择颜色 $colorHex',
      child: Tooltip(
        message: '选择 $colorHex',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(color),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? CardoryColors.primary
                        : CardoryColors.gray200,
                    width: selected ? 3 : 1,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorChannelSlider extends StatelessWidget {
  const _ColorChannelSlider({
    required this.channel,
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
    this.keyPrefix = 'theme-color',
  });

  final String channel;
  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 20, child: Text(label)),
      Expanded(
        child: Slider(
          key: ValueKey('$keyPrefix-$channel-slider'),
          value: value.toDouble(),
          min: 0,
          max: 255,
          activeColor: color,
          onChanged: (value) => onChanged(value.round()),
        ),
      ),
      SizedBox(
        width: 34,
        child: Text(value.toString(), textAlign: TextAlign.right),
      ),
    ],
  );
}

String _themeColorHex(int value) =>
    '#${value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

/// 是否为云同步方式（远程/云端存储），用于决定是否隐藏本地数据选项。
bool _isCloudSync(SyncProviderType type) => switch (type) {
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
    required this.dataPath,
    required this.syncStatus,
    required this.onSync,
    required this.onOpenSettings,
    required this.onChangePassword,
    required this.onRestoreBackup,
  });

  final AppSettings settings;
  final String dataPath;
  final SyncStatus syncStatus;
  final VoidCallback onSync;
  final ValueChanged<SettingsCategoryType> onOpenSettings;
  final VoidCallback onChangePassword;
  final VoidCallback onRestoreBackup;

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
          title: '同步',
          description: '同步方式：${_syncProviderLabel(settings.syncProvider)}',
          onPressed: () => onOpenSettings(SettingsCategoryType.sync),
        ),
        if (!Platform.isAndroid &&
            !Platform.isIOS &&
            !_isCloudSync(settings.syncProvider)) ...[
          const SizedBox(height: 10),
          _SettingsCategory(
            icon: Icons.folder_outlined,
            title: '本地数据',
            description: '数据文件：$dataPath',
            onPressed: () => onOpenSettings(SettingsCategoryType.localData),
          ),
        ],
        const SizedBox(height: 14),
        Text(
          _syncStatusText(syncStatus, settings),
          style: TextStyle(
            fontSize: 12.5,
            color:
                syncStatus.phase == SyncPhase.failure ||
                    syncStatus.phase == SyncPhase.conflict
                ? CardoryColors.error
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
    // Reserved provider: keep persisted data compatible without exposing it.
    SyncProviderType.selfHosted => '未启用',
    SyncProviderType.s3 => 'S3 兼容存储',
  };

  static String _syncStatusText(SyncStatus status, AppSettings settings) {
    if (status.message != null) return status.message!;
    final last = settings.lastSyncedAt;
    if (last == null) return '尚未同步';
    final local = last.toLocal();
    return '上次同步：${formatDate(local)} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
