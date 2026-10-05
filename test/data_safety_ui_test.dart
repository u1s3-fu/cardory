// P0 数据安全 UI 测试：
// - 设置页「数据安全」分区（备份导出与回收站入口）；
// - 回收站对话框（列表 + 恢复确认链路）；
// - 保险库创建流程的风险确认勾选。

import 'package:cardory/application/recycle_bin_store.dart';
import 'package:cardory/application/workspace_controller.dart';
import 'package:cardory/application/workspace_settings_service.dart';
import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/domain/cardory_repository.dart';
import 'package:cardory/domain/recycle_bin_models.dart';
import 'package:cardory/domain/sync_credentials.dart';
import 'package:cardory/presentation/pages/settings_page.dart';
import 'package:cardory/presentation/pages/vault_gate.dart';
import 'package:cardory/presentation/settings_models.dart';
import 'package:cardory/presentation/widgets/recycle_bin_dialog.dart';
import 'package:cardory/sync/sync_coordinator.dart';
import 'package:cardory/sync/sync_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryRepository implements CardoryRepository {
  @override
  Future<CardoryAccessState> accessState() async =>
      CardoryAccessState.setupRequired;

  @override
  Future<CardoryLoadResult> load() async => CardoryLoadResult(
    data: const CardoryData.empty(),
    settings: const AppSettings(),
    path: 'memory/cardory.db',
  );

  @override
  Future<void> save(CardoryData data, AppSettings settings) async {}

  @override
  Future<void> saveSettings(AppSettings settings) async {}

  @override
  Future<CardoryLoadResult> setup(String password) async {
    setupCalled = true;
    return load();
  }

  bool setupCalled = false;

  @override
  Future<CardoryLoadResult> unlockWithPassword(String password) => load();

  @override
  Future<CardoryLoadResult> restoreFromBackup(
    List<int> bytes,
    String password,
  ) => load();

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {}

  @override
  Future<List<int>> exportContainer() async => const [1];

  @override
  Future<CardoryData> importContainer(
    List<int> bytes,
    AppSettings settings,
  ) async => const CardoryData.empty();

  @override
  Future<String> saveSyncConflictSnapshot(
    List<int> bytes, {
    DateTime? timestamp,
  }) async => 'snapshot';
}

class _MemoryCredentialStore implements SyncCredentialStore {
  @override
  Future<SyncCredentials> read() async => const SyncCredentials();

  @override
  Future<void> write(SyncCredentials credentials) async {}
}

class _MemoryVaultCredentialStore implements VaultCredentialStore {
  @override
  Future<String?> readPassword() async => null;

  @override
  Future<void> writePassword(String value) async {}

  @override
  Future<void> deletePassword() async {}
}

class _FakeRecycleBinStore implements RecycleBinStore {
  _FakeRecycleBinStore(this.entries);

  List<RecycleBinEntry> entries;
  final List<RecycleBinEntry> restored = [];

  @override
  Future<List<RecycleBinEntry>> loadEntries() async => entries;

  @override
  Future<void> restore(RecycleBinEntityType type, String id) async {
    restored.add(entries.firstWhere((entry) => entry.id == id));
    entries = entries.where((entry) => entry.id != id).toList();
  }
}

void main() {
  group('设置页数据安全分区', () {
    testWidgets('提供回调时展示导出与回收站入口，导出结果显示为提示条', (tester) async {
      var recycleOpened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsDialog(
                settings: const AppSettings(),
                credentialStore: _MemoryCredentialStore(),
                category: SettingsCategoryType.dataSafety,
                embedded: true,
                onSave: (_) {},
                onExportBackup: () async => '备份已导出：cardory-backup-1',
                onOpenRecycleBin: () => recycleOpened = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('导出加密备份'), findsOneWidget);
      expect(find.text('打开回收站'), findsOneWidget);

      await tester.tap(find.byKey(const Key('open-recycle-bin')));
      await tester.pumpAndSettle();
      expect(recycleOpened, isTrue);

      await tester.tap(find.byKey(const Key('export-backup')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('备份已导出'), findsOneWidget);
    });

    testWidgets('未提供回调时不渲染数据安全操作入口', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsDialog(
                settings: const AppSettings(),
                credentialStore: _MemoryCredentialStore(),
                category: SettingsCategoryType.dataSafety,
                embedded: true,
                onSave: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('export-backup')), findsNothing);
      expect(find.byKey(const Key('open-recycle-bin')), findsNothing);
    });
  });

  group('回收站对话框', () {
    testWidgets('列出软删除条目；确认后恢复并刷新列表', (tester) async {
      final repository = _MemoryRepository();
      final store = _FakeRecycleBinStore([
        RecycleBinEntry(
          type: RecycleBinEntityType.project,
          id: 'p1',
          title: '项目一',
          deletedAt: DateTime.utc(2026, 10, 1),
        ),
        RecycleBinEntry(
          type: RecycleBinEntityType.task,
          id: 't1',
          title: '待办一',
          subtitle: '子待办',
          deletedAt: DateTime.utc(2026, 10, 4),
        ),
      ]);
      final controllerWithBin = WorkspaceController(
        repository: repository,
        vaultRepository: repository,
        settingsService: WorkspaceSettingsService(
          repository: repository,
          credentialStore: _MemoryCredentialStore(),
        ),
        syncService: SyncCoordinator(
          repository: repository,
          providerFactory: (_) async =>
              throw const SyncUnavailableException('not used'),
          attachmentRepositoryFactory: (_) =>
              throw UnimplementedError('回收站测试不使用附件'),
        ),
        attachmentRepositoryFactory: (_) =>
            throw UnimplementedError('回收站测试不使用附件'),
        recycleBinStore: store,
      );
      await controllerWithBin.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => RecycleBinDialog.show(
                    context,
                    controller: controllerWithBin,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('项目一'), findsOneWidget);
      expect(find.text('待办一'), findsOneWidget);
      expect(find.textContaining('剩余'), findsNWidgets(2));

      // 恢复「待办一」：确认框 → 确认。
      final tile = find.ancestor(
        of: find.text('待办一'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: tile.first, matching: find.text('恢复')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '恢复'));
      await tester.pumpAndSettle();

      expect(store.restored.map((entry) => entry.id), ['t1']);
      // 恢复后列表刷新，条目消失并出现成功提示。
      expect(find.text('待办一'), findsNothing);
      expect(find.textContaining('已恢复'), findsOneWidget);
    });
  });

  group('保险库创建风险确认', () {
    testWidgets('未勾选风险确认时无法创建保险库；勾选后可创建', (tester) async {
      final repository = _MemoryRepository();
      var unlocked = false;
      await tester.pumpWidget(
        MaterialApp(
          home: CardoryVaultGate(
            vaultRepository: repository,
            workspaceRepository: repository,
            credentialStore: _MemoryCredentialStore(),
            vaultCredentialStore: _MemoryVaultCredentialStore(),
            attachmentRepositoryFactory: (_) =>
                throw UnimplementedError('setup 流程不使用附件'),
            onSettingsChanged: (_) {},
            onUnlocked: (_) => unlocked = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'test-password-1');
      await tester.enterText(find.byType(TextField).at(1), 'test-password-1');
      await tester.pumpAndSettle();

      // 未勾选：点击创建只提示风险未确认。
      await tester.tap(find.text('创建加密保险库'));
      await tester.pumpAndSettle();
      expect(repository.setupCalled, isFalse);
      expect(find.textContaining('请先确认'), findsOneWidget);

      await tester.tap(find.byKey(const Key('vault-risk-acknowledged')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建加密保险库'));
      await tester.pumpAndSettle();

      expect(repository.setupCalled, isTrue);
      expect(unlocked, isTrue);
    });
  });
}
