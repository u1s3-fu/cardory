// Windows 桌面到期/截止提醒服务（local_notifier 系统通知实现）。
//
// 语义与移动端 LocalDueReminderService 对齐：立即通知 + 预约通知 +
// 已提醒去重（shared_preferences）。预约通知用进程内 Timer 承载——
// 应用退出即消失，重启后由解锁加载重新扫描重发（与移动端 cancelAll-
// 重发语义一致，属预期）。

import 'dart:async';
import 'dart:convert';

import 'package:local_notifier/local_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/due_reminder_service.dart';

class WindowsDueReminderService implements DueReminderService {
  WindowsDueReminderService();

  static const _storeKey = 'cardory_due_notified_keys_v1';

  final _timers = <int, Timer>{};
  bool _initialized = false;
  bool _available = true;

  Future<void> _ensureInitialized() async {
    if (_initialized || !_available) return;
    _initialized = true;
    try {
      await localNotifier.setup(appName: 'Cardory');
    } catch (_) {
      // 初始化失败（如系统不支持 toast）：静默降级为无通知。
      _available = false;
      _timers.clear();
    }
  }

  Future<void> _show(DueReminderPayload payload) async {
    await _ensureInitialized();
    if (!_available) return;
    try {
      final notification = LocalNotification(
        title: payload.title,
        body: payload.body,
      );
      await notification.show();
    } catch (_) {
      // 单条通知失败不影响其余提醒。
    }
  }

  @override
  Future<bool> ensurePermissions() async {
    // Windows toast 通知无需运行时权限申请；初始化失败视为不可用。
    await _ensureInitialized();
    return _available;
  }

  @override
  Future<void> notify(DueReminderPayload payload) => _show(payload);

  @override
  Future<void> schedule(ScheduledDueReminder reminder) async {
    await _ensureInitialized();
    if (!_available) return;
    final delay = reminder.fireAt.difference(DateTime.now());
    if (delay <= Duration.zero) {
      await _show(reminder.payload);
      return;
    }
    // 已存在的同 id 预约先取消（每轮扫描全量重排前的兜底去重）。
    _timers.remove(reminder.payload.id)?.cancel();
    _timers[reminder.payload.id] = Timer(delay, () {
      _timers.remove(reminder.payload.id);
      _show(reminder.payload);
    });
  }

  @override
  Future<void> cancelAll() async {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }

  @override
  Future<Set<String>> loadNotifiedKeys() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storeKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<String>().toSet();
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> saveNotifiedKeys(Set<String> keys) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storeKey, jsonEncode(keys.toList()));
  }
}
