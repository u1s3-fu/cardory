// 资产到期提醒测试：提醒规划纯函数 + AppSettings 提醒字段序列化。

import 'package:cardory/domain/app_settings.dart';
import 'package:cardory/domain/due_reminder_service.dart';
import 'package:cardory/domain/schedule_queries.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _day(int offset) {
  final now = DateTime.now();
  final base = DateTime(now.year, now.month, now.day);
  return base.add(Duration(days: offset));
}

AssetDueEntry _entry(String id, DateTime date, {String key = 'expireDate'}) =>
    AssetDueEntry(
      assetId: id,
      assetName: '资产-$id',
      date: date,
      fieldLabel: '注册到期',
      fieldKey: key,
      title: '注册到期 · 资产-$id',
    );

void main() {
  group('planDueReminders', () {
    test('逾期条目按紧迫度倒序提醒且限量，去重键生效', () {
      final overdue = [_entry('old', _day(-5)), _entry('new', _day(-1))];
      final plan = planDueReminders(
        overdue: overdue,
        dueToday: const [],
        upcoming: const [],
        notifiedKeys: const {},
      );

      expect(plan.immediate.length, 2);
      // 倒序：最近逾期的在前。
      expect(plan.immediate.first.title, '注册到期 · 资产-new');
      expect(plan.immediate.first.body, contains('已逾期 1 天'));
      expect(plan.immediate.last.body, contains('已逾期 5 天'));
    });

    test('逾期超过上限只提醒最近的几条', () {
      final overdue = [
        _entry('a', _day(-9)),
        _entry('b', _day(-8)),
        _entry('c', _day(-7)),
        _entry('d', _day(-6)),
        _entry('e', _day(-5)),
        _entry('f', _day(-4)),
      ];
      final plan = planDueReminders(
        overdue: overdue,
        dueToday: const [],
        upcoming: const [],
        notifiedKeys: const {},
      );
      expect(plan.immediate.length, 5);
      expect(plan.immediate.map((p) => p.title), isNot(contains('资产-a')));
    });

    test('今日到期立即提醒；未来条目预约到到期日 09:00', () {
      final plan = planDueReminders(
        overdue: const [],
        dueToday: [_entry('today', _day(0))],
        upcoming: [_entry('future', _day(7))],
        notifiedKeys: const {},
      );

      expect(plan.immediate.length, 1);
      expect(plan.immediate.single.body, '今天到期');
      expect(plan.scheduled.length, 1);
      final fire = plan.scheduled.single.fireAt;
      final due = _day(7);
      expect(
        DateTime(fire.year, fire.month, fire.day, fire.hour),
        DateTime(due.year, due.month, due.day, 9),
      );
      // 通知 id 稳定：同一（资产, 字段, 日期）两次规划一致。
      expect(
        plan.scheduled.single.payload.id,
        dueReminderNotificationId(_entry('future', _day(7))),
      );
    });

    test('已提醒过的条目不再立即弹出，状态经剪枝保留仍存在的 key', () {
      final staleKey = dueReminderKey(_entry('gone', _day(-2)));
      final keptKey = dueReminderKey(_entry('still', _day(-1)));
      final todayKey = dueReminderKey(_entry('today', _day(0)));

      final plan = planDueReminders(
        overdue: [_entry('still', _day(-1))],
        dueToday: [_entry('today', _day(0))],
        upcoming: const [],
        notifiedKeys: {staleKey, keptKey},
      );

      // still 已提醒过、today 未提醒过。
      expect(plan.immediate.single.title, '注册到期 · 资产-today');
      // 剪枝：已消失条目的 key 被移除，新增 key 并入。
      expect(plan.nextState.contains(staleKey), isFalse);
      expect(plan.nextState.contains(keptKey), isTrue);
      expect(plan.nextState.contains(todayKey), isTrue);
    });

    test('通知 id 对不同条目唯一稳定（截断为 int32 正数）', () {
      final first = dueReminderNotificationId(_entry('x', _day(1)));
      final second = dueReminderNotificationId(
        _entry('x', _day(1), key: 'sslExpire'),
      );
      expect(first, isNonNegative);
      expect(first, lessThan(0x7fffffff));
      expect(first, isNot(second));
    });
  });

  group('AppSettings 提醒字段', () {
    test('默认开启、默认提前 7 天；序列化往返一致', () {
      const defaults = AppSettings();
      expect(defaults.dueRemindersEnabled, isTrue);
      expect(defaults.dueReminderLeadDays, 7);

      const settings = AppSettings(
        dueRemindersEnabled: false,
        dueReminderLeadDays: 14,
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.dueRemindersEnabled, isFalse);
      expect(restored.dueReminderLeadDays, 14);
      expect(restored, settings);
    });

    test('提醒字段进入同步配置子集并在应用后保留', () {
      const settings = AppSettings(
        dueRemindersEnabled: false,
        dueReminderLeadDays: 3,
      );
      final applied = AppSettings().applySyncConfig(
        settings.toSyncConfigJson(),
      );
      expect(applied.dueRemindersEnabled, isFalse);
      expect(applied.dueReminderLeadDays, 3);
    });
  });
}
