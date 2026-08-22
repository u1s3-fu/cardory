import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../domain/attachment_repository.dart';
import '../../domain/cardory_repository.dart';
import '../../domain/sync_credentials.dart';
import '../../domain/widget_data_service.dart';
import '../../sync/cloud_restore_service.dart';
import '../../application/workspace_controller_factory.dart';
import '../../domain/cardory_container.dart';
import '../../domain/cardory_models.dart';
import '../../sync/sync_provider.dart';
import '../cardory_logo.dart';
import '../cardory_theme.dart';
import '../vault_auto_lock_controller.dart';
import '../widgets/cloud_restore_dialog.dart';
import '../widgets/password_text_field.dart';
import 'home_page.dart';

class CardoryVaultGate extends StatefulWidget {
  const CardoryVaultGate({
    super.key,
    required this.vaultRepository,
    required this.workspaceRepository,
    required this.controllerFactory,
    this.vaultSession,
    required this.credentialStore,
    required this.vaultCredentialStore,
    required this.providerFactory,
    required this.autoLockEnabled,
    required this.onSettingsChanged,
    this.widgetDataService,
    required this.attachmentRepositoryFactory,
    this.connectionTester,
  });

  final VaultRepository vaultRepository;
  final WorkspaceRepository workspaceRepository;
  final VaultSessionRepository? vaultSession;
  final SyncCredentialStore credentialStore;
  final VaultCredentialStore vaultCredentialStore;
  final SyncProviderFactory providerFactory;
  final WorkspaceControllerFactory controllerFactory;
  final bool autoLockEnabled;
  final WidgetDataService? widgetDataService;
  final AttachmentRepositoryFactory attachmentRepositoryFactory;
  final Future<void> Function(
    AppSettings,
    SyncCredentials,
  )? connectionTester;
  final ValueChanged<AppSettings> onSettingsChanged;

  @override
  State<CardoryVaultGate> createState() => _CardoryVaultGateState();
}

class _CardoryVaultGateState extends State<CardoryVaultGate> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  CardoryAccessState? _accessState;
  CardoryLoadResult? _result;
  String? _error;
  bool _busy = false;
  bool _restoreFromBackup = false;
  List<int>? _restoreBytes;
  String? _restoreFileName;
  late final VaultAutoLockController _autoLockController;

  @override
  void initState() {
    super.initState();
    _autoLockController = VaultAutoLockController(onLock: _lockVault)
      ..setEnabled(widget.autoLockEnabled)
      ..start();
    _inspect();
  }

  Future<void> _lockVault() async {
    await widget.vaultSession?.lock();
    await widget.vaultCredentialStore.deletePassword();
    if (!mounted) return;
    setState(() {
      _result = null;
      _accessState = CardoryAccessState.locked;
      _password.clear();
    });
  }

  @override
  void didUpdateWidget(covariant CardoryVaultGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoLockEnabled != widget.autoLockEnabled) {
      _autoLockController.setEnabled(widget.autoLockEnabled);
    }
  }

  @override
  void dispose() {
    _autoLockController.stop();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _inspect() async {
    if (mounted) setState(() => _error = null);
    try {
      final state = await widget.vaultRepository.accessState();
      if (!mounted) return;
      if (state == CardoryAccessState.unlocked) {
        final result = await widget.workspaceRepository.load();
        if (mounted) setState(() => _result = result);
      } else if (state == CardoryAccessState.locked) {
        final password = await widget.vaultCredentialStore.readPassword();
        if (password != null) {
          try {
            final result = await widget.vaultRepository.unlockWithPassword(
              password,
            );
            if (mounted) setState(() => _result = result);
            return;
          } on CardoryStorageException catch (error) {
            final cause = error.cause;
            if (cause is CardoryContainerException &&
                cause.error == CardoryContainerError.invalidCredential) {
              await widget.vaultCredentialStore.deletePassword();
            } else {
              rethrow;
            }
          }
        }
        if (mounted) setState(() => _accessState = state);
      } else {
        if (mounted) setState(() => _accessState = state);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final setup = _accessState == CardoryAccessState.setupRequired;
    if (setup && _password.text != _confirmation.text) {
      setState(() => _error = '两次输入的密码不一致。');
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = '密码至少需要 8 个字符。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = setup
          ? await widget.vaultRepository.setup(_password.text)
          : await widget.vaultRepository.unlockWithPassword(_password.text);
      await widget.vaultCredentialStore.writePassword(_password.text);
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _pickRestoreBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['cardory'],
        allowMultiple: false,
        withData: true,
      );
      if (result == null || !mounted) return;
      final file = result.files.single;
      if (file.bytes == null) {
        setState(() => _error = '无法读取所选备份文件。');
        return;
      }
      setState(() {
        _restoreBytes = file.bytes;
        _restoreFileName = file.name;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '选择备份文件失败：$error');
    }
  }

  Future<void> _restoreBackup() async {
    if (_busy) return;
    final bytes = _restoreBytes;
    if (bytes == null) {
      setState(() => _error = '请先选择 .cardory 备份文件。');
      return;
    }
    if (_password.text.length < 8) {
      setState(() => _error = '密码至少需要 8 个字符。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.vaultRepository.restoreFromBackup(
        bytes,
        _password.text,
      );
      await widget.vaultCredentialStore.writePassword(_password.text);
      if (!mounted) return;
      setState(() {
        _result = result;
        _restoreFromBackup = false;
        _busy = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  /// 从云端（WebDAV / S3）恢复数据。
  Future<void> _restoreFromCloud() async {
    if (_busy) return;
    setState(() => _error = null);
    final service = CloudRestoreService(vaultRepository: widget.vaultRepository);
    final ok = await CloudRestoreDialog.show(
      context,
      service: service,
      onRestored: (password, settings, credentials) async {
        // 保存数据密码以便后续自动解锁。
        await widget.vaultCredentialStore.writePassword(password);
        // 保存云同步凭据（WebDAV 密码 / S3 密钥），确保后续同步可正常认证。
        await widget.credentialStore.write(credentials);
        // 保存合并了云端配置与本次连接配置的设置。
        widget.onSettingsChanged(settings);
      },
    );
    if (!mounted) return;
    if (ok) {
      // 恢复成功，重新检测保险库状态以进入应用。
      await _inspect();
    }
  }

  Widget _buildRestoreForm(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(Icons.restore_rounded, size: 48),
      const SizedBox(height: 16),
      const Text(
        '从备份恢复',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        key: const Key('pick-cardory-backup'),
        onPressed: _busy ? null : _pickRestoreBackup,
        icon: const Icon(Icons.folder_open_rounded),
        label: Text(_restoreFileName ?? '选择 .cardory 备份'),
      ),
      const SizedBox(height: 12),
      PasswordTextField(
        fieldKey: const Key('restore-password'),
        controller: _password,
        autofocus: true,
        onSubmitted: (_) => _restoreBackup(),
        decoration: const InputDecoration(
          labelText: '备份密码',
          helperText: '输入创建此备份时使用的密码',
          prefixIcon: Icon(Icons.password_rounded),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(
          _error!,
          style: TextStyle(
            color: cardoryEnsureWhiteContrast(CardoryColors.error),
          ),
        ),
      ],
      const SizedBox(height: 20),
      FilledButton.icon(
        key: const Key('restore-cardory-backup'),
        onPressed: _busy ? null : _restoreBackup,
        icon: const Icon(Icons.restore_rounded),
        label: Text(_busy ? '恢复中…' : '用备份密码恢复'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _busy
            ? null
            : () => setState(() {
                _restoreFromBackup = false;
                _error = null;
              }),
        child: const Text('返回'),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_result != null) {
      return HomePage(
        controllerFactory: widget.controllerFactory,
        vaultRepository: widget.vaultRepository,
        credentialStore: widget.credentialStore,
        vaultCredentialStore: widget.vaultCredentialStore,
        onSettingsChanged: widget.onSettingsChanged,
        initialResult: _result,
        attachmentRepositoryFactory: widget.attachmentRepositoryFactory,
        connectionTester: widget.connectionTester,
      );
    }
    if (_accessState == null && _result == null) {
      if (_error != null) {
        return Scaffold(
          body: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 42,
                      color: cardoryEnsureWhiteContrast(
                        CardoryColors.error,
                        minRatio: 3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      '无法加载本地数据',
                      style: TextStyle(
                        fontSize: 18,
                        letterSpacing: -0.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(_error!),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _inspect,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final setup = _accessState == CardoryAccessState.setupRequired;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: _restoreFromBackup
                    ? _buildRestoreForm(context)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const CardoryLogo(size: 56),
                          const SizedBox(height: 16),
                          Text(
                            setup ? '保护你的 Cardory 数据' : '解锁 Cardory',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              letterSpacing: -0.3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            setup
                                ? '设置密码后，所有项目和待办都会加密保存。'
                                : '输入密码以打开加密数据。',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          PasswordTextField(
                            controller: _password,
                            autofocus: true,
                            onSubmitted: (_) => _submit(),
                            decoration: const InputDecoration(
                              labelText: '密码',
                              prefixIcon: Icon(Icons.password),
                            ),
                          ),
                          if (setup) ...[
                            const SizedBox(height: 12),
                            PasswordTextField(
                              controller: _confirmation,
                              onSubmitted: (_) => _submit(),
                              decoration: const InputDecoration(
                                labelText: '确认密码',
                                prefixIcon: Icon(Icons.password),
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: cardoryEnsureWhiteContrast(
                                  CardoryColors.error,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _busy ? null : _submit,
                            child: Text(
                              _busy
                                  ? '处理中…'
                                  : setup
                                  ? '创建加密保险库'
                                  : '解锁',
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            key: const Key('open-backup-restore'),
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _restoreFromBackup = true;
                                    _error = null;
                                  }),
                            icon: const Icon(Icons.restore_rounded),
                            label: const Text('从备份恢复'),
                          ),
                          if (setup) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              key: const Key('open-cloud-restore'),
                              onPressed: _busy ? null : _restoreFromCloud,
                              icon: const Icon(Icons.cloud_download_outlined),
                              label: const Text('从云端恢复'),
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
