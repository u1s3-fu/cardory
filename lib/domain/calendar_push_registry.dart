// 资产到期条目推送系统日历的登记表（per-device）。
//
// 记录「已写入系统日历」的到期条目与其事件 id，供删除资产 / 修改到期日
// 时回收或更新对应系统日程。系统日历与本机相关，登记表存本机
// （shared_preferences），不进入跨设备同步通道。

/// 一条已推送登记：事件 id + 推送时的到期日与标题（用于变更比对）。
class CalendarPushRecord {
  const CalendarPushRecord({
    required this.eventId,
    required this.date,
    required this.title,
  });

  /// 系统日历事件 id（[SystemCalendarService.createEvent] 返回）。
  final String eventId;

  /// 推送时的到期日（本地日期 ISO 串，yyyy-MM-dd）。
  final String date;

  /// 推送时的事件标题（`{字段标签} · {资产名}`）。
  final String title;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'eventId': eventId,
    'date': date,
    'title': title,
  };

  factory CalendarPushRecord.fromJson(Map<String, dynamic> json) =>
      CalendarPushRecord(
        eventId: json['eventId'] as String? ?? '',
        date: json['date'] as String? ?? '',
        title: json['title'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is CalendarPushRecord &&
      other.eventId == eventId &&
      other.date == date &&
      other.title == title;

  @override
  int get hashCode => Object.hash(eventId, date, title);
}

/// 登记表存储边界；key 为 `assetId|fieldKey`。
abstract interface class CalendarPushRegistry {
  Future<Map<String, CalendarPushRecord>> load();

  Future<void> save(Map<String, CalendarPushRecord> entries);
}

/// 登记表 key：资产 id + 到期字段 key。
String calendarPushRegistryKey(String assetId, String fieldKey) =>
    '$assetId|$fieldKey';
