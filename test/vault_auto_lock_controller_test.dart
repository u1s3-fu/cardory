import 'package:cardory/application/vault_auto_lock_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('locks once when the application moves to the background', (
    tester,
  ) async {
    var locks = 0;
    final controller = VaultAutoLockController(onLock: () => locks++);
    controller.start();
    addTearDown(controller.stop);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();

    expect(locks, 1);
  });

  testWidgets('does not lock when automatic locking is disabled', (
    tester,
  ) async {
    var locks = 0;
    final controller = VaultAutoLockController(onLock: () => locks++)
      ..setEnabled(false)
      ..start();
    addTearDown(controller.stop);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(locks, 0);
  });
}
