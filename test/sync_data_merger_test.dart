// sync_data_merger 的冲突对比与合并单元测试。
//
// 重点回归：mergeSyncData 曾漏掉 assetTags 字段，
// 导致手动合并后用户全部资产标签被清空。

import 'package:cardory/domain/cardory_models.dart';
import 'package:cardory/sync/sync_data_merger.dart';
import 'package:cardory/sync/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';

ProjectData _project(String id, String title) => ProjectData(
  id: id,
  title: title,
  description: '',
  priority: ProjectPriority.p1,
  stage: ProjectStage.doing,
  progressEntries: const [],
);

TodoData _todo(String id, String title) => TodoData(
  id: id,
  title: title,
  projectId: '',
  projectTitle: '',
  priority: ProjectPriority.p1,
  done: false,
);

AssetData _asset(String id, String name, {List<String> tagIds = const []}) =>
    AssetData(id: id, type: AssetType.software, name: name, tagIds: tagIds);

void main() {
  group('mergeSyncData', () {
    test('未指定选择时保留本地并补齐远端独有条目', () {
      final local = CardoryData(
        projects: [_project('p-local', '本地项目')],
        todos: [_todo('t-local', '本地待办')],
        assets: [_asset('a-local', '本地资产')],
      );
      final remote = CardoryData(
        projects: [_project('p-remote', '远端项目')],
        todos: [_todo('t-remote', '远端待办')],
        assets: [_asset('a-remote', '远端资产')],
      );

      final merged = mergeSyncData(local, remote, const {});

      expect(
        merged.projects.map((item) => item.id),
        containsAll(['p-local', 'p-remote']),
      );
      expect(
        merged.todos.map((item) => item.id),
        containsAll(['t-local', 't-remote']),
      );
      expect(
        merged.assets.map((item) => item.id),
        containsAll(['a-local', 'a-remote']),
      );
    });

    test('选择远端时采用远端条目', () {
      final local = CardoryData(
        projects: [_project('p-1', '本地标题')],
        todos: const [],
      );
      final remote = CardoryData(
        projects: [_project('p-1', '远端标题')],
        todos: const [],
      );

      final merged = mergeSyncData(local, remote, {
        'p-1': SyncConflictSide.remote,
      });

      expect(merged.projects.single.title, '远端标题');
    });

    test('合并两侧资产标签为并集', () {
      final local = CardoryData(
        projects: const [],
        todos: const [],
        assetTags: const [AssetTag(id: 'tag-local', name: '本地标签')],
      );
      final remote = CardoryData(
        projects: const [],
        todos: const [],
        assetTags: const [AssetTag(id: 'tag-remote', name: '远端标签')],
      );

      final merged = mergeSyncData(local, remote, const {});

      expect(merged.assetTags.map((tag) => tag.id).toSet(), {
        'tag-local',
        'tag-remote',
      });
    });

    test('同名 id 标签冲突时保留本地定义', () {
      final local = CardoryData(
        projects: const [],
        todos: const [],
        assetTags: const [AssetTag(id: 'tag-1', name: '本地名称')],
      );
      final remote = CardoryData(
        projects: const [],
        todos: const [],
        assetTags: const [AssetTag(id: 'tag-1', name: '远端名称')],
      );

      final merged = mergeSyncData(local, remote, const {});

      expect(merged.assetTags.single.id, 'tag-1');
      expect(merged.assetTags.single.name, '本地名称');
    });
  });

  group('buildSyncConflictItems', () {
    test('列出内容不一致与单边存在的条目', () {
      final local = CardoryData(
        projects: [_project('p-same', '相同'), _project('p-changed', '本地改')],
        todos: [_todo('t-local-only', '仅本地待办')],
      );
      final remote = CardoryData(
        projects: [_project('p-same', '相同'), _project('p-changed', '远端改')],
        todos: [_todo('t-remote-only', '仅远端待办')],
      );

      final conflicts = buildSyncConflictItems(local, remote);

      final conflictIds = conflicts.map((item) => item.id).toSet();
      expect(conflictIds, contains('p-changed'));
      expect(conflictIds, contains('t-local-only'));
      expect(conflictIds, contains('t-remote-only'));
      expect(conflictIds, isNot(contains('p-same')));
      // 标签差异不产生冲突项，由合并阶段的并集策略兜底。
      expect(conflicts.map((item) => item.category), everyElement(isNot('标签')));
    });
  });
}
