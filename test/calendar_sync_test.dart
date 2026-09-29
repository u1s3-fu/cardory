// 系统日历回收对账测试：失效删除、变更替换、未推送不动、登记保留。

import 'package:cardory/domain/calendar_push_registry.dart';
import 'package:cardory/domain/calendar_sync.dart';
import 'package:cardory/domain/schedule_queries.dart';
import 'package:flutter_test/flutter_test.dart';

AssetDueEntry _due(
  String assetId,
  String fieldKey,
  DateTime date, {
  String fieldLabel = '注册到期',
  String assetName = 'example.com',
}) => AssetDueEntry(
  assetId: assetId,
  assetName: assetName,
  date: date,
  fieldLabel: fieldLabel,
  fieldKey: fieldKey,
  title: '$fieldLabel · $assetName',
);

CalendarPushRecord _record(String eventId, DateTime date, String title) =>
    CalendarPushRecord(
      eventId: eventId,
      date: date.toIso8601String().substring(0, 10),
      title: title,
    );

void main() {
  final day = DateTime(2026, 9, 10);

  test('资产/字段失效：事件进入删除清单并移出登记', () {
    final plan = planCalendarSync(
      registry: {
        calendarPushRegistryKey('asset-1', 'expire'): _record(
          'evt-1',
          day,
          '注册到期 · example.com',
        ),
      },
      currentDues: const [],
    );

    expect(plan.eventIdsToDelete, ['evt-1']);
    expect(plan.replacements, isEmpty);
    expect(plan.nextRegistry, isEmpty);
  });

  test('到期日或标题变更：删旧建新，新内容写入登记', () {
    final newDay = DateTime(2026, 10, 20);
    final plan = planCalendarSync(
      registry: {
        calendarPushRegistryKey('asset-1', 'expire'): _record(
          'evt-1',
          day,
          '注册到期 · example.com',
        ),
      },
      currentDues: [_due('asset-1', 'expire', newDay)],
    );

    expect(plan.eventIdsToDelete, isEmpty);
    expect(plan.replacements, hasLength(1));
    expect(plan.replacements.single.oldEventId, 'evt-1');
    expect(
      plan.replacements.single.key,
      calendarPushRegistryKey('asset-1', 'expire'),
    );
    expect(plan.replacements.single.due.date, newDay);
    // 替换成功前登记暂不含该键，由控制器在新建成功后写入。
    expect(plan.nextRegistry, isEmpty);
  });

  test('仅标题变更（资产改名/字段改名）也触发替换', () {
    final plan = planCalendarSync(
      registry: {
        calendarPushRegistryKey('asset-1', 'expire'): _record(
          'evt-1',
          day,
          '注册到期 · example.com',
        ),
      },
      currentDues: [_due('asset-1', 'expire', day, assetName: 'renamed.com')],
    );

    expect(plan.replacements, hasLength(1));
    expect(plan.replacements.single.due.title, '注册到期 · renamed.com');
  });

  test('一致条目保留登记；从未推送的到期条目不受影响', () {
    final registry = {
      calendarPushRegistryKey('asset-1', 'expire'): _record(
        'evt-1',
        day,
        '注册到期 · example.com',
      ),
    };
    final plan = planCalendarSync(
      registry: registry,
      currentDues: [
        _due('asset-1', 'expire', day),
        _due('asset-2', 'sslExpire', DateTime(2026, 11, 1)),
      ],
    );

    expect(plan.eventIdsToDelete, isEmpty);
    expect(plan.replacements, isEmpty);
    expect(plan.nextRegistry.keys, [
      calendarPushRegistryKey('asset-1', 'expire'),
    ]);
    expect(plan.nextRegistry.values.single.eventId, 'evt-1');
  });
}
