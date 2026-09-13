import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/row_level_workspace_store.dart';
import '../application/workspace_controller_factory.dart';
import '../data/attachment_store.dart';
import '../data/repositories/drift_row_level_workspace_store.dart';
import '../data/runtime/sqlcipher_vault_store.dart';
import '../domain/attachment_repository.dart';
import '../domain/cardory_models.dart';
import '../domain/cardory_repository.dart';
import '../domain/widget_data_service.dart';
import '../services/home_widget_data_service.dart';
import '../sync/sync_coordinator.dart';
import '../sync/sync_credentials.dart';
import '../sync/sync_provider_registry.dart';

/// The breaking release uses SQLCipher as its only runtime store.
final sqlCipherVaultStoreProvider = Provider<SqlCipherVaultStore>((ref) {
  final store = SqlCipherVaultStore();
  ref.onDispose(store.lock);
  return store;
});

final vaultRepositoryProvider = Provider<VaultRepository>(
  (ref) => ref.watch(sqlCipherVaultStoreProvider),
);

final workspaceRepositoryProvider = Provider<WorkspaceRepository>(
  (ref) => ref.watch(sqlCipherVaultStoreProvider),
);

final syncRepositoryProvider = Provider<SyncRepository>(
  (ref) => ref.watch(sqlCipherVaultStoreProvider),
);

final vaultSessionRepositoryProvider = Provider<VaultSessionRepository>(
  (ref) => ref.watch(sqlCipherVaultStoreProvider),
);

final syncCredentialStoreProvider = Provider<SyncCredentialStore>(
  (ref) => SecureSyncCredentialStore(),
);

final vaultCredentialStoreProvider = Provider<VaultCredentialStore>(
  (ref) => SecureVaultCredentialStore(),
);

final syncProviderFactoryProvider = Provider<SyncProviderFactory>(
  (ref) => defaultSyncProviderFactory(ref.watch(syncCredentialStoreProvider)),
);

final widgetDataServiceProvider = Provider<WidgetDataService>(
  (ref) => const HomeWidgetDataService(),
);

final attachmentRepositoryFactoryProvider =
    Provider<AttachmentRepositoryFactory>((ref) => AttachmentStore.forDataFile);

/// 行级写入存储的惰性构建器：保险库解锁后控制器创建时才调用；
/// 数据库会话未开启（如测试注入假仓库）时返回 null。
final rowLevelStoreBuilderProvider = Provider<RowLevelWorkspaceStoreBuilder>(
  (ref) => () {
    final database = ref.watch(sqlCipherVaultStoreProvider).database;
    return database == null ? null : DriftRowLevelWorkspaceStore(database);
  },
);

typedef SyncConnectionTester =
    Future<void> Function(AppSettings settings, SyncCredentials credentials);

final syncConnectionTesterProvider = Provider<SyncConnectionTester>(
  (ref) => testSyncConnection,
);

final workspaceControllerFactoryProvider = Provider<WorkspaceControllerFactory>(
  (ref) => WorkspaceControllerFactory(
    workspaceRepository: ref.watch(workspaceRepositoryProvider),
    vaultRepository: ref.watch(vaultRepositoryProvider),
    syncRepository: ref.watch(syncRepositoryProvider),
    credentialStore: ref.watch(syncCredentialStoreProvider),
    syncServiceFactory: () => SyncCoordinator(
      repository: ref.read(syncRepositoryProvider),
      providerFactory: ref.read(syncProviderFactoryProvider),
      attachmentRepositoryFactory: ref.read(
        attachmentRepositoryFactoryProvider,
      ),
    ),
    attachmentRepositoryFactory: ref.watch(attachmentRepositoryFactoryProvider),
    rowLevelStoreBuilder: ref.watch(rowLevelStoreBuilderProvider),
    widgetDataService: ref.watch(widgetDataServiceProvider),
  ),
);
