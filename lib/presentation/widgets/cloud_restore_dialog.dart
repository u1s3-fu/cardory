import 'package:flutter/material.dart';

import '../../sync/cloud_restore_service.dart';
import '../../domain/app_settings.dart';
import '../../domain/cardory_models.dart' show formatDateTime;
import '../cardory_theme.dart';
import '../../domain/sync_credentials.dart' show SyncCredentials;
import '../../sync/sync_models.dart' show SyncDocument;
import '../widgets/password_text_field.dart';

/// 首次启动时从云端恢复数据的向导对话框。
///
/// 步骤：
///  1. 选择服务类型（WebDAV / S3）
///  2. 填写连接配置并验证凭据
///  3. 展示可恢复的备份，确认后执行恢复
///
/// 各步骤均处理网络不可用、凭据无效、无可用备份、恢复中断等异常，
/// 并提供错误提示与重试。
class CloudRestoreDialog extends StatefulWidget {
  const CloudRestoreDialog({
    super.key,
    required this.service,
    this.existingSettings,
    this.onRestored,
  });

  final CloudRestoreService service;
  final AppSettings? existingSettings;

  /// 恢复成功后回调，参数为用于恢复的数据密码、合并后的设置，
  /// 以及本次连接所需的云存储凭据（WebDAV 密码 / S3 密钥）。
  final void Function(
    String password,
    AppSettings settings,
    SyncCredentials credentials,
  )? onRestored;

  /// 展示恢复向导。
  ///
  /// 返回 true 表示恢复成功，false 表示用户取消或恢复未完成。
  static Future<bool> show(
    BuildContext context, {
    required CloudRestoreService service,
    AppSettings? existingSettings,
    void Function(
      String password,
      AppSettings settings,
      SyncCredentials credentials,
    )? onRestored,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CloudRestoreDialog(
        service: service,
        existingSettings: existingSettings,
        onRestored: onRestored,
      ),
    );
    return ok ?? false;
  }

  @override
  State<CloudRestoreDialog> createState() => _CloudRestoreDialogState();
}

class _CloudRestoreDialogState extends State<CloudRestoreDialog> {
  static const _stepSelect = 0;
  static const _stepConfigure = 1;
  static const _stepBackup = 2;
  static const _stepRestore = 3;

  int _step = _stepSelect;

  // 服务选择
  CloudRestoreServiceType? _serviceType;

  // 连接配置控制器
  final _webDavUrl = TextEditingController();
  final _webDavUsername = TextEditingController();
  final _webDavPassword = TextEditingController();
  final _s3Endpoint = TextEditingController();
  final _s3Region = TextEditingController(text: 'us-east-1');
  final _s3Bucket = TextEditingController();
  final _s3Prefix = TextEditingController(text: 'cardory');
  final _s3AccessKey = TextEditingController();
  final _s3SecretKey = TextEditingController();

  // 数据解密密码
  final _dataPassword = TextEditingController();

  // 状态
  bool _busy = false;
  bool _connected = false;
  String? _error;
  SyncDocument? _backup;

  CloudRestoreConfig get _config {
    final type = _serviceType ?? CloudRestoreServiceType.webDav;
    switch (type) {
      case CloudRestoreServiceType.webDav:
        return CloudRestoreConfig(
          serviceType: type,
          webDavUrl: _webDavUrl.text,
          webDavUsername: _webDavUsername.text,
          webDavPassword: _webDavPassword.text,
        );
      case CloudRestoreServiceType.s3:
        return CloudRestoreConfig(
          serviceType: type,
          s3Endpoint: _s3Endpoint.text,
          s3Region: _s3Region.text,
          s3Bucket: _s3Bucket.text,
          s3Prefix: _s3Prefix.text,
          s3AccessKey: _s3AccessKey.text,
          s3SecretKey: _s3SecretKey.text,
        );
    }
  }

  @override
  void initState() {
    super.initState();
    _prefillFromSettings();
  }

  void _prefillFromSettings() {
    final settings = widget.existingSettings;
    if (settings == null) return;
    if (settings.webDavUrl.trim().isNotEmpty) {
      _webDavUrl.text = settings.webDavUrl;
      _webDavUsername.text = settings.webDavUsername;
    }
    if (settings.s3Endpoint.trim().isNotEmpty) {
      _s3Endpoint.text = settings.s3Endpoint;
      _s3Region.text = settings.s3Region.isEmpty ? 'us-east-1' : settings.s3Region;
      _s3Bucket.text = settings.s3Bucket;
      _s3Prefix.text =
          settings.s3Prefix.isEmpty ? 'cardory' : settings.s3Prefix;
    }
  }

  @override
  void dispose() {
    _webDavUrl.dispose();
    _webDavUsername.dispose();
    _webDavPassword.dispose();
    _s3Endpoint.dispose();
    _s3Region.dispose();
    _s3Bucket.dispose();
    _s3Prefix.dispose();
    _s3AccessKey.dispose();
    _s3SecretKey.dispose();
    _dataPassword.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final backup = await widget.service.loadBackup(
        _config,
        existingSettings: widget.existingSettings,
      );
      if (!mounted) return;
      setState(() {
        _connected = true;
        _backup = backup;
        if (backup != null) {
          _step = _stepBackup;
        } else {
          _error = '云端没有可恢复的备份数据。';
        }
      });
    } on CloudRestoreException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '连接云存储失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doRestore() async {
    if (_backup == null) return;
    if (_dataPassword.text.isEmpty) {
      setState(() => _error = '请输入数据密码以解密备份。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _step = _stepRestore;
    });
    try {
      // 一并读取云端配置，恢复到本地，保持本地与云端配置一致。
      final cloudConfig = await widget.service.loadCloudConfig(
        _config,
        existingSettings: widget.existingSettings,
      );
      final result = await widget.service.restore(
        _backup!,
        _dataPassword.text,
        config: _config,
        cloudConfig: cloudConfig,
      );
      widget.onRestored?.call(
        _dataPassword.text,
        result.settings,
        _config.toCredentials(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on CloudRestoreException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _step = _stepBackup;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '恢复数据失败：$error';
        _step = _stepBackup;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: _buildStepBody(theme),
                ),
              ),
              const SizedBox(height: 16),
              _buildActions(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.cloud_sync_outlined,
            color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            '从云端恢复数据',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: '取消',
          icon: const Icon(Icons.close),
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }

  Widget _buildStepBody(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        switch (_step) {
          _stepSelect => _buildServiceSelect(theme),
          _stepConfigure => _buildConfigure(theme),
          _stepBackup => _buildBackupList(theme),
          _ => _buildRestoring(theme),
        },
      ],
    );
  }

  Widget _buildServiceSelect(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('选择要恢复数据的云存储服务', style: theme.textTheme.titleSmall),
        const SizedBox(height: 16),
        _ServiceCard(
          icon: Icons.cloud_outlined,
          title: 'WebDAV',
          subtitle: '兼容 WebDAV 的云盘或自建服务器',
          selected: _serviceType == CloudRestoreServiceType.webDav,
          onTap: () => setState(
            () => _serviceType = CloudRestoreServiceType.webDav,
          ),
        ),
        const SizedBox(height: 12),
        _ServiceCard(
          icon: Icons.storage_outlined,
          title: 'S3 兼容存储',
          subtitle: 'Amazon S3 或兼容 S3 协议的对象存储',
          selected: _serviceType == CloudRestoreServiceType.s3,
          onTap: () => setState(
            () => _serviceType = CloudRestoreServiceType.s3,
          ),
        ),
      ],
    );
  }

  Widget _buildConfigure(ThemeData theme) {
    final isWebDav = _serviceType == CloudRestoreServiceType.webDav;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '填写 ${isWebDav ? 'WebDAV' : 'S3'} 连接配置',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 16),
        if (isWebDav) ...[
          TextField(
            controller: _webDavUrl,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'WebDAV 地址',
              hintText: 'https://example.com/webdav',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _webDavUsername,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          const SizedBox(height: 12),
          PasswordTextField(
            controller: _webDavPassword,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'WebDAV 密码'),
          ),
        ] else ...[
          TextField(
            controller: _s3Endpoint,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'S3 Endpoint',
              hintText: 'https://s3.amazonaws.com',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _s3Region,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'Region'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _s3Bucket,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'Bucket'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _s3Prefix,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Prefix（可选）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _s3AccessKey,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Access Key'),
          ),
          const SizedBox(height: 12),
          PasswordTextField(
            controller: _s3SecretKey,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: 'Secret Key'),
          ),
        ],
      ],
    );
  }

  Widget _buildBackupList(ThemeData theme) {
    final backup = _backup;
    if (backup == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: CardoryColors.gray400,
          ),
          const SizedBox(height: 12),
          Text(
            '云端没有可恢复的备份数据。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => setState(() {
              _connected = false;
              _backup = null;
              _error = null;
            }),
            icon: const Icon(Icons.refresh),
            label: const Text('重新连接'),
          ),
        ],
      );
    }
    final entry = CloudBackupEntry(
      serviceType: _serviceType ?? CloudRestoreServiceType.webDav,
      name: CloudRestoreService.documentKey,
      size: backup.bytes.length,
      modifiedAt: backup.modifiedAt,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('选择要恢复的备份', style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(
              entry.serviceType == CloudRestoreServiceType.webDav
                  ? Icons.cloud_outlined
                  : Icons.storage_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('最新数据备份'),
            subtitle: Text(
              '${entry.name} · ${entry.sizeLabel}'
              '${entry.modifiedAt != null ? ' · ${formatDateTime(entry.modifiedAt!)}' : ''}',
            ),
            selected: true,
          ),
        ),
        const SizedBox(height: 16),
        PasswordTextField(
          controller: _dataPassword,
          enabled: !_busy,
          decoration: const InputDecoration(
            labelText: '数据密码',
            hintText: '输入创建该备份时使用的密码',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '恢复将覆盖当前设备上的本地数据，请确认备份内容后继续。',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildRestoring(ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 16),
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text('正在从云端恢复数据…', textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildActions(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_step > _stepSelect)
          TextButton(
            onPressed:
                _busy || (_connected && _step == _stepBackup)
                    ? null
                    : () => setState(() {
                      _step = _step - 1;
                      _error = null;
                      if (_step == _stepConfigure) {
                        _connected = false;
                        _backup = null;
                      }
                    }),
            child: const Text('上一步'),
          ),
        const SizedBox(width: 8),
        if (_step == _stepSelect)
          FilledButton(
            onPressed: _serviceType == null || _busy
                ? null
                : () => setState(() {
                  _step = _stepConfigure;
                  _error = null;
                }),
            child: const Text('下一步'),
          )
        else if (_step == _stepConfigure)
          FilledButton(
            onPressed: _busy
                ? null
                : () => _connect(),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('连接并验证'),
          )
        else if (_step == _stepBackup)
          FilledButton.icon(
            onPressed: _busy ? null : () => _doRestore(),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_done_outlined),
            label: const Text('恢复'),
          ),
      ],
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? primary : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? primary.withValues(alpha: 0.08)
              : theme.colorScheme.surface,
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? primary : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: primary),
          ],
        ),
      ),
    );
  }
}
