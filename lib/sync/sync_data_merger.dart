// 同步数据的对比与合并工具。

import 'dart:convert';

import '../domain/cardory_models.dart';
import 'sync_models.dart';

/// 对比本地与远端数据，生成冲突项列表。
///
/// 逐类（项目 / 待办 / 资产）按 id 对比，仅列出内容不一致或单边存在的条目。
List<SyncConflictItem> buildSyncConflictItems(
  CardoryData local,
  CardoryData remote,
) {
  final result = <SyncConflictItem>[];
  void compare(
    String category,
    List<Map<String, dynamic>> localItems,
    List<Map<String, dynamic>> remoteItems,
  ) {
    final localById = {for (final item in localItems) '${item['id']}': item};
    final remoteById = {for (final item in remoteItems) '${item['id']}': item};
    for (final id in {...localById.keys, ...remoteById.keys}) {
      if (jsonEncode(localById[id]) != jsonEncode(remoteById[id])) {
        final item = localById[id] ?? remoteById[id]!;
        result.add(
          SyncConflictItem(
            id: id,
            category: category,
            title: '${item['title'] ?? item['fileName'] ?? id}',
            side: localById.containsKey(id)
                ? SyncConflictSide.local
                : SyncConflictSide.remote,
          ),
        );
      }
    }
  }

  compare(
    '项目',
    local.projects.map((item) => item.toJson()).toList(),
    remote.projects.map((item) => item.toJson()).toList(),
  );
  compare(
    '待办',
    local.todos.map((item) => item.toJson()).toList(),
    remote.todos.map((item) => item.toJson()).toList(),
  );
  compare(
    '资产',
    local.assets.map((item) => item.toJson()).toList(),
    remote.assets.map((item) => item.toJson()).toList(),
  );
  return result;
}

/// 按选择合并本地与远端数据。
///
/// [choices] 为冲突项的 id → 来源 映射；未指定或选择本地时优先保留本地数据。
CardoryData mergeSyncData(
  CardoryData local,
  CardoryData remote,
  Map<String, SyncConflictSide> choices,
) {
  List<T> merge<T>(
    List<T> localItems,
    List<T> remoteItems,
    Map<String, dynamic> Function(T) toJson,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final localById = {
      for (final item in localItems) '${toJson(item)['id']}': item,
    };
    final remoteById = {
      for (final item in remoteItems) '${toJson(item)['id']}': item,
    };
    return [
      for (final id in {...localById.keys, ...remoteById.keys})
        (choices[id] == SyncConflictSide.remote
            ? remoteById[id]
            : localById[id] ?? remoteById[id]) as T,
    ];
  }

  return CardoryData(
    projects: merge(
      local.projects,
      remote.projects,
      (item) => item.toJson(),
      ProjectData.fromJson,
    ),
    todos: merge(
      local.todos,
      remote.todos,
      (item) => item.toJson(),
      TodoData.fromJson,
    ),
    assets: merge(
      local.assets,
      remote.assets,
      (item) => item.toJson(),
      AssetData.fromJson,
    ),
  );
}
