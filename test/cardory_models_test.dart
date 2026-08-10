import 'package:cardory/domain/cardory_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings', () {
    test('defaults legacy settings to the standard reminder range', () {
      final settings = AppSettings.fromJson(const {});

      expect(settings.homeReminderPriorityThreshold, ProjectPriority.p2);
    });

    test('round-trips the home reminder priority threshold', () {
      const settings = AppSettings(
        homeReminderPriorityThreshold: ProjectPriority.p1,
        recordSubTodoCreatedAt: true,
      );

      expect(AppSettings.fromJson(settings.toJson()), settings);
    });

    test('migrates the legacy automatic reminder setting', () {
      final settings = AppSettings.fromJson(const {
        'autoSetSubTodoReminderTime': true,
      });

      expect(settings.recordSubTodoCreatedAt, isTrue);
      expect(settings.toJson(), isNot(contains('autoSetSubTodoReminderTime')));
    });
  });

  group('ProjectData', () {
    test('reads current progress entries', () {
      final project = ProjectData.fromJson({
        'id': 'current-project',
        'progressEntries': [
          {
            'id': 'current-entry',
            'note': '新格式记录',
            'progress': 0.4,
            'createdAt': '2026-07-29T00:00:00.000Z',
          },
        ],
      });

      expect(project.progressEntries, hasLength(1));
      expect(project.progressEntries.single.id, 'current-entry');
      expect(project.progress, 0.4);
      expect(project.toJson(), contains('progressEntries'));
    });

    test('clamps progress values to the supported range', () {
      expect(readProgress(-1), 0);
      expect(readProgress(2), 1);
      expect(readProgress(0.5), 0.5);
      expect(readProgress(null), 0);
    });
  });

  group('AssetData', () {
    test('round-trips software and hardware fields in CardoryData', () {
      const software = AssetData(
        id: 'software-1',
        type: AssetType.software,
        name: 'Nginx',
        projectId: 'project-1',
        version: '1.26',
        port: '443',
        path: '/etc/nginx',
        username: 'admin',
        password: 'secret',
        note: '生产入口',
      );
      const hardware = AssetData(
        id: 'hardware-1',
        type: AssetType.hardware,
        name: '主数据库服务器',
        serialNumber: 'SN-001',
        network: '10.0.0.10',
        serverType: '物理服务器',
        username: 'root',
        password: 'secret',
      );

      final restored = CardoryData.fromJson(
        CardoryData(
          projects: const [],
          todos: const [],
          assets: const [software, hardware],
        ).toJson(),
      );

      expect(restored.assets, hasLength(2));
      expect(restored.assets.first.path, '/etc/nginx');
      expect(restored.assets.first.projectId, 'project-1');
      expect(restored.assets.last.serialNumber, 'SN-001');
      expect(restored.assets.last.serverType, '物理服务器');
      expect(restored.assets.last.password, 'secret');
    });

    test('round-trips server types in settings', () {
      const settings = AppSettings(serverTypes: ['物理服务器', '虚拟机']);

      expect(AppSettings.fromJson(settings.toJson()), settings);
    });
  });

  group('SubTodoData', () {
    test('round-trips addition and reminder timestamps independently', () {
      final createdAt = DateTime(2026, 7, 31, 9, 15);
      final reminderAt = DateTime(2026, 8, 1, 10, 30);
      final subTodo = SubTodoData(
        id: createdAt.microsecondsSinceEpoch.toString(),
        content: '准备验收材料',
        done: false,
        createdAt: createdAt,
        dueAt: reminderAt,
      );

      final restored = SubTodoData.fromJson(subTodo.toJson());

      expect(restored.createdAt, createdAt);
      expect(restored.dueAt, reminderAt);
    });

    test('derives the addition timestamp from legacy generated ids', () {
      final createdAt = DateTime(2026, 7, 31, 9, 15);

      final restored = SubTodoData.fromJson({
        'id': createdAt.microsecondsSinceEpoch.toString(),
        'content': '旧子待办',
        'done': false,
      });

      expect(restored.createdAt, createdAt);
      expect(restored.dueAt, isNull);
    });
  });
}
