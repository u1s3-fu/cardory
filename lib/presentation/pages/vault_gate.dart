import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/attachment_repository.dart';
import '../../domain/cardory_models.dart';
import '../../domain/cardory_repository.dart';
import '../../domain/sync_credentials.dart';
import '../../sync/cloud_restore_service.dart';
import '../../sync/local_backup_service.dart';
import '../cardory_logo.dart';
import '../cardory_theme.dart';
import '../widgets/cloud_restore_dialog.dart';
import '../widgets/password_text_field.dart';

/// 保险库门禁页：承担创建 / 解锁 / 云端恢复与错误重试。
///
/// 门禁页自身不渲染工作台：解锁成功后通过 [CardoryVaultGate.onUnlocked]
/// 把加载结果交还给应用层，由受保护路由 [workbenchRoutePath] 接管会话；
/// 应用进入后台的自动锁定也已上移到应用层统一处理。
class CardoryVaultGate extends StatefulWidget {
  const CardoryVaultGate({
    super.key,
    required this.vaultRepository,
    required this.workspaceRepository,
    required this.credentialStore,
    required this.vaultCredentialStore,
    required this.attachmentRepositoryFactory,
    required this.onSettingsChanged,
    required this.onUnlocked,
  });

  final VaultRepository vaultRepository;
  final WorkspaceRepository workspaceRepository;
  final SyncCredentialStore credentialStore;
  final VaultCredentialStore vaultCredentialStore;
  final AttachmentRepositoryFactory attachmentRepositoryFactory;
  final ValueChanged<AppSettings> onSettingsChanged;

  /// 解锁 / 自动解锁成功回调，携带加载结果。
  final void Function(CardoryLoadResult result) onUnlocked;

  @override
  State<CardoryVaultGate> createState() => _CardoryVaultGateState();
}

class _CardoryVaultGateState extends State<CardoryVaultGate> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  CardoryAccessState? _accessState;
  String? _error;
  bool _busy = false;
  bool _legacyDataDetected = false;

  /// 创建保险库前必须勾选的密码风险确认：密码是唯一解锁凭据，
  /// 没有恢复码、无法重置。
  bool _riskAcknowledged = false;

  @override
  void initState() {
    super.initState();
    _detectLegacyData();
    _inspect();
  }

  /// 检测旧版本（.cardory）数据文件。本版本不读取也不覆盖旧文件，
  /// 仅在「新建保险库」界面提示一次，让旧用户知晓旧数据不会被迁移。
  Future<void> _detectLegacyData() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final root = Directory(p.join(directory.path, 'Cardory'));
      final legacyData = File(
        p.join(root.path, 'cardory-current-data.cardory'),
      );
      final legacySettings = File(
        p.join(root.path, 'cardory-current-settings.json'),
      );
      final found =
          (await legacyData.exists()) || (await legacySettings.exists());
      if (mounted && found) {
        setState(() => _legacyDataDetected = true);
      }
    } catch (_) {
      // 目录不可访问时静默跳过，不影响保险库主流程。
    }
  }

  @override
  void dispose() {
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
        // 保险库已由外部会话打开：加载数据后把结果交给应用层进入工作台。
        final result = await widget.workspaceRepository.load();
        if (mounted) widget.onUnlocked(result);
      } else if (state == CardoryAccessState.locked) {
        final password = await widget.vaultCredentialStore.readPassword();
        if (password != null) {
          try {
            final result = await widget.vaultRepository.unlockWithPassword(
              password,
            );
            if (mounted) widget.onUnlocked(result);
            return;
          } on CardoryStorageException {
            // 已保存的密码无法解锁（密码错误或数据文件已损坏）：
            // 清除凭据，回落到手动输入界面，避免反复自动解锁失败。
            await widget.vaultCredentialStore.deletePassword();
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
    if (setup && !_riskAcknowledged) {
      setState(() => _error = '请先确认已了解忘记密码的风险。');
      return;
    }
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
      widget.onUnlocked(result);
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
    final service = CloudRestoreService(
      vaultRepository: widget.vaultRepository,
      attachmentRepositoryFactory: widget.attachmentRepositoryFactory,
    );
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

  /// 从本地备份包（.cardorybackup）恢复：选择文件 → 输入备份密码 →
  /// 整库替换并安装附件。恢复成功后以备份密码解锁进入工作台。
  Future<void> _restoreFromLocalBackup() async {
    if (_busy) return;
    setState(() => _error = null);
    final picked = await FilePicker.pickFiles(
      dialogTitle: '选择备份文件',
      type: FileType.any,
    );
    final archivePath = picked.isEmpty ? null : picked.single.path;
    if (archivePath == null || !mounted) return;
    if (!archivePath.endsWith(LocalBackupService.fileExtension)) {
      setState(
        () =>
            _error = '所选文件不是 Cardory 备份包（${LocalBackupService.fileExtension}）。',
      );
      return;
    }
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _BackupPasswordDialog(),
    );
    if (password == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await LocalBackupService(
        vaultRepository: widget.vaultRepository,
        attachmentRepositoryFactory: widget.attachmentRepositoryFactory,
      ).restore(archivePath: archivePath, password: password);
      // 以备份创建时的密码作为本机保险库密码，后续自动解锁沿用。
      await widget.vaultCredentialStore.writePassword(password);
      if (!mounted) return;
      widget.onUnlocked(result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_accessState == null) {
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
                child: Column(
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
                      setup ? '设置密码后，所有项目和待办都会加密保存。' : '输入密码以打开加密数据。',
                      textAlign: TextAlign.center,
                    ),
                    if (setup && _legacyDataDetected) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 20,
                              color: Colors.amber.shade900,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                '检测到旧版本数据文件（.cardory）。本版本使用新的加密数据库格式，'
                                '不会读取或覆盖旧文件，也不提供自动迁移；确认无用后请自行删除。',
                                style: TextStyle(fontSize: 12.5, height: 1.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              size: 20,
                              color: Colors.amber.shade900,
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                '密码是解锁数据的唯一凭据：没有恢复码、无法重置。'
                                '忘记密码将永久丢失全部数据，任何人都无法找回。',
                                style: TextStyle(fontSize: 12.5, height: 1.45),
                              ),
                            ),
                          ],
                        ),
                      ),
                      CheckboxListTile(
                        key: const Key('vault-risk-acknowledged'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        title: const Text(
                          '我已了解：忘记密码将无法找回数据，会妥善保管密码。',
                          style: TextStyle(fontSize: 13),
                        ),
                        value: _riskAcknowledged,
                        onChanged: (value) =>
                            setState(() => _riskAcknowledged = value ?? false),
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
                    if (setup) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        key: const Key('open-cloud-restore'),
                        onPressed: _busy ? null : _restoreFromCloud,
                        icon: const Icon(Icons.cloud_download_outlined),
                        label: const Text('从云端恢复'),
                      ),
                      TextButton.icon(
                        key: const Key('open-local-backup-restore'),
                        onPressed: _busy ? null : _restoreFromLocalBackup,
                        icon: const Icon(Icons.restore_outlined),
                        label: const Text('从本地备份恢复'),
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

/// 备份恢复的密码输入对话框：返回备份创建时使用的保险库密码。
class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog();

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty) return;
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('输入备份密码'),
    content: PasswordTextField(
      controller: _password,
      autofocus: true,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _submit(),
      decoration: const InputDecoration(
        labelText: '备份创建时使用的密码',
        prefixIcon: Icon(Icons.password),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _password.text.isEmpty ? null : _submit,
        child: const Text('恢复'),
      ),
    ],
  );
}
