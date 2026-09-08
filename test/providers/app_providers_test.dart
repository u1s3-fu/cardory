import 'package:cardory/providers/app_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sqlcipher 保险库 provider 共享同一 Store 实例', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final store = container.read(sqlCipherVaultStoreProvider);

    expect(container.read(vaultRepositoryProvider), same(store));
    expect(container.read(workspaceRepositoryProvider), same(store));
    expect(container.read(syncRepositoryProvider), same(store));
    expect(container.read(vaultSessionRepositoryProvider), same(store));
  });

  test('稳定依赖 provider 缓存其工厂与占位实现', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(sqlCipherVaultStoreProvider).isOpen, isFalse);
    expect(
      container.read(syncCredentialStoreProvider),
      same(container.read(syncCredentialStoreProvider)),
    );
    expect(
      container.read(vaultCredentialStoreProvider),
      same(container.read(vaultCredentialStoreProvider)),
    );
    expect(
      container.read(syncProviderFactoryProvider),
      same(container.read(syncProviderFactoryProvider)),
    );
    expect(
      container.read(workspaceControllerFactoryProvider),
      same(container.read(workspaceControllerFactoryProvider)),
    );
  });
}
