// 保险库会话门禁全流程（widget 级）：
// 已保存密码自动解锁 → 工作台；应用切后台自动锁定 →
// 关闭数据库会话 + 删除已保存密码 + 清除小组件摘要 → 回到门禁页。

import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/domain/cardory_repository.dart';
import 'package:cardory/domain/sync_credentials.dart';
import 'package:cardory/domain/widget_data_service.dart';
import 'package:cardory/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 会话状态可控的组合仓库：锁定后 [state] 切回 locked，
/// 门禁页重建重检时不会再自动进入工作台。
class _LockingRepository implements CardoryRepository {
  _LockingRepository(this.data);

  final CardoryData data;
  CardoryAccessState state = CardoryAccessState.locked;

  void lock() => state = CardoryAccessState.locked;

  @override
  Future<CardoryAccessState> accessState() async => state;

  @override
  Future<CardoryLoadResult> load() async => CardoryLoadResult(
    data: data,
    settings: const AppSettings(),
    path: 'memory/cardory.db',
  );

  @override
  Future<CardoryLoadResult> setup(String password) async {
    state = CardoryAccessState.unlocked;
    return load();
  }

  @override
  Future<CardoryLoadResult> unlockWithPassword(String password) async {
    state = CardoryAccessState.unlocked;
    return load();
  }

  @override
  Future<CardoryLoadResult> restoreFromBackup(
    List<int> bytes,
    String password,
  ) async {
    state = CardoryAccessState.unlocked;
    return load();
  }

  @override
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {}

  @override
  Future<List<int>> exportContainer() async => [1, 2, 3];

  @override
  Future<String> saveSyncConflictSnapshot(
    List<int> bytes, {
    DateTime? timestamp,
  }) async => 'memory.conflict.cardory';

  @override
  Future<CardoryData> importContainer(
    List<int> bytes,
    AppSettings settings,
  ) async => data;

  @override
  Future<void> save(CardoryData data, AppSettings settings) async {}

  @override
  Future<void> saveSettings(AppSettings settings) async {}
}

/// 会话：锁定回调把仓库切回 locked 并记录调用次数。
class _LockingVaultSession implements VaultSessionRepository {
  _LockingVaultSession(this.repository);

  final _LockingRepository repository;
  int lockCount = 0;

  @override
  Future<void> lock() async {
    lockCount += 1;
    repository.lock();
  }
}

/// 内存凭据：预置已保存密码，验证 deletePassword 是否被调用。
class _FakeVaultCredentialStore implements VaultCredentialStore {
  String? password = 'test-password';

  @override
  Future<String?> readPassword() async => password;

  @override
  Future<void> writePassword(String value) async => password = value;

  @override
  Future<void> deletePassword() async => password = null;
}

class _FakeSyncCredentialStore implements SyncCredentialStore {
  @override
  Future<SyncCredentials> read() async => const SyncCredentials();

  @override
  Future<void> write(SyncCredentials credentials) async {}
}

/// 记录小组件摘要清理次数的适配器。
class _RecordingWidgetService implements WidgetDataService {
  int clearCount = 0;

  @override
  Future<void> updateWidgetData(CardoryData data) async {}

  @override
  Future<void> clearWidgetData() async => clearCount += 1;
}

void main() {
  // HomePage 含持续动画，不能用 pumpAndSettle；按既有测试惯例逐帧推进。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Widget buildApp({
    required _LockingRepository repository,
    required _LockingVaultSession session,
    required _RecordingWidgetService widgetService,
    required _FakeVaultCredentialStore vaultCredentialStore,
  }) {
    return CardoryApp(
      vaultRepository: repository,
      workspaceRepository: repository,
      syncRepository: repository,
      vaultSession: session,
      credentialStore: _FakeSyncCredentialStore(),
      vaultCredentialStore: vaultCredentialStore,
      widgetDataService: widgetService,
    );
  }

  testWidgets('已保存密码自动解锁进入工作台，切后台自动锁定并清理凭据与小组件摘要', (tester) async {
    final repository = _LockingRepository(CardoryData.seed());
    final session = _LockingVaultSession(repository);
    final widgetService = _RecordingWidgetService();
    final vaultCredentialStore = _FakeVaultCredentialStore();

    await tester.pumpWidget(
      buildApp(
        repository: repository,
        session: session,
        widgetService: widgetService,
        vaultCredentialStore: vaultCredentialStore,
      ),
    );
    // 自动解锁 + 路由切换到工作台（HomePage）。
    await settle(tester);
    expect(repository.state, CardoryAccessState.unlocked);
    expect(find.byType(HomePage), findsOneWidget);

    // 应用切后台：触发自动锁定（autoLockEnabled 默认开启）。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);
    // 回到前台后应用应停留在门禁页。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);

    // 锁定流程四件事齐备：
    expect(session.lockCount, 1, reason: '应调用 vaultSession.lock() 关闭数据库会话');
    expect(vaultCredentialStore.password, isNull, reason: '应删除已保存密码');
    expect(widgetService.clearCount, 1, reason: '应清除桌面小组件敏感摘要');
    // 门禁重新检测后保持 locked：仓库已切回，工作台不再出现。
    expect(repository.state, CardoryAccessState.locked);
    expect(find.byType(HomePage), findsNothing);
  });

  testWidgets('自动锁定后再次解锁可重新进入工作台', (tester) async {
    final repository = _LockingRepository(CardoryData.seed());
    final session = _LockingVaultSession(repository);
    final widgetService = _RecordingWidgetService();
    final vaultCredentialStore = _FakeVaultCredentialStore();

    await tester.pumpWidget(
      buildApp(
        repository: repository,
        session: session,
        widgetService: widgetService,
        vaultCredentialStore: vaultCredentialStore,
      ),
    );
    await settle(tester);
    expect(find.byType(HomePage), findsOneWidget);

    // 第一次自动锁定。
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(find.byType(HomePage), findsNothing);

    // 门禁页当前显示 locked 表单：手动输入密码后解锁重新进入工作台。
    final unlockButton = find.widgetWithText(FilledButton, '解锁');
    expect(unlockButton, findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'test-password');
    await tester.tap(unlockButton);
    await settle(tester);
    expect(repository.state, CardoryAccessState.unlocked);
    expect(find.byType(HomePage), findsOneWidget);
  });
}
