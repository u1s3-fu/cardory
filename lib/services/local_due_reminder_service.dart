// 移动端资产到期提醒服务：flutter_local_notifications + shared_preferences。
//
// - 通知渠道固定 `cardory-due-reminders`；
// - 预约使用 inexact 闹钟（AndroidScheduleMode.inexactAllowWhileIdle），
//   不申请 SCHEDULE_EXACT_ALARM，尊重系统省电策略；
// - 已提醒状态持久化在应用 SharedPreferences（per-device，不进同步配置）。

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/due_reminder_service.dart';

class LocalDueReminderService implements DueReminderService {
  LocalDueReminderService();

  static const _channelDetails = AndroidNotificationDetails(
    'cardory-due-reminders',
    '资产到期提醒',
    channelDescription: '资产（域名/证书等）到期日提醒',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );
  static const _notifiedKeysStoreKey = 'due_reminder_notified_keys_v1';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    try {
      tzdata.initializeTimeZones();
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
    } catch (error) {
      // 时区初始化失败时 tz.local 回退 UTC，预约时间可能有偏差但不崩溃。
      debugPrint('LocalDueReminderService timezone init failed: $error');
    }
    _initialized = true;
  }

  NotificationDetails get _details =>
      const NotificationDetails(android: _channelDetails);

  @override
  Future<bool> ensurePermissions() async {
    await _ensureInitialized();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    return await android.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> notify(DueReminderPayload payload) async {
    await _plugin.show(payload.id, payload.title, payload.body, _details);
  }

  @override
  Future<void> schedule(ScheduledDueReminder reminder) async {
    final fireAt = reminder.fireAt;
    if (fireAt.isBefore(DateTime.now())) return;
    await _plugin.zonedSchedule(
      reminder.payload.id,
      reminder.payload.title,
      reminder.payload.body,
      tz.TZDateTime.from(fireAt, tz.local),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  @override
  Future<void> cancelAll() async {
    await _ensureInitialized();
    await _plugin.cancelAll();
  }

  @override
  Future<Set<String>> loadNotifiedKeys() async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList(_notifiedKeysStoreKey) ?? const [])
        .toSet();
  }

  @override
  Future<void> saveNotifiedKeys(Set<String> keys) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_notifiedKeysStoreKey, keys.toList());
  }
}
