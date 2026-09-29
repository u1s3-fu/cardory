// 系统日历回收对账：把推送登记表与当前资产到期条目比对，产出回收计划。
//
// 策略（回收 + 跟随更新）：
// - 登记条目的资产/到期字段已不存在（资产删除、字段删除、取消提醒）→ 删除事件；
// - 仍存在但到期日或标题（资产名/字段标签）变更 → 删旧事件 + 按新内容新建；
// - 一致 → 保留；从未推送的到期条目 → 不动（推送保持用户手动触发）。

import 'calendar_push_registry.dart';
import 'schedule_queries.dart';

/// 一轮对账的执行计划。
class CalendarSyncPlan {
  const CalendarSyncPlan({
    required this.eventIdsToDelete,
    required this.replacements,
    required this.nextRegistry,
  });

  /// 需要删除的系统日历事件 id（资产/字段失效）。
  final List<String> eventIdsToDelete;

  /// 需要删旧建新的替换项（到期日/标题变更）。
  final List<CalendarReplacement> replacements;

  /// 对账后的登记表新值。
  final Map<String, CalendarPushRecord> nextRegistry;
}

/// 一次「删旧 + 按新内容重建」的替换；[key] 为原登记表键，
/// 删除失败时调用方据此恢复原登记。
class CalendarReplacement {
  const CalendarReplacement({
    required this.key,
    required this.oldEventId,
    required this.due,
  });

  final String key;
  final String oldEventId;
  final AssetDueEntry due;
}

/// 依据登记表与当前到期条目生成回收计划（纯函数，便于单测）。
///
/// [currentDues] 为全量资产到期条目（不限区间，见 [assetDueEntries]）。
CalendarSyncPlan planCalendarSync({
  required Map<String, CalendarPushRecord> registry,
  required List<AssetDueEntry> currentDues,
}) {
  final currentByKey = <String, AssetDueEntry>{
    for (final due in currentDues)
      calendarPushRegistryKey(due.assetId, due.fieldKey): due,
  };

  final eventIdsToDelete = <String>[];
  final replacements = <CalendarReplacement>[];
  final nextRegistry = <String, CalendarPushRecord>{};

  registry.forEach((key, record) {
    final due = currentByKey[key];
    if (due == null) {
      // 资产删除 / 字段删除 / 取消提醒：回收事件。
      eventIdsToDelete.add(record.eventId);
      return;
    }
    final day = due.date.toIso8601String().substring(0, 10);
    if (record.date == day && record.title == due.title) {
      // 未变化：保留登记。
      nextRegistry[key] = record;
      return;
    }
    // 到期日或标题变更：删旧建新。
    replacements.add(
      CalendarReplacement(key: key, oldEventId: record.eventId, due: due),
    );
  });

  return CalendarSyncPlan(
    eventIdsToDelete: eventIdsToDelete,
    replacements: replacements,
    nextRegistry: nextRegistry,
  );
}
