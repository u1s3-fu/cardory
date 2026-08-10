import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'application/vault_auto_lock_controller.dart';
import 'data/cardory_store.dart';
import 'domain/cardory_container.dart';
import 'domain/cardory_models.dart';
import 'presentation/cardory_logo.dart';
import 'presentation/cardory_theme.dart';
import 'presentation/model_colors.dart';
import 'sync/sync_coordinator.dart';
import 'sync/sync_credentials.dart';
import 'sync/sync_models.dart';

void main() {
  runApp(
    CardoryApp(
      repository: CardoryStore(),
      credentialStore: SecureSyncCredentialStore(),
    ),
  );
}

class CardoryApp extends StatefulWidget {
  CardoryApp({
    super.key,
    required this.repository,
    SyncCredentialStore? credentialStore,
    VaultCredentialStore? vaultCredentialStore,
  }) : credentialStore = credentialStore ?? SecureSyncCredentialStore(),
       vaultCredentialStore =
           vaultCredentialStore ?? SecureVaultCredentialStore();

  final CardoryRepository repository;
  final SyncCredentialStore credentialStore;
  final VaultCredentialStore vaultCredentialStore;

  @override
  State<CardoryApp> createState() => _CardoryAppState();
}

class _CardoryAppState extends State<CardoryApp> {
  AppSettings _settings = const AppSettings();

  void _applySettings(AppSettings settings) =>
      setState(() => _settings = settings);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '板记 Cardory',
      debugShowCheckedModeBanner: false,
      theme: buildCardoryTheme(
        _settings.themeColor,
        background: Color(_settings.backgroundColorValue),
      ),
      home: CardoryVaultGate(
        repository: widget.repository,
        credentialStore: widget.credentialStore,
        vaultCredentialStore: widget.vaultCredentialStore,
        autoLockEnabled: _settings.autoLockEnabled,
        onSettingsChanged: _applySettings,
      ),
    );
  }
}

class CardoryVaultGate extends StatefulWidget {
  const CardoryVaultGate({
    super.key,
    required this.repository,
    required this.credentialStore,
    required this.vaultCredentialStore,
    required this.autoLockEnabled,
    required this.onSettingsChanged,
  });

  final CardoryRepository repository;
  final SyncCredentialStore credentialStore;
  final VaultCredentialStore vaultCredentialStore;
  final bool autoLockEnabled;
  final ValueChanged<AppSettings> onSettingsChanged;

  @override
  State<CardoryVaultGate> createState() => _CardoryVaultGateState();
}

class _CardoryVaultGateState extends State<CardoryVaultGate> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _recoveryKey = TextEditingController();
  final _replacementPassword = TextEditingController();
  final _replacementConfirmation = TextEditingController();
  CardoryAccessState? _accessState;
  CardoryLoadResult? _result;
  String? _newRecoveryKey;
  String? _error;
  bool _busy = false;
  String? _recoveryCopyMessage;
  bool _useRecoveryKey = false;
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
    final repository = widget.repository;
    if (repository is VaultSessionRepository) {
      await (repository as VaultSessionRepository).lock();
    }
    await widget.vaultCredentialStore.deletePassword();
    if (!mounted) return;
    setState(() {
      _result = null;
      _newRecoveryKey = null;
      _accessState = CardoryAccessState.locked;
      _password.clear();
      _recoveryKey.clear();
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
    _recoveryKey.dispose();
    _replacementPassword.dispose();
    _replacementConfirmation.dispose();
    super.dispose();
  }

  Future<void> _inspect() async {
    if (mounted) setState(() => _error = null);
    try {
      final state = await widget.repository.accessState();
      if (!mounted) return;
      if (state == CardoryAccessState.unlocked) {
        final result = await widget.repository.load();
        if (mounted) setState(() => _result = result);
      } else if (state == CardoryAccessState.locked) {
        final password = await widget.vaultCredentialStore.readPassword();
        if (password != null) {
          try {
            final result = await widget.repository.unlockWithPassword(password);
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
        setState(() => _accessState = state);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final setup = _accessState == CardoryAccessState.setupRequired;
    final resettingPassword = !setup && _useRecoveryKey;
    final newPassword = resettingPassword
        ? _replacementPassword.text
        : _password.text;
    final confirmation = resettingPassword
        ? _replacementConfirmation.text
        : _confirmation.text;
    if ((setup || resettingPassword) && newPassword != confirmation) {
      setState(() => _error = '两次输入的密码不一致。');
      return;
    }
    if ((setup || resettingPassword) && newPassword.length < 8) {
      setState(() => _error = '密码至少需要 8 个字符。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = setup
          ? await widget.repository.setup(_password.text)
          : _useRecoveryKey
          ? await widget.repository.resetPasswordWithRecoveryKey(
              _recoveryKey.text,
              _replacementPassword.text,
            )
          : await widget.repository.unlockWithPassword(_password.text);
      await widget.vaultCredentialStore.writePassword(newPassword);
      if (!mounted) return;
      setState(() {
        _result = result;
        _newRecoveryKey = result.recoveryKey;
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
    if (_replacementPassword.text != _replacementConfirmation.text) {
      setState(() => _error = '两次输入的密码不一致。');
      return;
    }
    if (_replacementPassword.text.length < 8) {
      setState(() => _error = '密码至少需要 8 个字符。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.repository.restoreFromBackup(
        bytes,
        _recoveryKey.text,
        _replacementPassword.text,
      );
      await widget.vaultCredentialStore.writePassword(
        _replacementPassword.text,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _newRecoveryKey = null;
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
      TextField(
        key: const Key('restore-recovery-key'),
        controller: _recoveryKey,
        decoration: const InputDecoration(
          labelText: '恢复码',
          prefixIcon: Icon(Icons.key_rounded),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('restore-new-password'),
        controller: _replacementPassword,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: '新密码',
          prefixIcon: Icon(Icons.password_rounded),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('restore-confirm-password'),
        controller: _replacementConfirmation,
        obscureText: true,
        onSubmitted: (_) => _restoreBackup(),
        decoration: const InputDecoration(
          labelText: '确认新密码',
          prefixIcon: Icon(Icons.password_rounded),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: 20),
      FilledButton.icon(
        key: const Key('restore-cardory-backup'),
        onPressed: _busy ? null : _restoreBackup,
        icon: const Icon(Icons.restore_rounded),
        label: Text(_busy ? '恢复中…' : '恢复并设置新密码'),
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

  Future<void> _copyRecoveryKey() async {
    final recoveryKey = _newRecoveryKey;
    if (recoveryKey == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: recoveryKey));
      if (mounted) {
        setState(() => _recoveryCopyMessage = '恢复码已复制，请粘贴到安全位置手动保存。');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _recoveryCopyMessage = '复制失败，请直接选择上方恢复码并手动复制。');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_result != null && _newRecoveryKey == null) {
      return HomePage(
        repository: widget.repository,
        credentialStore: widget.credentialStore,
        vaultCredentialStore: widget.vaultCredentialStore,
        onSettingsChanged: widget.onSettingsChanged,
        initialResult: _result,
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
                      color: CardoryColors.error,
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
                child: _newRecoveryKey != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.key_rounded, size: 48),
                          const SizedBox(height: 16),
                          const Text(
                            '保存你的恢复码',
                            style: TextStyle(
                              fontSize: 20,
                              letterSpacing: -0.3,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text('忘记密码或恢复备份时需要此恢复码。Cardory 不会再次显示它。'),
                          const SizedBox(height: 6),
                          const Text('请复制恢复码，并粘贴到你信任的离线位置手动保存。'),
                          const SizedBox(height: 18),
                          SelectableText(
                            _newRecoveryKey!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: _copyRecoveryKey,
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('复制恢复码'),
                          ),
                          if (_recoveryCopyMessage != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _recoveryCopyMessage!,
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 10),
                          FilledButton(
                            onPressed: () =>
                                setState(() => _newRecoveryKey = null),
                            child: const Text('我已妥善保存，进入 Cardory'),
                          ),
                        ],
                      )
                    : _restoreFromBackup
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
                                : _useRecoveryKey
                                ? '使用恢复码验证数据并设置新密码。'
                                : '输入密码以打开加密数据。',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                          if (!setup)
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(value: false, label: Text('密码')),
                                ButtonSegment(value: true, label: Text('恢复码')),
                              ],
                              selected: {_useRecoveryKey},
                              onSelectionChanged: (value) => setState(() {
                                _useRecoveryKey = value.first;
                                _error = null;
                              }),
                            ),
                          if (!setup) const SizedBox(height: 16),
                          TextField(
                            controller: _useRecoveryKey
                                ? _recoveryKey
                                : _password,
                            obscureText: !_useRecoveryKey,
                            autofocus: true,
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: _useRecoveryKey ? '恢复码' : '密码',
                              prefixIcon: Icon(
                                _useRecoveryKey ? Icons.key : Icons.password,
                              ),
                            ),
                          ),
                          if (setup) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _confirmation,
                              obscureText: true,
                              onSubmitted: (_) => _submit(),
                              decoration: const InputDecoration(
                                labelText: '确认密码',
                                prefixIcon: Icon(Icons.password),
                              ),
                            ),
                          ],
                          if (!setup && _useRecoveryKey) ...[
                            const SizedBox(height: 12),
                            TextField(
                              key: const Key('recovery-new-password'),
                              controller: _replacementPassword,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: '新密码',
                                prefixIcon: Icon(Icons.password_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              key: const Key('recovery-confirm-password'),
                              controller: _replacementConfirmation,
                              obscureText: true,
                              onSubmitted: (_) => _submit(),
                              decoration: const InputDecoration(
                                labelText: '确认新密码',
                                prefixIcon: Icon(Icons.password_rounded),
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
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
                                  : _useRecoveryKey
                                  ? '重设密码并解锁'
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

enum AppSection { home, todos, projects, settings }

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.repository,
    required this.credentialStore,
    required this.vaultCredentialStore,
    required this.onSettingsChanged,
    this.initialResult,
  });

  final CardoryRepository repository;
  final SyncCredentialStore credentialStore;
  final VaultCredentialStore vaultCredentialStore;
  final ValueChanged<AppSettings> onSettingsChanged;
  final CardoryLoadResult? initialResult;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  CardoryData _data = const CardoryData.empty();
  AppSettings _settings = const AppSettings();
  String _dataPath = '';
  String? _error;
  bool _loading = true;
  bool _sidebarExpanded = true;
  AppSection _section = AppSection.home;
  late final SyncCoordinator _syncCoordinator;
  SyncStatus _syncStatus = const SyncStatus();

  @override
  void initState() {
    super.initState();
    _syncCoordinator = SyncCoordinator(
      repository: widget.repository,
      credentialStore: widget.credentialStore,
    )..addListener(_onSyncStatusChanged);
    final initial = widget.initialResult;
    if (initial == null) {
      _load();
    } else {
      _data = initial.data;
      _settings = initial.settings;
      _dataPath = initial.path;
      _loading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onSettingsChanged(initial.settings);
        if (initial.recoveredFromBackup && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('主数据文件损坏，已从备份恢复。')));
        }
      });
    }
  }

  @override
  void dispose() {
    _syncCoordinator
      ..removeListener(_onSyncStatusChanged)
      ..dispose();
    super.dispose();
  }

  void _onSyncStatusChanged() {
    if (mounted) setState(() => _syncStatus = _syncCoordinator.status);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await widget.repository.load();
      if (!mounted) return;
      setState(() {
        _data = result.data;
        _settings = result.settings;
        _dataPath = result.path;
        _loading = false;
      });
      widget.onSettingsChanged(result.settings);
      if (result.recoveredFromBackup) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('主数据文件损坏，已从备份恢复。')));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<bool> _save(CardoryData data) async {
    final previous = _data;
    if (mounted) setState(() => _data = data);
    try {
      await widget.repository.save(data, _settings);
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => _data = previous);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
      return false;
    }
  }

  Future<void> _openSettings([SettingsCategoryType? category]) async {
    final result = await showDialog<SettingsResult>(
      context: context,
      builder: (_) => SettingsDialog(
        settings: _settings,
        currentDataPath: _dataPath,
        credentialStore: widget.credentialStore,
        category: category,
      ),
    );
    if (result == null) return;
    final settings = result.settings;
    try {
      if (settings.syncProvider == SyncProviderType.webdav &&
          result.credentials.password.isNotEmpty) {
        await widget.credentialStore.writeWebDav(result.credentials);
      } else if (settings.syncProvider != SyncProviderType.webdav) {
        await widget.credentialStore.deleteWebDav();
      }
      if (settings.syncProvider == SyncProviderType.selfHosted &&
          result.selfHostedToken.isNotEmpty) {
        await widget.credentialStore.writeSelfHostedToken(
          result.selfHostedToken,
        );
      } else if (settings.syncProvider != SyncProviderType.selfHosted) {
        await widget.credentialStore.deleteSelfHostedToken();
      }
      await widget.repository.save(_data, settings);
      await widget.repository.saveSettings(settings);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _loading = true;
      });
      widget.onSettingsChanged(settings);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _sync() async {
    final settings = await _syncCoordinator.synchronize(_settings);
    if (!mounted) return;
    setState(() => _settings = settings);
    widget.onSettingsChanged(settings);
    if (_syncCoordinator.status.phase == SyncPhase.success) await _load();
  }

  Future<void> _changePassword() async {
    final passwords = await showDialog<PasswordChangeResult>(
      context: context,
      builder: (_) => const PasswordChangeDialog(),
    );
    if (passwords == null) return;
    try {
      await widget.repository.changePassword(
        passwords.currentPassword,
        passwords.newPassword,
      );
      await widget.vaultCredentialStore.writePassword(passwords.newPassword);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密码已修改。')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _restoreBackupFromSettings() async {
    try {
      final selected = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['cardory'],
        allowMultiple: false,
        withData: true,
      );
      if (selected == null || !mounted) return;
      final file = selected.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const CardoryStorageException('无法读取所选备份文件。');
      }
      final credentials = await showDialog<BackupRecoveryCredentials>(
        context: context,
        builder: (_) => BackupRecoveryDialog(fileName: file.name),
      );
      if (credentials == null || !mounted) return;
      final result = await widget.repository.restoreFromBackup(
        bytes,
        credentials.recoveryKey,
        credentials.newPassword,
      );
      await widget.vaultCredentialStore.writePassword(credentials.newPassword);
      if (!mounted) return;
      setState(() {
        _data = result.data;
        _settings = result.settings;
        _dataPath = result.path;
      });
      widget.onSettingsChanged(result.settings);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('数据已从备份恢复。')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _addProject() async {
    final project = await showDialog<ProjectData>(
      context: context,
      builder: (_) => const ProjectDialog(),
    );
    if (project == null) return;
    await _save(_data.copyWith(projects: [..._data.projects, project]));
  }

  Future<void> _editProject(ProjectData project) async {
    final updated = await showDialog<ProjectData>(
      context: context,
      builder: (_) => ProjectDialog(project: project),
    );
    if (updated == null) return;
    final projects = _data.projects
        .map((item) => item.id == updated.id ? updated : item)
        .toList();
    final todos = _data.todos
        .map(
          (todo) => todo.projectId == updated.id
              ? todo.copyWith(projectTitle: updated.title)
              : todo,
        )
        .toList();
    await _save(_data.copyWith(projects: projects, todos: todos));
  }

  Future<void> _deleteProject(ProjectData project) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除项目'),
        content: Text('确定删除“${project.title}”吗？关联待办和资产也会一并删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _save(
      _data.copyWith(
        projects: _data.projects
            .where((item) => item.id != project.id)
            .toList(),
        todos: _data.todos
            .where((todo) => todo.projectId != project.id)
            .toList(),
        assets: _data.assets
            .where((asset) => asset.projectId != project.id)
            .toList(),
      ),
    );
  }

  Future<void> _addTodo() async {
    final todo = await showDialog<TodoData>(
      context: context,
      builder: (_) => TodoDialog(
        projects: _data.projects,
        recordSubTodoCreatedAt: _settings.recordSubTodoCreatedAt,
      ),
    );
    if (todo == null) return;
    await _save(_data.copyWith(todos: [..._data.todos, todo]));
  }

  Future<TodoData?> _openTodo(TodoData todo) async {
    final updated = await showDialog<TodoData>(
      context: context,
      builder: (_) => TodoDialog(
        projects: _data.projects,
        todo: todo,
        recordSubTodoCreatedAt: _settings.recordSubTodoCreatedAt,
      ),
    );
    if (updated == null) return null;
    await _save(
      _data.copyWith(
        todos: _data.todos
            .map((item) => item.id == updated.id ? updated : item)
            .toList(),
      ),
    );
    return updated;
  }

  Future<bool> _deleteTodo(TodoData todo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除待办'),
        content: Text('确定删除“${todo.title}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    return _save(
      _data.copyWith(
        todos: _data.todos.where((item) => item.id != todo.id).toList(),
      ),
    );
  }

  Future<TodoData?> _addProjectTodo(ProjectData project) async {
    final todo = await showDialog<TodoData>(
      context: context,
      builder: (_) => TodoDialog(
        projects: _data.projects,
        initialProject: project,
        recordSubTodoCreatedAt: _settings.recordSubTodoCreatedAt,
      ),
    );
    if (todo == null) return null;
    await _save(_data.copyWith(todos: [..._data.todos, todo]));
    return todo;
  }

  Future<TodoData> _toggleTodo(TodoData todo) async {
    final updated = todo.copyWith(done: !todo.done);
    final todos = _data.todos
        .map((item) => item.id == todo.id ? updated : item)
        .toList();
    await _save(_data.copyWith(todos: todos));
    return updated;
  }

  Future<TodoData> _toggleSubTodo(TodoData todo, SubTodoData subTodo) async {
    TodoData updated = todo;
    final todos = _data.todos.map((item) {
      if (item.id != todo.id) return item;
      final subTodos = item.subTodos
          .map(
            (sub) => sub.id == subTodo.id ? sub.copyWith(done: !sub.done) : sub,
          )
          .toList();
      updated = item.copyWith(subTodos: subTodos);
      return updated;
    }).toList();
    await _save(_data.copyWith(todos: todos));
    return updated;
  }

  Future<void> _quickAddSubTodo(TodoData todo) async {
    final subTodo = await showDialog<SubTodoData>(
      context: context,
      builder: (_) => QuickAddSubTodoDialog(
        recordCreatedAt: _settings.recordSubTodoCreatedAt,
      ),
    );
    if (subTodo == null) return;
    final updated = todo.copyWith(subTodos: [...todo.subTodos, subTodo]);
    await _save(
      _data.copyWith(
        todos: _data.todos
            .map((item) => item.id == todo.id ? updated : item)
            .toList(),
      ),
    );
  }

  Future<void> _updateProject(ProjectData project) async {
    final projects = _data.projects
        .map((item) => item.id == project.id ? project : item)
        .toList();
    await _save(_data.copyWith(projects: projects));
  }

  Future<void> _openProject(ProjectData project) async {
    final current = _data.projects.firstWhere(
      (item) => item.id == project.id,
      orElse: () => project,
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectDetailPage(
          project: current,
          todos: _data.todos
              .where((todo) => todo.projectId == current.id)
              .toList(),
          assets: _data.assets
              .where((asset) => asset.projectId == current.id)
              .toList(),
          onUpdateProject: _updateProject,
          onAddAsset: () => _addAsset(current),
          onEditAsset: _editAsset,
          onDeleteAsset: _deleteAsset,
          onToggleTodo: _toggleTodo,
          onToggleSubTodo: _toggleSubTodo,
          onOpenTodo: _openTodo,
          onAddTodo: _addProjectTodo,
          onDeleteTodo: _deleteTodo,
        ),
      ),
    );
  }

  Future<AssetData?> _addAsset(ProjectData project) async {
    final asset = await showDialog<AssetData>(
      context: context,
      builder: (_) => AssetDialog(
        projectId: project.id,
        serverTypes: _settings.serverTypes,
      ),
    );
    if (asset != null) {
      final recorded = asset.copyWith(
        activities: [
          AssetActivity(
            kind: AssetActivityKind.created,
            message: '创建资产',
            timestamp: DateTime.now(),
          ),
          ...asset.activities,
        ],
      );
      await _save(_data.copyWith(assets: [..._data.assets, recorded]));
    }
    return asset;
  }

  Future<AssetData?> _editAsset(AssetData asset) async {
    final updated = await showDialog<AssetData>(
      context: context,
      builder: (_) =>
          AssetDialog(asset: asset, serverTypes: _settings.serverTypes),
    );
    if (updated != null) {
      final changed = <String>[];
      if (updated.name != asset.name) changed.add('名称');
      if (updated.version != asset.version) changed.add('版本');
      if (updated.port != asset.port) changed.add('端口');
      if (updated.path != asset.path) changed.add('路径');
      if (updated.serialNumber != asset.serialNumber) changed.add('序列号');
      if (updated.network != asset.network) changed.add('网络');
      if (updated.serverType != asset.serverType) changed.add('服务器类型');
      if (updated.username != asset.username) changed.add('账号');
      if (updated.password != asset.password) changed.add('密码');
      if (updated.note != asset.note) changed.add('备注');
      if (changed.isEmpty) changed.add('字段');
      final recorded = updated.copyWith(
        activities: [
          AssetActivity(
            kind: AssetActivityKind.updated,
            message: '更新${changed.join('、')}',
            timestamp: DateTime.now(),
          ),
          ...updated.activities,
        ],
      );
      await _save(
        _data.copyWith(
          assets: _data.assets
              .map((item) => item.id == updated.id ? recorded : item)
              .toList(),
        ),
      );
    }
    return updated;
  }

  Future<void> _deleteAsset(AssetData asset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除资产'),
        content: Text('确定删除“${asset.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _save(
        _data.copyWith(
          assets: _data.assets.where((item) => item.id != asset.id).toList(),
        ),
      );
    }
  }

  Widget _buildContent() {
    switch (_section) {
      case AppSection.home:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HeroHeader(onAddProject: _addProject, onAddTodo: _addTodo),
            const SizedBox(height: 22),
            Overview(data: _data),
            const SizedBox(height: 22),
            KanbanBoard(
              data: _data,
              onOpenProject: _openProject,
              onEditProject: _editProject,
              onDeleteProject: _deleteProject,
            ),
            const SizedBox(height: 22),
            ReminderPanel(
              todos: _data.todos,
              priorityThreshold: _settings.homeReminderPriorityThreshold,
              onToggleTodo: _toggleTodo,
              onToggleSubTodo: _toggleSubTodo,
              onAddSubTodo: _quickAddSubTodo,
              onOpenTodo: _openTodo,
            ),
          ],
        );
      case AppSection.todos:
        return TodoPanel(
          todos: _data.todos,
          onToggle: _toggleTodo,
          onToggleSubTodo: _toggleSubTodo,
          onOpenTodo: _openTodo,
          onDeleteTodo: _deleteTodo,
        );
      case AppSection.projects:
        return ProjectListPanel(
          projects: _data.projects,
          onOpenProject: _openProject,
          onEditProject: _editProject,
          onDeleteProject: _deleteProject,
        );
      case AppSection.settings:
        return SettingsPanel(
          dataPath: _dataPath,
          settings: _settings,
          syncStatus: _syncStatus,
          onSync: _sync,
          onOpenSettings: _openSettings,
          onChangePassword: _changePassword,
          onRestoreBackup: _restoreBackupFromSettings,
        );
    }
  }

  String get _sectionTitle => switch (_section) {
    AppSection.home => '看板',
    AppSection.todos => '待办事项',
    AppSection.projects => '项目',
    AppSection.settings => '设置',
  };

  void _selectSection(AppSection section) {
    if (section == _section) return;
    setState(() => _section = section);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 42,
                      color: CardoryColors.error,
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
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 720;
    final medium = width >= 720 && width < 1100;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              CardoryColors.gray50,
              CardoryColors.primarySoft.withValues(alpha: 0.52),
              const Color(0xFFFFF7FC),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              AppTopBar(
                compact: compact,
                title: _sectionTitle,
                onOpenSettings: _openSettings,
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!compact)
                      Sidebar(
                        selected: _section,
                        expanded: !medium && _sidebarExpanded,
                        onToggleExpanded: medium
                            ? null
                            : () => setState(
                                () => _sidebarExpanded = !_sidebarExpanded,
                              ),
                        onSelected: _selectSection,
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              key: const Key('main-scroll-view'),
                              padding: EdgeInsets.fromLTRB(
                                compact ? 16 : 28,
                                compact ? 16 : 24,
                                compact ? 16 : 28,
                                36,
                              ),
                              child: Align(
                                alignment: Alignment.topCenter,
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1680,
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 240),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                          opacity: animation,
                                          child: SlideTransition(
                                            position: Tween<Offset>(
                                              begin: const Offset(0.025, 0),
                                              end: Offset.zero,
                                            ).animate(animation),
                                            child: child,
                                          ),
                                        ),
                                    child: KeyedSubtree(
                                      key: ValueKey(_section),
                                      child: _buildContent(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: compact
          ? SectionNavigation(
              key: const Key('bottom-navigation'),
              selected: _section,
              compact: true,
              onSelected: _selectSection,
            )
          : null,
    );
  }
}

class ProjectDetailPage extends StatefulWidget {
  const ProjectDetailPage({
    super.key,
    required this.project,
    required this.todos,
    required this.assets,
    required this.onUpdateProject,
    required this.onAddAsset,
    required this.onEditAsset,
    required this.onDeleteAsset,
    required this.onToggleTodo,
    required this.onToggleSubTodo,
    required this.onOpenTodo,
    required this.onAddTodo,
    required this.onDeleteTodo,
  });

  final ProjectData project;
  final List<TodoData> todos;
  final List<AssetData> assets;
  final Future<void> Function(ProjectData project) onUpdateProject;
  final Future<AssetData?> Function() onAddAsset;
  final Future<AssetData?> Function(AssetData asset) onEditAsset;
  final Future<void> Function(AssetData asset) onDeleteAsset;
  final Future<TodoData> Function(TodoData todo) onToggleTodo;
  final Future<TodoData> Function(TodoData todo, SubTodoData subTodo)
  onToggleSubTodo;
  final Future<TodoData?> Function(TodoData todo) onOpenTodo;
  final Future<TodoData?> Function(ProjectData project) onAddTodo;
  final Future<bool> Function(TodoData todo) onDeleteTodo;

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  late ProjectData _project;
  late List<TodoData> _todos;
  late List<AssetData> _assets;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _todos = widget.todos;
    _assets = widget.assets;
  }

  Future<void> _save(ProjectData project) async {
    setState(() => _project = project);
    await widget.onUpdateProject(project);
  }

  Future<void> _addProgress() async {
    final entry = await showDialog<ProjectProgressEntry>(
      context: context,
      builder: (_) => ProgressDialog(currentProgress: _project.progress),
    );
    if (entry == null) return;
    await _save(
      _project.copyWith(progressEntries: [..._project.progressEntries, entry]),
    );
  }

  Future<void> _editProgress(ProjectProgressEntry current) async {
    final entry = await showDialog<ProjectProgressEntry>(
      context: context,
      builder: (_) => ProgressDialog(entry: current),
    );
    if (entry == null) return;
    await _save(
      _project.copyWith(
        progressEntries: _project.progressEntries
            .map((item) => item.id == entry.id ? entry : item)
            .toList(),
      ),
    );
  }

  Future<void> _toggleTodo(TodoData todo) async {
    final updated = await widget.onToggleTodo(todo);
    setState(
      () => _todos = _todos
          .map((item) => item.id == updated.id ? updated : item)
          .toList(),
    );
  }

  Future<void> _toggleSubTodo(TodoData todo, SubTodoData subTodo) async {
    final updated = await widget.onToggleSubTodo(todo, subTodo);
    setState(
      () => _todos = _todos
          .map((item) => item.id == updated.id ? updated : item)
          .toList(),
    );
  }

  Future<void> _addTodo() async {
    final todo = await widget.onAddTodo(_project);
    if (todo != null && mounted) setState(() => _todos = [..._todos, todo]);
  }

  Future<void> _openTodo(TodoData todo) async {
    final updated = await widget.onOpenTodo(todo);
    if (updated == null || !mounted) return;
    setState(() {
      _todos = updated.projectId == _project.id
          ? _todos
                .map((item) => item.id == updated.id ? updated : item)
                .toList()
          : _todos.where((item) => item.id != updated.id).toList();
    });
  }

  Future<void> _viewAsset(AssetData asset) async {
    final shouldEdit = await showDialog<bool>(
      context: context,
      builder: (_) => AssetDetailDialog(asset: asset),
    );
    if (shouldEdit != true || !mounted) return;

    final updated = await widget.onEditAsset(asset);
    if (mounted && updated != null) {
      setState(() {
        _assets = _assets
            .map((item) => item.id == updated.id ? updated : item)
            .toList();
      });
    }
  }

  Future<bool> _deleteTodo(TodoData todo) async {
    final deleted = await widget.onDeleteTodo(todo);
    if (deleted && mounted) {
      setState(
        () => _todos = _todos.where((item) => item.id != todo.id).toList(),
      );
    }
    return deleted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_project.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: darkCardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        children: [
                          PriorityBadge(priority: _project.priority),
                          StageBadge(stage: _project.stage),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _project.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          letterSpacing: -0.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _project.description.isEmpty
                            ? '暂无项目说明'
                            : _project.description,
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 13.5,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<ProjectStage>(
                        initialValue: _project.stage,
                        decoration: const InputDecoration(
                          labelText: '项目阶段',
                          filled: true,
                        ),
                        items: ProjectStage.values
                            .map(
                              (stage) => DropdownMenuItem(
                                value: stage,
                                child: Text(stage.label),
                              ),
                            )
                            .toList(),
                        onChanged: (stage) {
                          if (stage != null) {
                            _save(_project.copyWith(stage: stage));
                          }
                        },
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _addProgress,
                      icon: const Icon(Icons.add_chart_rounded),
                      label: const Text('记录进度'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _addTodo,
                      icon: const Icon(Icons.add_task_rounded),
                      label: const Text('新建待办'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _ProjectAssetsPanel(
                  assets: _assets,
                  onAdd: () async {
                    final asset = await widget.onAddAsset();
                    if (mounted && asset != null) {
                      setState(() => _assets = [..._assets, asset]);
                    }
                  },
                  onView: _viewAsset,
                  onDelete: (asset) async {
                    await widget.onDeleteAsset(asset);
                    if (mounted) {
                      setState(
                        () => _assets = _assets
                            .where((item) => item.id != asset.id)
                            .toList(),
                      );
                    }
                  },
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final timeline = ProgressTimeline(
                      entries: _project.progressEntries,
                      onEdit: _editProgress,
                    );
                    final todos = TodoPanel(
                      todos: _todos,
                      onToggle: _toggleTodo,
                      onToggleSubTodo: _toggleSubTodo,
                      onOpenTodo: _openTodo,
                      onDeleteTodo: _deleteTodo,
                    );
                    if (constraints.maxWidth < 860) {
                      return Column(
                        children: [timeline, const SizedBox(height: 20), todos],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: timeline),
                        const SizedBox(width: 20),
                        Expanded(child: todos),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectAssetsPanel extends StatelessWidget {
  const _ProjectAssetsPanel({
    required this.assets,
    required this.onAdd,
    required this.onView,
    required this.onDelete,
  });

  final List<AssetData> assets;
  final Future<void> Function() onAdd;
  final Future<void> Function(AssetData asset) onView;
  final Future<void> Function(AssetData asset) onDelete;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: SectionTitle(title: '项目资产', subtitle: '软件与硬件资产均归属当前项目'),
            ),
            FilledButton.icon(
              key: const Key('add-project-asset-button'),
              onPressed: () => onAdd(),
              icon: const Icon(Icons.add),
              label: const Text('新增资产'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (assets.isEmpty)
          const EmptyCard(text: '暂无项目资产')
        else
          ...assets.map((asset) {
            final accent = asset.type == AssetType.software
                ? CardoryColors.primary
                : CardoryColors.success;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: cardoryCard(radius: 12),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () => onView(asset),
                leading: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cardoryTint(accent, 0.88),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    asset.type == AssetType.software
                        ? Icons.apps_outlined
                        : Icons.dns_outlined,
                    color: accent,
                    size: 19,
                  ),
                ),
                title: Text(asset.name),
                subtitle: Text(
                  asset.type == AssetType.software
                      ? [
                          if (asset.version.isNotEmpty) '版本 ${asset.version}',
                          if (asset.port.isNotEmpty) '端口 ${asset.port}',
                          if (asset.path.isNotEmpty) asset.path,
                        ].join(' · ')
                      : [
                          if (asset.serverType.isNotEmpty) asset.serverType,
                          if (asset.serialNumber.isNotEmpty)
                            '序列号 ${asset.serialNumber}',
                          if (asset.network.isNotEmpty) asset.network,
                        ].join(' · '),
                ),
                trailing: IconButton(
                  tooltip: '删除资产',
                  onPressed: () => onDelete(asset),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            );
          }),
      ],
    ),
  );
}

class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.compact,
    required this.title,
    required this.onOpenSettings,
  });

  final bool compact;
  final String title;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 56 : 60,
      // 左侧 padding 与侧边栏菜单图标左边缘对齐（侧边栏 padding 10 + 图标居中偏移 10）
      padding: EdgeInsets.only(
        left: compact ? 16 : 20,
        right: compact ? 16 : 24,
      ),
      decoration: BoxDecoration(
        color: CardoryColors.white.withValues(alpha: 0.72),
        border: Border(
          bottom: BorderSide(
            color: CardoryColors.primary.withValues(alpha: 0.06),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: CardoryColors.primary.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const CardoryLogo(size: 32),

          const SizedBox(width: 12),
          if (!compact) ...[
            Text(
              '板记 Cardory',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: CardoryColors.gray900,
              ),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 20, color: CardoryColors.gray200),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                color: compact ? CardoryColors.gray900 : CardoryColors.gray500,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.tune_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class SectionNavigation extends StatelessWidget {
  const SectionNavigation({
    super.key,
    required this.selected,
    required this.compact,
    required this.onSelected,
  });

  final AppSection selected;
  final bool compact;
  final ValueChanged<AppSection> onSelected;

  static const _items = [
    (AppSection.home, Icons.space_dashboard_outlined, '看板'),
    (AppSection.todos, Icons.checklist_rounded, '待办'),
    (AppSection.projects, Icons.folder_outlined, '项目'),
    (AppSection.settings, Icons.settings_outlined, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return NavigationBar(
        height: 64,
        selectedIndex: _items.indexWhere((item) => item.$1 == selected),
        onDestinationSelected: (index) {
          final section = _items[index].$1;
          if (section != selected) onSelected(section);
        },
        destinations: [
          for (final item in _items)
            NavigationDestination(icon: Icon(item.$2), label: item.$3),
        ],
      );
    }
    return Container(
      height: 48,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: CardoryColors.white.withValues(alpha: 0.72),
        border: Border(
          bottom: BorderSide(
            color: CardoryColors.primary.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final item in _items)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: TextButton.icon(
                  onPressed: selected == item.$1
                      ? null
                      : () => onSelected(item.$1),
                  icon: Icon(item.$2, size: 17),
                  label: Text(item.$3),
                  style: TextButton.styleFrom(
                    foregroundColor: selected == item.$1
                        ? Theme.of(context).colorScheme.primary
                        : CardoryColors.gray500,
                    backgroundColor: selected == item.$1
                        ? CardoryColors.primarySoft
                        : Colors.transparent,
                    textStyle: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected == item.$1
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.selected,
    required this.expanded,
    required this.onSelected,
    this.onToggleExpanded,
  });

  final AppSection selected;
  final bool expanded;
  final ValueChanged<AppSection> onSelected;
  final VoidCallback? onToggleExpanded;

  static const _items = [
    (AppSection.home, Icons.space_dashboard_outlined, '看板'),
    (AppSection.todos, Icons.check_circle_outline_rounded, '待办'),
    (AppSection.projects, Icons.folder_outlined, '项目'),
    (AppSection.settings, Icons.settings_outlined, '设置'),
  ];

  @override
  Widget build(BuildContext context) => Container(
    width: expanded ? 208 : 64,
    height: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    decoration: BoxDecoration(
      color: CardoryColors.white.withValues(alpha: 0.72),
      border: Border(
        right: BorderSide(color: CardoryColors.primary.withValues(alpha: 0.06)),
      ),
    ),
    child: Column(
      children: [
        Row(
          children: [
            IconButton(
              style: IconButton.styleFrom(
                minimumSize: const Size(40, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              constraints: const BoxConstraints.tightFor(width: 40, height: 44),
              padding: EdgeInsets.zero,
              onPressed: onToggleExpanded,
              icon: Icon(
                expanded ? Icons.menu_open_rounded : Icons.menu_rounded,
                size: 20,
              ),
              color: CardoryColors.gray500,
            ),
            if (expanded)
              Expanded(
                child: Text(
                  'Cardory',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    foreground: Paint()
                      ..shader = LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          CardoryColors.pink,
                        ],
                      ).createShader(const Rect.fromLTWH(0, 0, 120, 20)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        for (final item in _items) ...[
          _SidebarItem(
            icon: item.$2,
            label: item.$3,
            selected: selected == item.$1,
            expanded: expanded,
            onTap: selected == item.$1 ? null : () => onSelected(item.$1),
          ),
          const SizedBox(height: 2),
        ],
      ],
    ),
  );
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: expanded ? '' : label,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? CardoryColors.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : CardoryColors.gray400,
            ),
            if (expanded) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: selected
                        ? CardoryColors.gray900
                        : CardoryColors.gray600,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.onAddProject,
    required this.onAddTodo,
  });

  final VoidCallback onAddProject;
  final VoidCallback onAddTodo;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '把项目推进，落到今天',
            style: TextStyle(
              color: CardoryColors.gray900,
              fontSize: compact ? 24 : 28,
              height: 1.2,
              letterSpacing: -0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '集中查看项目阶段、关键待办和最近进度。数据保存在你的本地保险库。',
            style: TextStyle(
              color: CardoryColors.gray500,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        ],
      );
      final actions = Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton.icon(
            onPressed: onAddProject,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('新建项目'),
          ),
          OutlinedButton.icon(
            onPressed: onAddTodo,
            icon: const Icon(Icons.playlist_add_rounded, size: 18),
            label: const Text('添加待办'),
          ),
        ],
      );
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 6,
          vertical: compact ? 16 : 20,
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 18), actions],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 24),
                  actions,
                ],
              ),
      );
    },
  );
}

class Overview extends StatelessWidget {
  const Overview({super.key, required this.data});

  final CardoryData data;

  @override
  Widget build(BuildContext context) {
    final activeCount = data.projects
        .where((item) => item.stage != ProjectStage.done)
        .length;
    final p0Count = data.projects
        .where((item) => item.priority == ProjectPriority.p0)
        .length;
    final todoCount = data.todos.where((todo) => !todo.done).length;
    final cards = [
      OverviewCard(
        label: '项目',
        value: '${data.projects.length}',
        icon: Icons.folder_rounded,
      ),
      OverviewCard(
        label: '推进中',
        value: '$activeCount',
        icon: Icons.trending_up_rounded,
      ),
      OverviewCard(
        label: '高优先级',
        value: '$p0Count',
        icon: Icons.priority_high_rounded,
      ),
      OverviewCard(
        label: '待办',
        value: '$todoCount',
        icon: Icons.checklist_rounded,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class OverviewCard extends StatelessWidget {
  const OverviewCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final accents = [
      CardoryColors.primary,
      CardoryColors.success,
      CardoryColors.error,
      CardoryColors.pink,
    ];
    final accent =
        accents[(label.codeUnitAt(0) + icon.codePoint) % accents.length];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardoryCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cardoryTint(accent, 0.88),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: CardoryColors.gray500,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              color: CardoryColors.gray900,
              fontSize: 28,
              height: 1,
              letterSpacing: -0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class ReminderPanel extends StatelessWidget {
  const ReminderPanel({
    super.key,
    required this.todos,
    required this.priorityThreshold,
    required this.onToggleTodo,
    required this.onToggleSubTodo,
    required this.onAddSubTodo,
    required this.onOpenTodo,
  });

  final List<TodoData> todos;
  final ProjectPriority priorityThreshold;
  final Future<TodoData> Function(TodoData todo) onToggleTodo;
  final Future<TodoData> Function(TodoData todo, SubTodoData subTodo)
  onToggleSubTodo;
  final Future<void> Function(TodoData todo) onAddSubTodo;
  final Future<TodoData?> Function(TodoData todo) onOpenTodo;

  @override
  Widget build(BuildContext context) {
    final reminders = todos
        .where(
          (todo) =>
              !todo.done && todo.priority.index <= priorityThreshold.index,
        )
        .toList();
    final shown = reminders;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: '主要提醒',
            subtitle:
                '${_reminderPriorityRangeLabel(priorityThreshold)} · 未完成待办',
          ),
          const SizedBox(height: 16),
          if (shown.isEmpty)
            const EmptyCard(text: '暂无重要提醒')
          else
            for (final todo in shown) ...[
              Material(
                color: todo.done
                    ? CardoryColors.success.withValues(alpha: 0.055)
                    : CardoryColors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  hoverColor: CardoryColors.primarySoft.withValues(alpha: 0.55),
                  onTap: () => onOpenTodo(todo),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: todo.done
                            ? CardoryColors.success.withValues(alpha: 0.18)
                            : CardoryColors.primary.withValues(alpha: 0.10),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: CardoryColors.primary.withValues(alpha: 0.05),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(5),
                                onTap: () => onToggleTodo(todo),
                                child: Icon(
                                  todo.done
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  size: 20,
                                  color: todo.done
                                      ? CardoryColors.success
                                      : CardoryColors.gray300,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    todo.title,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: todo.done
                                          ? CardoryColors.gray400
                                          : CardoryColors.gray800,
                                      decoration: todo.done
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 200,
                                        ),
                                        child: Text(
                                          todo.projectTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: todo.done
                                                ? CardoryColors.gray300
                                                : CardoryColors.gray400,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      PriorityBadge(priority: todo.priority),
                                      Text(
                                        todo.dateRangeText,
                                        style: TextStyle(
                                          color: CardoryColors.error,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (todo.subTodos.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          for (final subTodo in todo.subTodos)
                            SubTodoTile(
                              todo: todo,
                              subTodo: subTodo,
                              onToggle: (todo, subTodo) async {
                                await onToggleSubTodo(todo, subTodo);
                              },
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (todo != shown.last) const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class KanbanBoard extends StatelessWidget {
  const KanbanBoard({
    super.key,
    required this.data,
    required this.onOpenProject,
    required this.onEditProject,
    required this.onDeleteProject,
  });

  final CardoryData data;
  final Future<void> Function(ProjectData project) onOpenProject;
  final Future<void> Function(ProjectData project) onEditProject;
  final Future<void> Function(ProjectData project) onDeleteProject;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionTitle(title: '项目看板', subtitle: '点击项目进入详情页记录进度'),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 12.0;
          final columnCount = constraints.maxWidth >= 960
              ? 4
              : constraints.maxWidth >= 560
              ? 2
              : 1;
          final columnWidth =
              (constraints.maxWidth - spacing * (columnCount - 1)) /
              columnCount;
          return Wrap(
            key: const Key('kanban-responsive-board'),
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final stage in ProjectStage.values)
                KanbanColumn(
                  width: columnWidth,
                  stage: stage,
                  projects: data.projects
                      .where((item) => item.stage == stage)
                      .toList(),
                  onOpenProject: onOpenProject,
                  onEditProject: onEditProject,
                  onDeleteProject: onDeleteProject,
                ),
            ],
          );
        },
      ),
    ],
  );
}

class KanbanColumn extends StatelessWidget {
  const KanbanColumn({
    super.key,
    required this.width,
    required this.stage,
    required this.projects,
    required this.onOpenProject,
    required this.onEditProject,
    required this.onDeleteProject,
  });

  final double width;
  final ProjectStage stage;
  final List<ProjectData> projects;
  final Future<void> Function(ProjectData project) onOpenProject;
  final Future<void> Function(ProjectData project) onEditProject;
  final Future<void> Function(ProjectData project) onDeleteProject;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CardoryColors.white.withValues(alpha: 0.55),
        gradient: LinearGradient(
          colors: [
            cardoryTint(stage.color, 0.96),
            CardoryColors.white.withValues(alpha: 0.4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: stage.color.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: stage.color.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: stage.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: stage.color.withValues(alpha: 0.4),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stage.label,
                    style: TextStyle(
                      color: cardoryShade(stage.color, 0.35),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                CountPill(count: projects.length),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (projects.isEmpty)
            const EmptyCard(text: '暂无项目')
          else
            for (final project in projects) ...[
              ProjectCard(
                project: project,
                onTap: () => onOpenProject(project),
                onEdit: () => onEditProject(project),
                onDelete: () => onDeleteProject(project),
              ),
              if (project != projects.last) const SizedBox(height: 12),
            ],
        ],
      ),
    ),
  );
}

class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final ProjectData project;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final latest = project.progressEntries.isEmpty
        ? '还没有进度记录'
        : project.progressEntries.last.note;
    return Material(
      color: CardoryColors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        hoverColor: CardoryColors.primarySoft.withValues(alpha: 0.55),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: CardoryColors.primary.withValues(alpha: 0.10),
            ),
            boxShadow: [
              BoxShadow(
                color: CardoryColors.primary.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        project.title,
                        style: TextStyle(
                          color: CardoryColors.gray900,
                          fontSize: 14.5,
                          letterSpacing: -0.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: PriorityBadge(priority: project.priority),
                  ),
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: PopupMenuButton<String>(
                      tooltip: '项目操作',
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        size: 18,
                        color: CardoryColors.gray400,
                      ),
                      padding: EdgeInsets.zero,
                      onSelected: (value) {
                        if (value == 'detail') onTap();
                        if (value == 'edit') onEdit();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'detail', child: Text('详情')),
                        PopupMenuItem(value: 'edit', child: Text('编辑')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                project.description.isEmpty ? '暂无项目说明' : project.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CardoryColors.gray500,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      latest,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CardoryColors.gray400,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: CardoryColors.gray400,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProjectListPanel extends StatelessWidget {
  const ProjectListPanel({
    super.key,
    required this.projects,
    required this.onOpenProject,
    required this.onEditProject,
    required this.onDeleteProject,
  });

  final List<ProjectData> projects;
  final Future<void> Function(ProjectData project) onOpenProject;
  final Future<void> Function(ProjectData project) onEditProject;
  final Future<void> Function(ProjectData project) onDeleteProject;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: '项目', subtitle: '选择项目，查看进度、待办与关联资产'),
        const SizedBox(height: 18),
        if (projects.isEmpty)
          const EmptyCard(text: '暂无项目')
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1080
                  ? 3
                  : constraints.maxWidth >= 680
                  ? 2
                  : 1;
              final cardWidth =
                  (constraints.maxWidth - (columns - 1) * 14) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: projects
                    .map(
                      (project) => SizedBox(
                        width: cardWidth,
                        child: ProjectCard(
                          project: project,
                          onTap: () => onOpenProject(project),
                          onEdit: () => onEditProject(project),
                          onDelete: () => onDeleteProject(project),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
      ],
    ),
  );
}

class TodoPanel extends StatelessWidget {
  const TodoPanel({
    super.key,
    required this.todos,
    required this.onToggle,
    required this.onToggleSubTodo,
    required this.onOpenTodo,
    required this.onDeleteTodo,
  });

  final List<TodoData> todos;
  final Future<void> Function(TodoData todo) onToggle;
  final Future<void> Function(TodoData todo, SubTodoData subTodo)
  onToggleSubTodo;
  final Future<void> Function(TodoData todo) onOpenTodo;
  final Future<bool> Function(TodoData todo) onDeleteTodo;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: '待办', subtitle: '下一步行动，可点击查看/编辑详情'),
        const SizedBox(height: 16),
        if (todos.isEmpty)
          const EmptyCard(text: '暂无待办')
        else
          for (final todo in todos) ...[
            TodoTile(
              todo: todo,
              onToggle: onToggle,
              onToggleSubTodo: onToggleSubTodo,
              onOpenTodo: onOpenTodo,
              onDeleteTodo: onDeleteTodo,
            ),
            if (todo != todos.last) const SizedBox(height: 12),
          ],
      ],
    ),
  );
}

class TodoTile extends StatelessWidget {
  const TodoTile({
    super.key,
    required this.todo,
    required this.onToggle,
    required this.onToggleSubTodo,
    required this.onOpenTodo,
    required this.onDeleteTodo,
  });

  final TodoData todo;
  final Future<void> Function(TodoData todo) onToggle;
  final Future<void> Function(TodoData todo, SubTodoData subTodo)
  onToggleSubTodo;
  final Future<void> Function(TodoData todo) onOpenTodo;
  final Future<bool> Function(TodoData todo) onDeleteTodo;

  @override
  Widget build(BuildContext context) {
    final doneCount = todo.subTodos.where((item) => item.done).length;
    return Material(
      color: todo.done
          ? CardoryColors.success.withValues(alpha: 0.055)
          : CardoryColors.white,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: todo.done
                ? CardoryColors.success.withValues(alpha: 0.18)
                : CardoryColors.gray200,
          ),
          boxShadow: [
            BoxShadow(
              color: CardoryColors.primary.withValues(alpha: 0.05),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onOpenTodo(todo),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: Icon(
                      todo.done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: todo.done
                          ? CardoryColors.success
                          : CardoryColors.gray300,
                    ),
                    onPressed: () => onToggle(todo),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                todo.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: todo.done
                                      ? CardoryColors.gray400
                                      : CardoryColors.gray800,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  decoration: todo.done
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            if (todo.done) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: CardoryColors.success.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '已完成',
                                  style: TextStyle(
                                    color: CardoryColors.success,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (todo.description.isNotEmpty)
                          Text(
                            todo.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: CardoryColors.gray500,
                              fontSize: 12.5,
                              height: 1.5,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${todo.projectTitle} · ${todo.dateRangeText}',
                                style: TextStyle(
                                  color: CardoryColors.gray400,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            PriorityBadge(priority: todo.priority),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '删除待办',
                    onPressed: () => onDeleteTodo(todo),
                    icon: const Icon(Icons.delete_outline_rounded, size: 19),
                    color: CardoryColors.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            if (todo.subTodos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '子待办 $doneCount/${todo.subTodos.length}',
                style: TextStyle(
                  color: CardoryColors.gray400,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              for (final subTodo in todo.subTodos) ...[
                SubTodoTile(
                  todo: todo,
                  subTodo: subTodo,
                  onToggle: onToggleSubTodo,
                ),
                if (subTodo != todo.subTodos.last) const SizedBox(height: 4),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class SubTodoTile extends StatelessWidget {
  const SubTodoTile({
    super.key,
    required this.todo,
    required this.subTodo,
    required this.onToggle,
  });

  final TodoData todo;
  final SubTodoData subTodo;
  final Future<void> Function(TodoData todo, SubTodoData subTodo) onToggle;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(10),
    hoverColor: CardoryColors.primarySoft.withValues(alpha: 0.72),
    onTap: () => onToggle(todo, subTodo),
    child: Padding(
      padding: const EdgeInsets.only(left: 32, top: 5, bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              subTodo.done ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 16,
              color: subTodo.done
                  ? CardoryColors.success
                  : CardoryColors.gray300,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subTodo.content,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: subTodo.done
                        ? CardoryColors.gray400
                        : CardoryColors.gray600,
                    decoration: subTodo.done
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                if (subTodo.createdAt != null || subTodo.dueAt != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (subTodo.createdAt != null)
                        _SubTodoTimeLabel(
                          icon: Icons.add_circle_outline_rounded,
                          label: '添加',
                          value: subTodo.createdAt!,
                        ),
                      if (subTodo.dueAt != null)
                        _SubTodoTimeLabel(
                          icon: Icons.alarm_rounded,
                          label: '提醒',
                          value: subTodo.dueAt!,
                          emphasized: true,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SubTodoTimeLabel extends StatelessWidget {
  const _SubTodoTimeLabel({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final DateTime value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = emphasized
        ? colorScheme.onPrimaryContainer
        : CardoryColors.gray500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: emphasized
            ? colorScheme.primaryContainer
            : CardoryColors.gray100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$label ${formatDateTime(value)}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 10.5,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProgressTimeline extends StatelessWidget {
  const ProgressTimeline({
    super.key,
    required this.entries,
    required this.onEdit,
  });

  final List<ProjectProgressEntry> entries;
  final Future<void> Function(ProjectProgressEntry entry) onEdit;

  @override
  Widget build(BuildContext context) {
    final ordered = entries.reversed.toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '进度记录', subtitle: '按时间记录项目推进情况'),
          const SizedBox(height: 16),
          if (ordered.isEmpty)
            const EmptyCard(text: '暂无进度记录')
          else
            for (final entry in ordered) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: CardoryColors.primarySoft.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: CardoryColors.primary.withValues(alpha: 0.12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 17,
                          color: CardoryColors.primary,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          formatDateTime(entry.createdAt),
                          style: TextStyle(
                            color: CardoryColors.gray400,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: '编辑进度',
                          onPressed: () => onEdit(entry),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          color: CardoryColors.gray500,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.note,
                      style: TextStyle(
                        color: CardoryColors.gray600,
                        fontSize: 13,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
              if (entry != ordered.last) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class AssetDetailDialog extends StatelessWidget {
  const AssetDetailDialog({super.key, required this.asset});

  final AssetData asset;

  @override
  Widget build(BuildContext context) {
    final isSoftware = asset.type == AssetType.software;
    return AlertDialog(
      title: Row(
        children: [
          Icon(isSoftware ? Icons.apps_outlined : Icons.dns_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text(asset.name)),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Chip(label: Text(isSoftware ? '软件资产' : '硬件资产')),
              const SizedBox(height: 12),
              if (isSoftware) ...[
                _AssetDetailRow(label: '版本', value: asset.version),
                _AssetDetailRow(label: '端口', value: asset.port),
                _AssetDetailRow(label: '路径', value: asset.path),
              ] else ...[
                _AssetDetailRow(label: '服务器类型', value: asset.serverType),
                _AssetDetailRow(label: '服务器序列号', value: asset.serialNumber),
                _AssetDetailRow(label: '网络', value: asset.network),
              ],
              _AssetDetailRow(label: '登录用户名', value: asset.username),
              _AssetDetailRow(
                label: '登录密码',
                value: asset.password.isEmpty
                    ? ''
                    : '•' * asset.password.length,
              ),
              _AssetDetailRow(label: '备注 / 用途', value: asset.note),
              const SizedBox(height: 8),
              Text('变动记录', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              if (asset.activities.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '暂无变动记录',
                    style: TextStyle(color: CardoryColors.gray400),
                  ),
                )
              else
                for (final activity in asset.activities)
                  _AssetActivityRow(activity: activity),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          key: const Key('edit-asset-button'),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('编辑资产'),
        ),
      ],
    );
  }
}

class _AssetActivityRow extends StatelessWidget {
  const _AssetActivityRow({required this.activity});

  final AssetActivity activity;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (activity.kind) {
      AssetActivityKind.created => (
        Icons.add_circle_outline_rounded,
        CardoryColors.success,
      ),
      AssetActivityKind.updated => (Icons.edit_outlined, CardoryColors.primary),
      AssetActivityKind.deleted => (
        Icons.delete_outline_rounded,
        CardoryColors.error,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.message,
                  style: TextStyle(
                    color: CardoryColors.gray700,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDateTime(activity.timestamp),
                  style: TextStyle(
                    color: CardoryColors.gray400,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetDetailRow extends StatelessWidget {
  const _AssetDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        Text(value.isEmpty ? '未填写' : value),
      ],
    ),
  );
}

class AssetDialog extends StatefulWidget {
  const AssetDialog({
    super.key,
    this.asset,
    this.projectId = '',
    required this.serverTypes,
  });

  final AssetData? asset;
  final String projectId;
  final List<String> serverTypes;

  @override
  State<AssetDialog> createState() => _AssetDialogState();
}

class _AssetDialogState extends State<AssetDialog> {
  late AssetType _type = widget.asset?.type ?? AssetType.software;
  late final _name = TextEditingController(text: widget.asset?.name ?? '');
  late final _version = TextEditingController(
    text: widget.asset?.version ?? '',
  );
  late final _port = TextEditingController(text: widget.asset?.port ?? '');
  late final _path = TextEditingController(text: widget.asset?.path ?? '');
  late final _serialNumber = TextEditingController(
    text: widget.asset?.serialNumber ?? '',
  );
  late final _network = TextEditingController(
    text: widget.asset?.network ?? '',
  );
  late final _serverType = TextEditingController(
    text: widget.asset?.serverType ?? '',
  );
  late final _username = TextEditingController(
    text: widget.asset?.username ?? '',
  );
  late final _password = TextEditingController(
    text: widget.asset?.password ?? '',
  );
  late final _note = TextEditingController(text: widget.asset?.note ?? '');
  String? _error;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _version,
      _port,
      _path,
      _serialNumber,
      _network,
      _serverType,
      _username,
      _password,
      _note,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  InputDecoration _decoration(String label) =>
      InputDecoration(labelText: label, border: const OutlineInputBorder());

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写资产名称');
      return;
    }
    Navigator.pop(
      context,
      AssetData(
        id: widget.asset?.id ?? newId(),
        type: _type,
        name: name,
        projectId: widget.asset?.projectId ?? widget.projectId,
        version: _version.text.trim(),
        port: _port.text.trim(),
        path: _path.text.trim(),
        serialNumber: _serialNumber.text.trim(),
        network: _network.text.trim(),
        serverType: _serverType.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
        note: _note.text.trim(),
        activities: widget.asset?.activities ?? const [],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.asset == null ? '新增资产' : '编辑资产'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<AssetType>(
              segments: const [
                ButtonSegment(
                  value: AssetType.software,
                  label: Text('软件资产'),
                  icon: Icon(Icons.apps_outlined),
                ),
                ButtonSegment(
                  value: AssetType.hardware,
                  label: Text('硬件资产'),
                  icon: Icon(Icons.dns_outlined),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) =>
                  setState(() => _type = value.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              decoration: _decoration('资产名称 *'),
            ),
            const SizedBox(height: 12),
            if (_type == AssetType.software) ...[
              TextField(controller: _version, decoration: _decoration('版本')),
              const SizedBox(height: 12),
              TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                decoration: _decoration('端口'),
              ),
              const SizedBox(height: 12),
              TextField(controller: _path, decoration: _decoration('路径')),
            ] else ...[
              TextField(
                controller: _serialNumber,
                decoration: _decoration('服务器序列号'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _network,
                decoration: _decoration('网络 / IP / 网段'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: widget.serverTypes.contains(_serverType.text)
                    ? _serverType.text
                    : null,
                decoration: _decoration('服务器类型'),
                items: widget.serverTypes
                    .map(
                      (type) =>
                          DropdownMenuItem(value: type, child: Text(type)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _serverType.text = value ?? ''),
              ),
              if (widget.serverTypes.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('可在“设置 > 工作台偏好”中新增服务器类型。'),
                ),
            ],
            const SizedBox(height: 12),
            TextField(controller: _username, decoration: _decoration('登录用户名')),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: _decoration('登录密码'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              decoration: _decoration('备注 / 用途'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('保存')),
    ],
  );
}

class ProjectDialog extends StatefulWidget {
  const ProjectDialog({super.key, this.project});

  final ProjectData? project;

  @override
  State<ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<ProjectDialog> {
  late final _title = TextEditingController(text: widget.project?.title ?? '');
  late final _description = TextEditingController(
    text: widget.project?.description ?? '',
  );
  late ProjectPriority _priority =
      widget.project?.priority ?? ProjectPriority.p2;
  late ProjectStage _stage = widget.project?.stage ?? ProjectStage.planned;
  late DateTime? _startDate = widget.project?.startDate;
  late DateTime? _endDate = widget.project?.endDate;
  String? _error;

  Future<void> _pickDate(bool start) async {
    final minimum = start ? DateTime(2000) : _startDate ?? DateTime(2000);
    final candidate = (start ? _startDate : _endDate) ?? DateTime.now();
    final initial = candidate.isBefore(minimum) ? minimum : candidate;
    final picked = await showDatePicker(
      context: context,
      firstDate: minimum,
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
      _error = null;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.project == null ? '新建项目' : '编辑项目'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.68,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: '项目名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '项目说明'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: '开始日期（可选）',
                      value: _startDate,
                      onTap: () => _pickDate(true),
                      onClear: _startDate == null
                          ? null
                          : () => setState(() => _startDate = null),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DateField(
                      label: '结束日期（可选）',
                      value: _endDate,
                      onTap: () => _pickDate(false),
                      onClear: _endDate == null
                          ? null
                          : () => setState(() => _endDate = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ProjectPriority>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: '优先级'),
                items: ProjectPriority.values
                    .map(
                      (p) => DropdownMenuItem(value: p, child: Text(p.label)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _priority = v ?? _priority),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ProjectStage>(
                initialValue: _stage,
                decoration: const InputDecoration(labelText: '阶段'),
                items: ProjectStage.values
                    .map(
                      (s) => DropdownMenuItem(value: s, child: Text(s.label)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _stage = v ?? _stage),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) {
              setState(() => _error = '请输入项目名称。');
              return;
            }
            if (_startDate != null &&
                _endDate != null &&
                _endDate!.isBefore(_startDate!)) {
              setState(() => _error = '结束日期不能早于开始日期。');
              return;
            }
            Navigator.pop(
              context,
              ProjectData(
                id: widget.project?.id ?? newId(),
                title: _title.text.trim(),
                description: _description.text.trim(),
                startDate: _startDate,
                endDate: _endDate,
                priority: _priority,
                stage: _stage,
                progressEntries: widget.project?.progressEntries ?? const [],
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class TodoDialog extends StatefulWidget {
  const TodoDialog({
    super.key,
    required this.projects,
    this.todo,
    this.initialProject,
    this.recordSubTodoCreatedAt = false,
  });

  final List<ProjectData> projects;
  final TodoData? todo;
  final ProjectData? initialProject;
  final bool recordSubTodoCreatedAt;

  @override
  State<TodoDialog> createState() => _TodoDialogState();
}

class _TodoDialogState extends State<TodoDialog> {
  late final _title = TextEditingController(text: widget.todo?.title ?? '');
  late final _description = TextEditingController(
    text: widget.todo?.description ?? '',
  );
  late List<SubTodoData> _subTodos = List.of(widget.todo?.subTodos ?? const []);
  late ProjectData? _project = widget.todo == null
      ? widget.initialProject
      : widget.projects
            .where((p) => p.id == widget.todo!.projectId)
            .firstOrNull;
  late ProjectPriority _priority = widget.todo?.priority ?? ProjectPriority.p2;
  late DateTime? _startDate = widget.todo?.startDate;
  late DateTime? _endDate = widget.todo?.endDate;
  String? _error;

  Future<void> _pickDate(bool start) async {
    final minimum = start ? DateTime(2000) : _startDate ?? DateTime(2000);
    final candidate = (start ? _startDate : _endDate) ?? DateTime.now();
    final initial = candidate.isBefore(minimum) ? minimum : candidate;
    final picked = await showDatePicker(
      context: context,
      firstDate: minimum,
      lastDate: DateTime(2100),
      initialDate: initial,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
      _error = null;
    });
  }

  Future<void> _manageSubTodos() async {
    final result = await showDialog<List<SubTodoData>>(
      context: context,
      builder: (_) => SubTodoManagerDialog(
        initialSubTodos: _subTodos,
        recordCreatedAt: widget.recordSubTodoCreatedAt,
      ),
    );
    if (result != null && mounted) setState(() => _subTodos = result);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startDateField = _DateField(
      label: '开始日期（可选）',
      value: _startDate,
      onTap: () => _pickDate(true),
      onClear: _startDate == null
          ? null
          : () => setState(() => _startDate = null),
    );
    final endDateField = _DateField(
      label: '截止日期（可选）',
      value: _endDate,
      onTap: () => _pickDate(false),
      onClear: _endDate == null ? null : () => setState(() => _endDate = null),
    );
    final useVerticalDateLayout = MediaQuery.sizeOf(context).width < 600;
    return AlertDialog(
      title: Text(widget.todo == null ? '新建待办' : '待办详情 / 编辑'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.68,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                autofocus: widget.todo == null,
                decoration: const InputDecoration(labelText: '待办标题 *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '详细说明'),
              ),
              const SizedBox(height: 12),
              if (useVerticalDateLayout)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    startDateField,
                    const SizedBox(height: 8),
                    endDateField,
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(child: startDateField),
                    const SizedBox(width: 10),
                    Expanded(child: endDateField),
                  ],
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ProjectData?>(
                initialValue: _project,
                decoration: const InputDecoration(labelText: '关联项目'),
                items: [
                  const DropdownMenuItem<ProjectData?>(
                    value: null,
                    child: Text('未关联项目'),
                  ),
                  ...widget.projects.map(
                    (p) => DropdownMenuItem<ProjectData?>(
                      value: p,
                      child: Text(p.title),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _project = v),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ProjectPriority>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: '优先级'),
                items: ProjectPriority.values
                    .map(
                      (p) => DropdownMenuItem(value: p, child: Text(p.label)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _priority = v ?? _priority),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: CardoryColors.gray300),
                ),
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('子待办'),
                subtitle: Text(
                  _subTodos.isEmpty
                      ? '未添加，点击打开弹窗管理'
                      : '共 ${_subTodos.length} 项，已完成 ${_subTodos.where((item) => item.done).length} 项',
                ),
                trailing: const Icon(Icons.open_in_new_rounded, size: 19),
                onTap: _manageSubTodos,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) {
              setState(() => _error = '请输入待办标题。');
              return;
            }
            if (_startDate != null &&
                _endDate != null &&
                _endDate!.isBefore(_startDate!)) {
              setState(() => _error = '截止日期不能早于开始日期。');
              return;
            }
            Navigator.pop(
              context,
              TodoData(
                id: widget.todo?.id ?? newId(),
                title: _title.text.trim(),
                description: _description.text.trim(),
                startDate: _startDate,
                endDate: _endDate,
                projectId: _project?.id ?? '',
                projectTitle: _project?.title ?? '未关联项目',
                priority: _priority,
                done: widget.todo?.done ?? false,
                subTodos: _subTodos,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

SubTodoData _createSubTodo(
  String content, {
  required bool recordCreatedAt,
  DateTime? reminderAt,
}) {
  return SubTodoData(
    id: newId(),
    content: content,
    done: false,
    createdAt: recordCreatedAt ? DateTime.now() : null,
    dueAt: reminderAt,
  );
}

Future<DateTime?> _showReminderDateTimePicker(
  BuildContext context,
  DateTime initial,
) async {
  final firstDate = DateTime(2000);
  final lastDate = DateTime(2100);
  final initialDate = initial.isBefore(firstDate)
      ? firstDate
      : initial.isAfter(lastDate)
      ? lastDate
      : initial;
  final date = await showDatePicker(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    initialDate: initialDate,
  );
  if (date == null || !context.mounted) return null;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

class QuickAddSubTodoDialog extends StatefulWidget {
  const QuickAddSubTodoDialog({super.key, required this.recordCreatedAt});

  final bool recordCreatedAt;

  @override
  State<QuickAddSubTodoDialog> createState() => _QuickAddSubTodoDialogState();
}

class _QuickAddSubTodoDialogState extends State<QuickAddSubTodoDialog> {
  final TextEditingController _content = TextEditingController();
  DateTime? _reminderAt;
  String? _error;

  Future<void> _pickReminderAt() async {
    final selected = await _showReminderDateTimePicker(
      context,
      _reminderAt ?? DateTime.now(),
    );
    if (selected == null || !mounted) return;
    setState(() => _reminderAt = selected);
  }

  void _submit() {
    final content = _content.text.trim();
    if (content.isEmpty) {
      setState(() => _error = '请输入子提醒内容。');
      return;
    }
    Navigator.pop(
      context,
      _createSubTodo(
        content,
        recordCreatedAt: widget.recordCreatedAt,
        reminderAt: _reminderAt,
      ),
    );
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('快捷添加子提醒'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('quick-add-subtodo-content'),
            controller: _content,
            autofocus: true,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: '子提醒内容',
              hintText: '输入内容，支持换行',
              alignLabelWithHint: true,
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('quick-add-subtodo-reminder-time'),
                  onPressed: _pickReminderAt,
                  icon: Icon(
                    _reminderAt == null
                        ? Icons.alarm_add_outlined
                        : Icons.edit_calendar_outlined,
                  ),
                  label: Text(
                    _reminderAt == null
                        ? '设置提醒时间'
                        : '提醒 ${formatDateTime(_reminderAt!)}',
                  ),
                ),
              ),
              if (_reminderAt != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '清除提醒时间',
                  onPressed: () => setState(() => _reminderAt = null),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton.icon(
        onPressed: _submit,
        icon: const Icon(Icons.add_rounded),
        label: const Text('添加'),
      ),
    ],
  );
}

class SubTodoManagerDialog extends StatefulWidget {
  const SubTodoManagerDialog({
    super.key,
    required this.initialSubTodos,
    this.recordCreatedAt = false,
  });

  final List<SubTodoData> initialSubTodos;
  final bool recordCreatedAt;

  @override
  State<SubTodoManagerDialog> createState() => _SubTodoManagerDialogState();
}

class _SubTodoManagerDialogState extends State<SubTodoManagerDialog> {
  late final List<SubTodoData> _subTodos = List.of(widget.initialSubTodos);
  final TextEditingController _newSubTodoContent = TextEditingController();
  final FocusNode _newSubTodoContentFocus = FocusNode();
  String? _addError;

  void _addSubTodo() {
    final content = _newSubTodoContent.text.trim();
    if (content.isEmpty) {
      setState(() => _addError = '请输入子任务内容。');
      return;
    }
    setState(() {
      _subTodos.add(
        _createSubTodo(content, recordCreatedAt: widget.recordCreatedAt),
      );
      _newSubTodoContent.clear();
      _addError = null;
    });
    _newSubTodoContentFocus.requestFocus();
  }

  Future<void> _toggleDueAt(int index, bool enabled) async {
    if (!enabled) {
      setState(
        () => _subTodos[index] = _subTodos[index].copyWith(clearDueAt: true),
      );
      return;
    }
    final current = _subTodos[index].dueAt ?? DateTime.now();
    final reminderAt = await _showReminderDateTimePicker(context, current);
    if (reminderAt == null || !mounted) return;
    setState(() {
      _subTodos[index] = _subTodos[index].copyWith(dueAt: reminderAt);
    });
  }

  Future<void> _changeDueAt(int index) async {
    await _toggleDueAt(index, true);
  }

  Future<void> _editSubTodo(SubTodoData subTodo) async {
    final controller = TextEditingController(text: subTodo.content);
    final content = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑子待办'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: '内容 *',
            alignLabelWithHint: true,
          ),
          minLines: 4,
          maxLines: 10,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (content == null || !mounted) return;
    setState(() {
      final index = _subTodos.indexWhere((item) => item.id == subTodo.id);
      if (index >= 0) _subTodos[index] = subTodo.copyWith(content: content);
    });
  }

  @override
  void dispose() {
    _newSubTodoContent.dispose();
    _newSubTodoContentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('管理子待办'),
    content: SizedBox(
      width: 680,
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _newSubTodoContent,
                  focusNode: _newSubTodoContentFocus,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: '子任务内容',
                    hintText: '输入内容，支持换行',
                    alignLabelWithHint: true,
                    errorText: _addError,
                  ),
                  onChanged: (_) {
                    if (_addError != null) setState(() => _addError = null);
                  },
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _addSubTodo,
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _subTodos.isEmpty
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.account_tree_outlined, size: 42),
                      SizedBox(height: 10),
                      Text('暂无子待办'),
                    ],
                  )
                : ListView.separated(
                    itemCount: _subTodos.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _subTodos[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 6, 6),
                          child: Column(
                            children: [
                              ListTile(
                                leading: IconButton(
                                  tooltip: item.done ? '标记未完成' : '标记完成',
                                  onPressed: () => setState(
                                    () => _subTodos[index] = item.copyWith(
                                      done: !item.done,
                                    ),
                                  ),
                                  icon: Icon(
                                    item.done
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: item.done
                                        ? CardoryColors.success
                                        : CardoryColors.gray400,
                                  ),
                                ),
                                title: Text(
                                  item.content,
                                  style: TextStyle(
                                    decoration: item.done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                subtitle: item.createdAt == null
                                    ? null
                                    : Text(
                                        '添加于 ${formatDateTime(item.createdAt!)}',
                                      ),
                                onTap: () => _editSubTodo(item),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: '编辑',
                                      onPressed: () => _editSubTodo(item),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: '删除',
                                      onPressed: () => setState(
                                        () => _subTodos.removeAt(index),
                                      ),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 18,
                                      color: CardoryColors.gray500,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('提醒时间'),
                                          if (item.dueAt == null)
                                            Text(
                                              '未设置',
                                              style: TextStyle(
                                                color: CardoryColors.gray400,
                                                fontSize: 11.5,
                                              ),
                                            )
                                          else
                                            InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              onTap: () => _changeDueAt(index),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 3,
                                                    ),
                                                child: Text(
                                                  formatDateTime(item.dueAt!),
                                                  style: TextStyle(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Switch.adaptive(
                                      value: item.dueAt != null,
                                      onChanged: (value) =>
                                          _toggleDueAt(index, value),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, List<SubTodoData>.of(_subTodos)),
        child: const Text('完成'),
      ),
    ],
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
          suffixIcon: onClear == null
              ? null
              : IconButton(
                  tooltip: '清除日期',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
        ),
        child: Text(
          value == null ? '未设置' : formatDate(value!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  );
}

class SettingsResult {
  const SettingsResult({
    required this.settings,
    required this.credentials,
    required this.selfHostedToken,
  });

  final AppSettings settings;
  final WebDavCredentials credentials;
  final String selfHostedToken;
}

class PasswordChangeResult {
  const PasswordChangeResult({
    required this.currentPassword,
    required this.newPassword,
  });

  final String currentPassword;
  final String newPassword;
}

class PasswordChangeDialog extends StatefulWidget {
  const PasswordChangeDialog({super.key});

  @override
  State<PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<PasswordChangeDialog> {
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    if (_newPassword.text.length < 8) {
      setState(() => _error = '新密码至少需要 8 个字符。');
      return;
    }
    if (_newPassword.text != _confirmation.text) {
      setState(() => _error = '两次输入的新密码不一致。');
      return;
    }
    Navigator.pop(
      context,
      PasswordChangeResult(
        currentPassword: _currentPassword.text,
        newPassword: _newPassword.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('修改密码'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _currentPassword,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: '当前密码'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _newPassword,
            obscureText: true,
            decoration: const InputDecoration(labelText: '新密码'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmation,
            obscureText: true,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: '确认新密码'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('修改密码')),
    ],
  );
}

class RecoveryKeyDialog extends StatefulWidget {
  const RecoveryKeyDialog({super.key, required this.recoveryKey});

  final String recoveryKey;

  @override
  State<RecoveryKeyDialog> createState() => _RecoveryKeyDialogState();
}

class _RecoveryKeyDialogState extends State<RecoveryKeyDialog> {
  String? _message;

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.recoveryKey));
      if (mounted) {
        setState(() => _message = '恢复码已复制，请粘贴到安全位置手动保存。');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = '复制失败，请直接选择上方恢复码并手动复制。');
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('保存新恢复码'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('旧恢复码已失效。新恢复码可用于重设密码或恢复备份。'),
          const SizedBox(height: 6),
          const Text('请复制恢复码，并粘贴到你信任的离线位置手动保存。'),
          const SizedBox(height: 18),
          SelectableText(
            widget.recoveryKey,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          if (_message != null) ...[
            const SizedBox(height: 14),
            Text(_message!),
          ],
        ],
      ),
    ),
    actions: [
      OutlinedButton.icon(
        onPressed: _copy,
        icon: const Icon(Icons.copy_rounded),
        label: const Text('复制恢复码'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('我已保存'),
      ),
    ],
  );
}

class BackupRecoveryCredentials {
  const BackupRecoveryCredentials({
    required this.recoveryKey,
    required this.newPassword,
  });

  final String recoveryKey;
  final String newPassword;
}

class BackupRecoveryDialog extends StatefulWidget {
  const BackupRecoveryDialog({super.key, required this.fileName});

  final String fileName;

  @override
  State<BackupRecoveryDialog> createState() => _BackupRecoveryDialogState();
}

class _BackupRecoveryDialogState extends State<BackupRecoveryDialog> {
  final _recoveryKey = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _recoveryKey.dispose();
    _newPassword.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    if (_newPassword.text.length < 8) {
      setState(() => _error = '密码至少需要 8 个字符。');
      return;
    }
    if (_newPassword.text != _confirmation.text) {
      setState(() => _error = '两次输入的密码不一致。');
      return;
    }
    Navigator.pop(
      context,
      BackupRecoveryCredentials(
        recoveryKey: _recoveryKey.text,
        newPassword: _newPassword.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('恢复数据'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.fileName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text('恢复后当前数据文件将保留为 .bak 备份。'),
            const SizedBox(height: 16),
            TextField(
              key: const Key('settings-restore-recovery-key'),
              controller: _recoveryKey,
              decoration: const InputDecoration(
                labelText: '恢复码',
                prefixIcon: Icon(Icons.key_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('settings-restore-new-password'),
              controller: _newPassword,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '新密码',
                prefixIcon: Icon(Icons.password_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('settings-restore-confirm-password'),
              controller: _confirmation,
              obscureText: true,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: '确认新密码',
                prefixIcon: Icon(Icons.password_rounded),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton.icon(
        key: const Key('confirm-settings-restore'),
        onPressed: _submit,
        icon: const Icon(Icons.restore_rounded),
        label: const Text('恢复'),
      ),
    ],
  );
}

enum SettingsCategoryType { workspace, security, localData, sync }

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.settings,
    required this.currentDataPath,
    required this.credentialStore,
    this.category,
    this.embedded = false,
    this.onSave,
  }) : assert(!embedded || onSave != null);

  final AppSettings settings;
  final String currentDataPath;
  final SyncCredentialStore credentialStore;
  final SettingsCategoryType? category;
  final bool embedded;
  final ValueChanged<SettingsResult>? onSave;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late int _themeColorValue = widget.settings.themeColorValue;
  late int _backgroundColorValue = widget.settings.backgroundColorValue;
  late ProjectPriority _homeReminderPriorityThreshold =
      widget.settings.homeReminderPriorityThreshold;
  late bool _recordSubTodoCreatedAt = widget.settings.recordSubTodoCreatedAt;
  late bool _autoLockEnabled = widget.settings.autoLockEnabled;
  late final List<String> _serverTypes = [...widget.settings.serverTypes];
  final TextEditingController _newServerType = TextEditingController();
  late SyncProviderType _syncProvider = widget.settings.syncProvider;
  late final TextEditingController _dataPath = TextEditingController(
    text: widget.settings.dataPath.isEmpty
        ? widget.currentDataPath
        : widget.settings.dataPath,
  );
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
  late final TextEditingController _themeHex = TextEditingController(
    text: _themeColorHex(_themeColorValue),
  );
  late final TextEditingController _backgroundHex = TextEditingController(
    text: _themeColorHex(_backgroundColorValue),
  );
  bool _hasStoredWebDavPassword = false;
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
    widget.credentialStore.readWebDav().then((credentials) {
      if (!mounted) return;
      setState(() => _hasStoredWebDavPassword = credentials != null);
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
    };
  }

  @override
  void dispose() {
    _dataPath.dispose();
    _newServerType.dispose();
    _syncDirectory.dispose();
    _webDavUrl.dispose();
    _webDavUsername.dispose();
    _webDavPassword.dispose();
    _selfHostedUrl.dispose();
    _selfHostedToken.dispose();
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
                  child: Text(_reminderPriorityRangeLabel(priority)),
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
          subtitle: const Text('锁定后需重新输入密码或恢复码才能访问数据'),
          value: _autoLockEnabled,
          onChanged: (value) => setState(() => _autoLockEnabled = value),
        ),
      ],
      if (_shows(SettingsCategoryType.localData)) ...[
        const SizedBox(height: 22),
        const Text('本地数据', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        TextField(
          controller: _dataPath,
          decoration: const InputDecoration(
            labelText: '本地数据文件存储路径',
            hintText:
                r'C:\Users\你的用户名\Documents\Cardory\cardory-current-data.cardory',
          ),
        ),
      ],
      if (_shows(SettingsCategoryType.sync)) ...[
        const SizedBox(height: 22),
        const Text('同步', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        DropdownButtonFormField<SyncProviderType>(
          initialValue: _syncProvider,
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
              value: SyncProviderType.selfHosted,
              child: Text('自托管 API'),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _syncProvider = value);
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
            decoration: const InputDecoration(
              labelText: 'WebDAV 地址',
              hintText: 'https://dav.example.com/cardory/',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _webDavUsername,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _webDavPassword,
            obscureText: true,
            decoration: InputDecoration(
              labelText: _hasStoredWebDavPassword ? '密码（已保存）' : '密码',
              helperText: _hasStoredWebDavPassword
                  ? '留空将保留系统安全凭据存储中的密码'
                  : '密码仅保存到系统安全凭据存储',
            ),
          ),
        ],
        if (_syncProvider == SyncProviderType.selfHosted) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _selfHostedUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '自托管 API 地址',
              hintText: 'https://sync.example.com/v1/cardory/container',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _selfHostedToken,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '访问令牌',
              helperText: '令牌仅保存到系统安全凭据存储',
            ),
          ),
        ],
      ],
    ],
  );

  SettingsResult _result() => SettingsResult(
    settings: widget.settings.copyWith(
      themeColorValue: _themeColorValue,
      backgroundColorValue: _backgroundColorValue,
      homeReminderPriorityThreshold: _homeReminderPriorityThreshold,
      recordSubTodoCreatedAt: _recordSubTodoCreatedAt,
      autoLockEnabled: _autoLockEnabled,
      serverTypes: _serverTypes,
      dataPath: _dataPath.text.trim(),
      syncProvider: _syncProvider,
      syncDirectoryPath: _syncDirectory.text.trim(),
      webDavUrl: _webDavUrl.text.trim(),
      webDavUsername: _webDavUsername.text.trim(),
      selfHostedUrl: _selfHostedUrl.text.trim(),
      clearSyncState: _syncEndpointChanged(),
    ),
    credentials: WebDavCredentials(password: _webDavPassword.text),
    selfHostedToken: _selfHostedToken.text,
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
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(999),
    onTap: onTap,
    child: Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Color(color),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? CardoryColors.primary : CardoryColors.gray200,
          width: selected ? 3 : 1,
        ),
      ),
    ),
  );
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

class ProgressDialog extends StatefulWidget {
  const ProgressDialog({super.key, this.currentProgress, this.entry})
    : assert(currentProgress != null || entry != null);

  final double? currentProgress;
  final ProjectProgressEntry? entry;

  @override
  State<ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<ProgressDialog> {
  late final _note = TextEditingController(text: widget.entry?.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.entry == null ? '记录进度' : '编辑进度'),
    content: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 460,
        maxHeight: MediaQuery.sizeOf(context).height * 0.68,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _note,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(labelText: '进度说明'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          Navigator.pop(
            context,
            ProjectProgressEntry(
              id: widget.entry?.id ?? newId(),
              note: _note.text.trim().isEmpty ? '更新项目进度' : _note.text.trim(),
              progress: widget.entry?.progress ?? widget.currentProgress ?? 0,
              createdAt: widget.entry?.createdAt ?? DateTime.now(),
            ),
          );
        },
        child: const Text('保存'),
      ),
    ],
  );
}

String _reminderPriorityRangeLabel(ProjectPriority priority) =>
    switch (priority) {
      ProjectPriority.p0 => '高优先级及以上',
      ProjectPriority.p1 => '中优先级及以上',
      ProjectPriority.p2 => '普通优先级及以上',
      ProjectPriority.p3 => '全部优先级',
    };

String _themeColorHex(int value) =>
    '#${value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({
    super.key,
    required this.dataPath,
    required this.settings,
    required this.syncStatus,
    required this.onSync,
    required this.onOpenSettings,
    required this.onChangePassword,
    required this.onRestoreBackup,
  });

  final String dataPath;
  final AppSettings settings;
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
        const SectionTitle(title: '设置', subtitle: '分别管理工作台、安全、本地数据与同步'),
        const SizedBox(height: 16),
        _SettingsCategory(
          icon: Icons.tune_rounded,
          title: '工作台偏好',
          description:
              '主页提醒：${_reminderPriorityRangeLabel(settings.homeReminderPriorityThreshold)}',
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
          icon: Icons.folder_outlined,
          title: '本地数据',
          description: '数据文件：$dataPath',
          onPressed: () => onOpenSettings(SettingsCategoryType.localData),
        ),
        const SizedBox(height: 10),
        _SettingsCategory(
          icon: Icons.sync_rounded,
          title: '同步',
          description: '同步方式：${_syncProviderLabel(settings.syncProvider)}',
          onPressed: () => onOpenSettings(SettingsCategoryType.sync),
        ),
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
    SyncProviderType.selfHosted => '未启用',
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

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          color: CardoryColors.gray900,
          fontSize: 16,
          letterSpacing: -0.2,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        subtitle,
        style: TextStyle(color: CardoryColors.gray500, fontSize: 12.5),
      ),
    ],
  );
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.priority});

  final ProjectPriority priority;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: priority.color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      priority.label,
      style: TextStyle(
        color: priority.color,
        fontSize: 11,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class StageBadge extends StatelessWidget {
  const StageBadge({super.key, required this.stage});

  final ProjectStage stage;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: stage.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      stage.label,
      style: TextStyle(
        color: stage.color,
        fontSize: 11,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class CountPill extends StatelessWidget {
  const CountPill({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: CardoryColors.gray100,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      '$count',
      style: TextStyle(
        color: CardoryColors.gray600,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
    decoration: BoxDecoration(
      color: CardoryColors.gray50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: CardoryColors.gray200),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: CardoryColors.gray400, fontSize: 12.5),
    ),
  );
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

BoxDecoration cardDecoration() => cardoryCard();
BoxDecoration darkCardDecoration() => cardoryDarkHero();
