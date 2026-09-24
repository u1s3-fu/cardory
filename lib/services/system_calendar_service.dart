// 系统日历集成服务。
//
// - 移动端（Android/iOS）：device_calendar 插件读写系统日历（需日历权限）；
// - 桌面端（Windows/macOS/Linux）：系统日历没有可用的编程接口，采用
//   .ics（iCalendar）文件落地方案——创建日程写入应用文档目录
//   `Cardory/calendar/` 下的 .ics 文件（可被 Outlook/Apple 日历等导入），
//   读取时解析该目录下所有 .ics（用户也可把系统日历导出的 .ics 放进来）。

import 'dart:convert';
import 'dart:io';

import 'package:device_calendar/device_calendar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;

/// 系统日历中的一条日程。
class SystemCalendarEvent {
  const SystemCalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.note = '',
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;
  final String note;

  bool get isAllDay =>
      start.hour == 0 &&
      start.minute == 0 &&
      !end.isBefore(start) &&
      end.difference(start).inHours >= 23;
}

/// 日程写入结果；[detail] 携带可展示的补充信息（如 .ics 文件路径）。
class SystemCalendarWriteResult {
  const SystemCalendarWriteResult({required this.success, this.detail = ''});

  final bool success;
  final String detail;
}

abstract interface class SystemCalendarService {
  /// 读取 [start, end] 区间内的系统日历日程。
  Future<List<SystemCalendarEvent>> loadEvents(DateTime start, DateTime end);

  /// 创建一条日程到系统日历。
  Future<SystemCalendarWriteResult> createEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    String note = '',
  });
}

/// 按平台选择实现：移动端走系统日历插件，桌面端走 .ics 文件。
SystemCalendarService createSystemCalendarService() {
  if (Platform.isAndroid || Platform.isIOS) {
    return MobileSystemCalendarService();
  }
  return DesktopIcsCalendarService();
}

/// 移动端实现：device_calendar 插件。
class MobileSystemCalendarService implements SystemCalendarService {
  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  Future<List<Calendar>> _calendars() async {
    var granted = (await _plugin.hasPermissions()).isSuccess;
    if (!granted) {
      granted = (await _plugin.requestPermissions()).isSuccess;
    }
    if (!granted) {
      throw const SystemCalendarPermissionException();
    }
    final result = await _plugin.retrieveCalendars();
    if (!result.isSuccess) return const [];
    return result.data?.toList() ?? const [];
  }

  @override
  Future<List<SystemCalendarEvent>> loadEvents(
    DateTime start,
    DateTime end,
  ) async {
    final calendars = await _calendars();
    final events = <SystemCalendarEvent>[];
    for (final calendar in calendars) {
      final calendarId = calendar.id;
      if (calendarId == null) continue;
      final result = await _plugin.retrieveEvents(
        calendarId,
        RetrieveEventsParams(startDate: start, endDate: end),
      );
      if (!result.isSuccess) continue;
      for (final event in result.data ?? const []) {
        final eventStart = event.start;
        final eventEnd = event.end;
        if (eventStart == null || eventEnd == null) continue;
        events.add(
          SystemCalendarEvent(
            id: event.eventId ?? '$calendarId-${events.length}',
            title: event.title ?? '（无标题日程）',
            start: eventStart,
            end: eventEnd,
            note: event.description ?? '',
          ),
        );
      }
    }
    events.sort((a, b) => a.start.compareTo(b.start));
    return events;
  }

  @override
  Future<SystemCalendarWriteResult> createEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    String note = '',
  }) async {
    final calendars = await _calendars();
    final writable = calendars
        .where((calendar) => calendar.isReadOnly != true)
        .toList();
    final calendar = writable.isEmpty ? null : writable.first;
    final calendarId = calendar?.id;
    if (calendarId == null) {
      return const SystemCalendarWriteResult(
        success: false,
        detail: '设备上没有可写的系统日历。',
      );
    }
    final result = await _plugin.createOrUpdateEvent(
      Event(
        calendarId,
        title: title,
        start: tz.TZDateTime.from(start, tz.local),
        end: tz.TZDateTime.from(end, tz.local),
        description: note,
      ),
    );
    if (result?.isSuccess ?? false) {
      return SystemCalendarWriteResult(
        success: true,
        detail: '已写入系统日历「${calendar?.name ?? ''}」。',
      );
    }
    return SystemCalendarWriteResult(
      success: false,
      detail: result?.errors.join('；') ?? '写入系统日历失败。',
    );
  }
}

/// 系统日历权限被拒绝。
class SystemCalendarPermissionException implements Exception {
  const SystemCalendarPermissionException();
}

/// 桌面端实现：.ics（iCalendar）文件。
class DesktopIcsCalendarService implements SystemCalendarService {
  DesktopIcsCalendarService({Future<Directory> Function()? directoryProvider})
    // ignore: prefer_initializing_formals
    : _directoryProvider = directoryProvider;

  static const _dirName = 'calendar';

  final Future<Directory> Function()? _directoryProvider;

  Future<Directory> _directory() async {
    if (_directoryProvider != null) return _directoryProvider();
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(documents.path, 'Cardory', _dirName));
    await dir.create(recursive: true);
    return dir;
  }

  String _formatUtc(DateTime value) {
    final u = value.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${u.year}${two(u.month)}${two(u.day)}'
        'T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  }

  String _escape(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\n', '\\n');

  String _unescape(String value) => value
      .replaceAll('\\n', '\n')
      .replaceAll('\\,', ',')
      .replaceAll('\\;', ';')
      .replaceAll('\\\\', '\\');

  String _icsFor(SystemCalendarEvent event) => [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Cardory//Calendar//CN',
    'BEGIN:VEVENT',
    'UID:${event.id}@cardory',
    'DTSTAMP:${_formatUtc(DateTime.now().toUtc())}',
    'DTSTART:${_formatUtc(event.start)}',
    'DTEND:${_formatUtc(event.end)}',
    'SUMMARY:${_escape(event.title)}',
    if (event.note.isNotEmpty) 'DESCRIPTION:${_escape(event.note)}',
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n');

  List<SystemCalendarEvent> _parseIcs(String text, String sourceName) {
    final events = <SystemCalendarEvent>[];
    String? uid;
    String? summary;
    String? description;
    DateTime? start;
    DateTime? end;
    DateTime? parseDate(String raw) {
      final value = raw.trim();
      final isDateOnly = value.length == 8;
      final normalized = value
          .replaceAll(RegExp(r'[-:]'), '')
          .split('T')
          .join('T');
      if (isDateOnly) {
        return DateTime(
          int.parse(normalized.substring(0, 4)),
          int.parse(normalized.substring(4, 6)),
          int.parse(normalized.substring(6, 8)),
        );
      }
      final utc = normalized.endsWith('Z');
      final body = utc
          ? normalized.substring(0, normalized.length - 1)
          : normalized;
      final parsed = DateTime(
        int.parse(body.substring(0, 4)),
        int.parse(body.substring(4, 6)),
        int.parse(body.substring(6, 8)),
        int.parse(body.substring(9, 11)),
        int.parse(body.substring(11, 13)),
        body.length >= 15 ? int.parse(body.substring(13, 15)) : 0,
      );
      return utc
          ? DateTime.utc(
              parsed.year,
              parsed.month,
              parsed.day,
              parsed.hour,
              parsed.minute,
              parsed.second,
            ).toLocal()
          : parsed;
    }

    void flush() {
      final localUid = uid;
      final localSummary = summary;
      final localStart = start;
      final localEnd = end;
      if (localUid != null &&
          localSummary != null &&
          localStart != null &&
          localEnd != null) {
        events.add(
          SystemCalendarEvent(
            id: localUid,
            title: localSummary,
            start: localStart,
            end: localEnd,
            note: description ?? '',
          ),
        );
      }
      uid = null;
      summary = null;
      description = null;
      start = null;
      end = null;
    }

    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trim();
      if (trimmed == 'BEGIN:VEVENT') continue;
      if (trimmed == 'END:VEVENT') {
        flush();
        continue;
      }
      final colon = trimmed.indexOf(':');
      if (colon <= 0) continue;
      final key = trimmed.substring(0, colon).toUpperCase();
      final value = trimmed.substring(colon + 1);
      if (key.startsWith('UID')) {
        uid = value;
      } else if (key.startsWith('SUMMARY')) {
        summary = _unescape(value);
      } else if (key.startsWith('DESCRIPTION')) {
        description = _unescape(value);
      } else if (key.startsWith('DTSTART')) {
        start = parseDate(value);
      } else if (key.startsWith('DTEND')) {
        end = parseDate(value);
      }
    }
    return events;
  }

  @override
  Future<List<SystemCalendarEvent>> loadEvents(
    DateTime start,
    DateTime end,
  ) async {
    final dir = await _directory();
    final events = <SystemCalendarEvent>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.ics')) {
        continue;
      }
      try {
        events.addAll(
          _parseIcs(await entity.readAsString(), p.basename(entity.path)),
        );
      } catch (_) {
        // 单个文件损坏不影响其余日程读取。
      }
    }
    // 日级区间语义：start/end 按日期分量取整，end 当天全天包含在内。
    final rangeStart = DateTime(start.year, start.month, start.day);
    final rangeEnd = DateTime(
      end.year,
      end.month,
      end.day,
    ).add(const Duration(days: 1));
    return events
        .where(
          (event) =>
              event.end.isAfter(rangeStart) && event.start.isBefore(rangeEnd),
        )
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  @override
  Future<SystemCalendarWriteResult> createEvent({
    required String title,
    required DateTime start,
    required DateTime end,
    String note = '',
  }) async {
    final dir = await _directory();
    final id = 'cardory-${DateTime.now().microsecondsSinceEpoch}';
    final file = File(p.join(dir.path, '$id.ics'));
    await file.writeAsString(
      _icsFor(
        SystemCalendarEvent(
          id: id,
          title: title,
          start: start,
          end: end,
          note: note,
        ),
      ),
      flush: true,
    );
    return SystemCalendarWriteResult(
      success: true,
      detail: '已导出 .ics 日程文件：${file.path}（可导入系统日历）。',
    );
  }
}
