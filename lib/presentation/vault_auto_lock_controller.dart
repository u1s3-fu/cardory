import 'dart:async';

import 'package:flutter/widgets.dart';

/// Flutter lifecycle adapter that locks an active vault in the background.
class VaultAutoLockController with WidgetsBindingObserver {
  VaultAutoLockController({required this.onLock});

  final FutureOr<void> Function() onLock;
  bool _locked = false;
  bool _enabled = true;

  void setEnabled(bool enabled) => _enabled = enabled;

  void start() => WidgetsBinding.instance.addObserver(this);

  void stop() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled ||
        _locked ||
        (state != AppLifecycleState.inactive &&
            state != AppLifecycleState.paused &&
            state != AppLifecycleState.detached)) {
      return;
    }
    _locked = true;
    unawaited(Future<void>.sync(onLock));
  }
}
