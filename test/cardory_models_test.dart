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

    test('defaults upload rename settings and round-trips them', () {
      const defaults = AppSettings();
      expect(defaults.renameAttachmentsOnUpload, isTrue);
      expect(defaults.keepAttachmentExtensionOnRename, isFalse);
      expect(
        AppSettings.fromJson(defaults.toJson()),
        defaults,
      );

      const customized = AppSettings(
        renameAttachmentsOnUpload: false,
        keepAttachmentExtensionOnRename: true,
      );
      expect(
        AppSettings.fromJson(customized.toJson()),
        customized,
      );
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

    test('round-trips project attachments with type and creation date', () {
      final data = CardoryData.fromJson({
        'projects': [
          {
            'id': 'project-attachments',
            'title': '项目附件',
            'description': '',
            'priority': 'p1',
            'stage': 'doing',
            'progressEntries': <Object?>[],
            'attachments': [
              {
                'id': 'attachment-image',
                'fileName': 'design.png',
                'storageKey': 'attachment-image.cardory-attachment',
                'encryptionKey': 'key',
                'size': 2048,
                'sha256': 'hash',
                'mimeType': 'image/png',
                'kind': 'image',
                'createdAt': '2026-08-20T04:30:00.000Z',
              },
            ],
          },
        ],
        'todos': <Object?>[],
        'assets': <Object?>[],
      });

      final projectJson =
          (data.toJson()['projects'] as List).single as Map<String, dynamic>;
      final attachmentJson =
          (projectJson['attachments'] as List).single as Map<String, dynamic>;

      expect(attachmentJson['kind'], 'image');
      expect(attachmentJson['createdAt'], '2026-08-20T04:30:00.000Z');
    });

    test('moves legacy asset attachments to their project', () {
      final data = CardoryData.fromJson({
        'projects': [
          {
            'id': 'project-legacy',
            'title': '旧项目',
            'description': '',
            'priority': 'p2',
            'stage': 'planned',
            'progressEntries': <Object?>[],
          },
        ],
        'todos': <Object?>[],
        'assets': [
          {
            'id': 'asset-legacy',
            'type': 'software',
            'name': '旧资产',
            'projectId': 'project-legacy',
            'attachments': [
              {
                'id': 'attachment-legacy',
                'fileName': 'manual.pdf',
                'createdAt': '2026-08-19T00:00:00.000Z',
              },
            ],
          },
        ],
      });

      final json = data.toJson();
      final projectJson =
          (json['projects'] as List).single as Map<String, dynamic>;
      final assetJson = (json['assets'] as List).single as Map<String, dynamic>;
      final attachmentJson =
          (projectJson['attachments'] as List).single as Map<String, dynamic>;

      expect(attachmentJson['id'], 'attachment-legacy');
      expect(attachmentJson['kind'], 'document');
      expect(assetJson, isNot(contains('attachments')));
    });

    test('round-trips attachment categories with custom names', () {
      final project = ProjectData.fromJson({
        'id': 'project-categories',
        'title': '分类项目',
        'description': '',
        'priority': 'p1',
        'stage': 'doing',
        'progressEntries': <Object?>[],
        'categories': [
          {'id': 'category-docs', 'name': '文档', 'createdAt': '2026-08-20T00:00:00.000Z'},
          {'id': 'category-assets', 'name': '素材'},
        ],
        'attachments': [
          {
            'id': 'attachment-categorized',
            'fileName': 'manual.pdf',
            'createdAt': '2026-08-20T01:00:00.000Z',
            'categoryIds': ['category-docs', 'category-assets'],
          },
        ],
      });

      final restored = ProjectData.fromJson(project.toJson());
      final json = restored.toJson();

      expect(restored.categories, hasLength(2));
      expect(restored.categories.first.name, '文档');
      expect(restored.categories.first.createdAt, DateTime(2026, 8, 20));
      expect(
        restored.attachments.single.categoryIds,
        containsAll(['category-docs', 'category-assets']),
      );
      expect(json, contains('categories'));
      expect(
        ((json['attachments'] as List).single as Map<String, dynamic>)['categoryIds'],
        containsAll(['category-docs', 'category-assets']),
      );
    });

    test('defaults missing categories to empty lists', () {
      final project = ProjectData.fromJson({
        'id': 'project-legacy-categories',
        'title': '旧项目',
        'description': '',
        'priority': 'p2',
        'stage': 'planned',
        'progressEntries': <Object?>[],
        'attachments': [
          {
            'id': 'attachment-no-category',
            'fileName': 'notes.txt',
            'createdAt': '2026-08-19T00:00:00.000Z',
          },
        ],
      });

      expect(project.categories, isEmpty);
      expect(project.attachments.single.categoryIds, isEmpty);
    });

    test('preserves orphaned legacy attachments in a recovery project', () {
      final data = CardoryData.fromJson({
        'projects': <Object?>[],
        'todos': <Object?>[],
        'assets': [
          {
            'id': 'asset-orphaned',
            'type': 'software',
            'name': '孤立资产',
            'projectId': '',
            'attachments': [
              {
                'id': 'attachment-orphaned',
                'fileName': 'evidence.txt',
                'createdAt': '2026-08-17T00:00:00.000Z',
              },
            ],
          },
        ],
      });

      final projects = data.toJson()['projects'] as List;
      final recoveryProject = projects.single as Map<String, dynamic>;
      final attachments = recoveryProject['attachments'] as List;

      expect(recoveryProject['title'], '待整理附件');
      expect(
        (attachments.single as Map<String, dynamic>)['id'],
        'attachment-orphaned',
      );
    });
  });

  group('AttachmentData', () {
    test('infers an explicit type for legacy attachment metadata', () {
      final attachment = AttachmentData.fromJson({
        'id': 'legacy-archive',
        'fileName': 'source.zip',
        'createdAt': '2026-08-18T00:00:00.000Z',
      });

      expect(attachment.toJson()['kind'], 'archive');
      expect(attachment.toJson()['createdAt'], '2026-08-18T00:00:00.000Z');
    });

    test('round-trips category ids through copyWith', () {
      final attachment = AttachmentData.fromJson({
        'id': 'attachment-copy-category',
        'fileName': 'report.docx',
        'createdAt': '2026-08-20T02:00:00.000Z',
        'categoryIds': ['category-a'],
      });

      final updated = attachment.copyWith(
        categoryIds: const ['category-b'],
      );
      final cleared = attachment.copyWith(
        categoryIds: const [],
        clearCategoryIds: true,
      );

      expect(updated.categoryIds, ['category-b']);
      expect(cleared.categoryIds, isEmpty);
      expect(
        AttachmentData.fromJson(updated.toJson()).categoryIds,
        ['category-b'],
      );
    });

    test('derives a stable creation date from legacy generated ids', () {
      final createdAt = DateTime(2026, 8, 16, 9, 45);

      final attachment = AttachmentData.fromJson({
        'id': createdAt.microsecondsSinceEpoch.toString(),
        'fileName': 'legacy.txt',
      });

      expect(attachment.createdAt, createdAt);
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

    test('round-trips asset tags and multi-tag assets', () {
      final restored = CardoryData.fromJson(
        CardoryData(
          projects: const [],
          todos: const [],
          assets: const [
            AssetData(
              id: 'asset-tagged',
              type: AssetType.hardware,
              name: 'DB 服务器',
              tagIds: ['tag-prod', 'tag-db'],
            ),
          ],
          assetTags: const [
            AssetTag(id: 'tag-prod', name: '生产环境'),
            AssetTag(id: 'tag-db', name: '数据库'),
          ],
        ).toJson(),
      );

      expect(restored.assetTags, hasLength(2));
      expect(restored.assetTags.first.name, '生产环境');
      expect(
        restored.assets.single.tagIds,
        containsAll(['tag-prod', 'tag-db']),
      );
      expect(
        AssetTag.fromJson(restored.assetTags.first.toJson()).name,
        '生产环境',
      );
    });

    test('defaults missing asset tags to empty lists', () {
      final restored = AssetData.fromJson({
        'id': 'asset-legacy',
        'type': 'software',
        'name': '旧资产',
      });

      expect(restored.tagIds, isEmpty);
    });

    test('clears asset tag ids through copyWith', () {
      const asset = AssetData(
        id: 'asset-clear-tags',
        type: AssetType.software,
        name: 'Nginx',
        tagIds: ['tag-web'],
      );

      final cleared = asset.copyWith(tagIds: const [], clearTagIds: true);

      expect(cleared.tagIds, isEmpty);
      expect(
        AssetData.fromJson(cleared.toJson()).tagIds,
        isEmpty,
      );
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
