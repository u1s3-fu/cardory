// 桌面端 .ics 系统日历服务测试：创建日程 → 读回 → 区间过滤。

import 'dart:io';

import 'package:cardory/services/system_calendar_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late DesktopIcsCalendarService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cardory-ics');
    service = DesktopIcsCalendarService(directoryProvider: () async => tempDir);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows 句柄延迟释放，尽力清理。
    }
  });

  test('创建日程生成 .ics 文件并可读回（含转义字符往返）', () async {
    final write = await service.createEvent(
      title: '评审会;重要,事项',
      start: DateTime(2026, 9, 14, 10, 30),
      end: DateTime(2026, 9, 14, 11, 0),
      note: '带\n换行的备注',
    );
    expect(write.success, isTrue);

    final files = tempDir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    expect(p.extension(files.single.path), '.ics');

    final events = await service.loadEvents(
      DateTime(2026, 9, 14),
      DateTime(2026, 9, 15),
    );
    expect(events, hasLength(1));
    expect(events.single.title, '评审会;重要,事项');
    expect(events.single.start, DateTime(2026, 9, 14, 10, 30));
    expect(events.single.end, DateTime(2026, 9, 14, 11, 0));
    expect(events.single.note, '带\n换行的备注');
  });

  test('loadEvents 按区间过滤并排序', () async {
    await service.createEvent(
      title: '早会',
      start: DateTime(2026, 9, 14, 8),
      end: DateTime(2026, 9, 14, 8, 30),
    );
    await service.createEvent(
      title: '晚会',
      start: DateTime(2026, 9, 16, 20),
      end: DateTime(2026, 9, 16, 21),
    );

    final week = await service.loadEvents(
      DateTime(2026, 9, 14),
      DateTime(2026, 9, 20),
    );
    expect(week.map((event) => event.title).toList(), ['早会', '晚会']);

    final singleDay = await service.loadEvents(
      DateTime(2026, 9, 16),
      DateTime(2026, 9, 16),
    );
    expect(singleDay.map((event) => event.title), ['晚会']);

    final outside = await service.loadEvents(
      DateTime(2026, 10, 1),
      DateTime(2026, 10, 7),
    );
    expect(outside, isEmpty);
  });

  test('损坏的 .ics 文件被跳过不影响其余读取', () async {
    await service.createEvent(
      title: '正常日程',
      start: DateTime(2026, 9, 14, 9),
      end: DateTime(2026, 9, 14, 9, 30),
    );
    File(p.join(tempDir.path, 'broken.ics')).writeAsStringSync('NOT-ICS');

    final events = await service.loadEvents(
      DateTime(2026, 9, 14),
      DateTime(2026, 9, 14),
    );
    expect(events.single.title, '正常日程');
  });
}
