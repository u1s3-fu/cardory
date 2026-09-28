// 资产到期提醒：平台通知服务契约 + 纯函数提醒规划。
//
// 保险库模型下锁外无数据，无法后台扫描加密库；策略为「解锁加载数据后
// 扫描 + 内容预计算预约系统通知」，锁后预约通知照常弹出。桌面端使用
// [NullDueReminderService] 空实现（无通知基础设施）。

import 'schedule_queries.dart';

/// 单条到期提醒载荷。
class DueReminderPayload {
  const DueReminderPayload({
    required this.id,
    required this.title,
    required this.body,
  });

  /// 稳定通知 id：同一（资产, 字段, 日期）重复规划时覆盖而非堆积。
  final int id;
  final String title;
  final String body;
}

/// 一条需要预约到未来某时刻的提醒。
class ScheduledDueReminder {
  const ScheduledDueReminder({required this.payload, required this.fireAt});

  final DueReminderPayload payload;
  final DateTime fireAt;
}

/// 一轮提醒扫描的执行计划。
class DueReminderPlan {
  const DueReminderPlan({
    required this.immediate,
    required this.scheduled,
    required this.nextState,
  });

  /// 立即弹出的通知（今日到期 / 已逾期未提醒）。
  final List<DueReminderPayload> immediate;

  /// 预约到到期日 09:00 的通知。
  final List<ScheduledDueReminder> scheduled;

  /// 已提醒状态的新值（per-device，持久化由服务实现负责）。
  final Set<String> nextState;
}

/// 资产到期提醒的平台能力边界。
abstract interface class DueReminderService {
  /// 请求通知权限；false 表示用户拒绝，调用方应跳过本轮提醒。
  Future<bool> ensurePermissions();

  /// 立即弹出通知。
  Future<void> notify(DueReminderPayload payload);

  /// 预约通知（到期日 09:00，inexact 闹钟，不申请精确闹钟权限）。
  Future<void> schedule(ScheduledDueReminder reminder);

  /// 取消全部通知（每轮扫描前重置，避免陈旧预约残留）。
  Future<void> cancelAll();

  /// 读取已提醒状态（key 由 [dueReminderKey] 生成）。
  Future<Set<String>> loadNotifiedKeys();

  /// 持久化已提醒状态。
  Future<void> saveNotifiedKeys(Set<String> keys);
}

/// 空实现：桌面端与测试未注入真实通知能力时使用。
class NullDueReminderService implements DueReminderService {
  const NullDueReminderService();

  @override
  Future<bool> ensurePermissions() async => false;

  @override
  Future<void> notify(DueReminderPayload payload) async {}

  @override
  Future<void> schedule(ScheduledDueReminder reminder) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<Set<String>> loadNotifiedKeys() async => {};

  @override
  Future<void> saveNotifiedKeys(Set<String> keys) async {}
}

/// 提醒去重键：仅对「立即弹出」的通知去重（预约通知每轮重发，
/// 到期当日被 cancelAll 后由当日提醒兜底，见 README 语义注释）。
String dueReminderKey(AssetDueEntry entry) {
  final day = entry.date.toIso8601String().substring(0, 10);
  return '${entry.assetId}|${entry.fieldKey}|$day';
}

/// 稳定通知 id：同一（资产, 字段, 日期）恒定，跨会话覆盖不堆积。
int dueReminderNotificationId(AssetDueEntry entry) =>
    Object.hash(
      'cardory-due',
      entry.assetId,
      entry.fieldKey,
      entry.date.toIso8601String().substring(0, 10),
    ) &
    0x7fffffff;

/// 依据到期条目生成提醒执行计划（纯函数，便于单测）。
///
/// - [overdue]：早于今日的到期条目；仅提醒未去重过的最近 [overdueCap] 条；
/// - [dueToday]：今日到期条目；未去重过的立即弹出；
/// - [upcoming]：今日之后、提前窗口内的条目；预约到到期日 09:00。
DueReminderPlan planDueReminders({
  required List<AssetDueEntry> overdue,
  required List<AssetDueEntry> dueToday,
  required List<AssetDueEntry> upcoming,
  required Set<String> notifiedKeys,
  int overdueCap = 5,
}) {
  final immediate = <DueReminderPayload>[];
  final shownKeys = <String>{};

  void addImmediate(AssetDueEntry entry, String body) {
    final key = dueReminderKey(entry);
    if (notifiedKeys.contains(key) || shownKeys.contains(key)) return;
    shownKeys.add(key);
    immediate.add(
      DueReminderPayload(
        id: dueReminderNotificationId(entry),
        title: entry.title,
        body: body,
      ),
    );
  }

  // 逾期条目按日期倒序（最近的逾期最紧急），限量防刷屏。
  final overdueDesc = [...overdue]..sort((a, b) => b.date.compareTo(a.date));
  for (final entry in overdueDesc.take(overdueCap)) {
    final days = entry.date.difference(DateTime.now()).inDays.abs();
    addImmediate(entry, '已逾期 $days 天，请尽快处理');
  }
  for (final entry in dueToday) {
    addImmediate(entry, '今天到期');
  }

  final scheduled = <ScheduledDueReminder>[
    for (final entry in upcoming)
      ScheduledDueReminder(
        payload: DueReminderPayload(
          id: dueReminderNotificationId(entry),
          title: entry.title,
          body: '将于 ${entry.date.toIso8601String().substring(0, 10)} 到期',
        ),
        fireAt: DateTime(entry.date.year, entry.date.month, entry.date.day, 9),
      ),
  ];

  // 已提醒状态剪枝：只保留仍出现在本轮扫描中的 key，防集合无限增长。
  final currentKeys = {
    for (final entry in [...overdue, ...dueToday, ...upcoming])
      dueReminderKey(entry),
  };
  final nextState = {...notifiedKeys.where(currentKeys.contains), ...shownKeys};
  return DueReminderPlan(
    immediate: immediate,
    scheduled: scheduled,
    nextState: nextState,
  );
}
