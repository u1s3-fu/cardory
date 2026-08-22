// 设置对话框中的同步配置区。

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../domain/app_settings.dart';
import '../../domain/sync_credentials.dart';
import '../../sync/sync_models.dart';
import '../cardory_theme.dart';
import 'password_text_field.dart';

/// 同步配置区：提供同步方式选择、各提供者的字段与连接测试。
///
/// 表单状态自持；保存时通过 [SyncSettingsSectionState.collect] 一次性收集
/// 当前输入（由外层经 GlobalKey 调用）。
class SyncSettingsSection extends StatefulWidget {
  const SyncSettingsSection({
    super.key,
    required this.settings,
    required this.credentialStore,
    this.connectionTester,
  });

  /// 当前应用设置（用于判断同步端点是否变化）。
  final AppSettings settings;

  final SyncCredentialStore credentialStore;

  final Future<void> Function(AppSettings, SyncCredentials)? connectionTester;

  @override
  State<SyncSettingsSection> createState() => SyncSettingsSectionState();
}

/// [SyncSettingsSection] 的状态，提供保存时的取值入口。
class SyncSettingsSectionState extends State<SyncSettingsSection> {
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
  bool _hasStoredWebDavPassword = false;
  bool _hasStoredS3Credentials = false;
  bool _testingConnection = false;
  bool _connectionSucceeded = false;
  String? _connectionMessage;

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
    final current = _connectionSettings();
    return current.syncProvider != widget.settings.syncProvider ||
        current.syncDirectoryPath != widget.settings.syncDirectoryPath ||
        current.webDavUrl != widget.settings.webDavUrl ||
        current.webDavUsername != widget.settings.webDavUsername ||
        current.selfHostedUrl != widget.settings.selfHostedUrl ||
        current.s3Endpoint != widget.settings.s3Endpoint ||
        current.s3Region != widget.settings.s3Region ||
        current.s3Bucket != widget.settings.s3Bucket ||
        current.s3Prefix != widget.settings.s3Prefix;
  }

  void _clearConnectionResult() {
    if (_connectionMessage != null || _connectionSucceeded) {
      setState(() {
        _connectionMessage = null;
        _connectionSucceeded = false;
      });
    }
  }

  AppSettings _connectionSettings() => widget.settings.copyWith(
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
  );

  Future<void> _testConnection() async {
    if (_testingConnection) return;
    final tester = widget.connectionTester;
    if (tester == null) {
      setState(() {
        _testingConnection = false;
        _connectionSucceeded = false;
        _connectionMessage = '当前环境不支持连接测试';
      });
      return;
    }
    final settings = _connectionSettings();
    final credentials = widget.credentialStore.read();
    setState(() {
      _testingConnection = true;
      _connectionSucceeded = false;
      _connectionMessage = null;
    });
    try {
      final stored = await credentials;
      final missing = _missingCredentialHint(settings, stored);
      if (missing != null) {
        if (!mounted) return;
        setState(() {
          _testingConnection = false;
          _connectionMessage = missing;
        });
        return;
      }
      // 测试凭据采用"表单本次输入优先、已保存值兜底"，
      // 仅用于验证，不持久化任何值。
      await tester(settings, _testCredentials(stored));
      if (!mounted) return;
      setState(() {
        _testingConnection = false;
        _connectionSucceeded = true;
        _connectionMessage = '连接成功，可以保存设置。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _testingConnection = false;
        _connectionSucceeded = false;
        _connectionMessage = _friendlyConnectionError(error);
      });
    }
  }

  /// 检查当前同步方式是否缺少必要凭据；缺少时返回用户可操作的中文提示。
  String? _missingCredentialHint(AppSettings settings, SyncCredentials stored) {
    switch (settings.syncProvider) {
      case SyncProviderType.webdav:
        if (_webDavPassword.text.isEmpty && stored.webDav == null) {
          return '请先输入 WebDAV 密码后再测试连接';
        }
        return null;
      case SyncProviderType.s3:
        if ((_s3AccessKey.text.isEmpty || _s3SecretKey.text.isEmpty) &&
            stored.s3 == null) {
          return '请先输入 S3 Access Key 与 Secret Key 后再测试连接';
        }
        return null;
      default:
        return null;
    }
  }

  /// 构造用于连接测试的临时凭据：表单本次输入优先，为空时回退到已保存值。
  /// 与保存语义保持一致（密码留空表示保留已保存的凭据）。
  SyncCredentials _testCredentials(SyncCredentials stored) {
    final webDavPassword = _webDavPassword.text;
    final accessKey = _s3AccessKey.text.trim();
    final secretKey = _s3SecretKey.text;
    final hasWebDavInput = webDavPassword.isNotEmpty;
    final hasS3Input = accessKey.isNotEmpty && secretKey.isNotEmpty;
    if (!hasWebDavInput && !hasS3Input) return stored;
    return SyncCredentials(
      webDav: hasWebDavInput
          ? WebDavCredentials(password: webDavPassword)
          : stored.webDav,
      selfHostedToken: stored.selfHostedToken,
      s3: hasS3Input
          ? S3Credentials(accessKey: accessKey, secretKey: secretKey)
          : stored.s3,
    );
  }

  /// 将同步异常转换为用户友好的中文提示（避免依赖中文字面量匹配）。
  String _friendlyConnectionError(Object error) {
    if (error is SyncProviderException) {
      return switch (error.code) {
        SyncProviderErrorCode.webDavCredentialsMissing =>
          '未检测到已保存的 WebDAV 密码，请先在密码框中输入密码',
        SyncProviderErrorCode.s3CredentialsMissing =>
          '未检测到已保存的 S3 密钥，请先输入 Access Key 与 Secret Key',
        null => error.message,
      };
    }
    return error.toString();
  }

  Widget _connectionTestButton(String key) {
    if (_testingConnection) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('正在测试连接…'),
          ],
        ),
      );
    }
    if (_connectionSucceeded) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          _connectionMessage ?? '连接成功',
          style: TextStyle(
            color: CardoryColors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    if (_connectionMessage != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          _connectionMessage!,
          style: TextStyle(
            color: cardoryEnsureWhiteContrast(CardoryColors.error),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: Key(key),
          onPressed: _testConnection,
          icon: const Icon(Icons.wifi_tethering_rounded, size: 18),
          label: const Text('测试连接'),
        ),
      ),
    );
  }

  @override
  void dispose() {
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
    super.dispose();
  }

  /// 收集当前输入为保存结果。
  SyncSettingsResult collect() => SyncSettingsResult(
    provider: _syncProvider,
    directoryPath: _syncDirectory.text.trim(),
    webDavUrl: _webDavUrl.text.trim(),
    webDavUsername: _webDavUsername.text.trim(),
    webDavPassword: _webDavPassword.text,
    selfHostedUrl: _selfHostedUrl.text.trim(),
    selfHostedToken: _selfHostedToken.text,
    s3Endpoint: _s3Endpoint.text.trim(),
    s3Region: _s3Region.text.trim(),
    s3Bucket: _s3Bucket.text.trim(),
    s3Prefix: _s3Prefix.text.trim(),
    s3AccessKey: _s3AccessKey.text.trim(),
    s3SecretKey: _s3SecretKey.text,
    clearSyncState: _syncEndpointChanged(),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<SyncProviderType>(
          // 自建服务提供者保留为内部扩展点，
          // 但刻意不在设置界面中暴露。
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
    );
  }
}

/// [SyncSettingsSection] 在保存时收集的结果。
class SyncSettingsResult {
  const SyncSettingsResult({
    required this.provider,
    required this.directoryPath,
    required this.webDavUrl,
    required this.webDavUsername,
    required this.webDavPassword,
    required this.selfHostedUrl,
    required this.selfHostedToken,
    required this.s3Endpoint,
    required this.s3Region,
    required this.s3Bucket,
    required this.s3Prefix,
    required this.s3AccessKey,
    required this.s3SecretKey,
    required this.clearSyncState,
  });

  final SyncProviderType provider;
  final String directoryPath;
  final String webDavUrl;
  final String webDavUsername;
  final String webDavPassword;
  final String selfHostedUrl;
  final String selfHostedToken;
  final String s3Endpoint;
  final String s3Region;
  final String s3Bucket;
  final String s3Prefix;
  final String s3AccessKey;
  final String s3SecretKey;
  final bool clearSyncState;
}
