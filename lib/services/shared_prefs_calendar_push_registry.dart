// shared_preferences 实现的日历推送登记表。

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/calendar_push_registry.dart';

class SharedPrefsCalendarPushRegistry implements CalendarPushRegistry {
  SharedPrefsCalendarPushRegistry();

  static const _storeKey = 'calendar_push_registry_v1';

  @override
  Future<Map<String, CalendarPushRecord>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storeKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final entry in decoded.entries)
          if (entry.value is Map<String, dynamic>)
            entry.key: CalendarPushRecord.fromJson(
              entry.value as Map<String, dynamic>,
            ),
      };
    } catch (_) {
      // 登记数据损坏时按空表处理（最坏情况：孤儿日程不被回收）。
      return {};
    }
  }

  @override
  Future<void> save(Map<String, CalendarPushRecord> entries) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storeKey,
      jsonEncode({
        for (final entry in entries.entries) entry.key: entry.value.toJson(),
      }),
    );
  }
}
