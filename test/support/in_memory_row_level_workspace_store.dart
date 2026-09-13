// RowLevelWorkspaceStore 的内存实现（仅测试用）。
//
// 直接复用 WorkspaceMutationService 的纯快照变换，把行级写入语义
// 投影到调用方提供的 CardoryData 读写器上；配合内存 CardoryRepository
// 驱动完整的 UI/控制器测试。

import 'package:cardory/application/row_level_workspace_store.dart';
import 'package:cardory/application/workspace_mutation_service.dart';
import 'package:cardory/domain/cardory_models.dart';

class InMemoryRowLevelWorkspaceStore implements RowLevelWorkspaceStore {
  InMemoryRowLevelWorkspaceStore(this._read, this._write);

  final CardoryData Function() _read;
  final void Function(CardoryData data) _write;
  static const _mutations = WorkspaceMutationService();

  /// 置为 true 时下一次写入抛错，用于模拟持久化失败。
  bool failNextWrite = false;

  Future<void> _commit(CardoryData data) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('row-level write failed');
    }
    _write(data);
  }

  @override
  Future<void> addProject(ProjectData project) =>
      _commit(_mutations.addProject(_read(), project));

  @override
  Future<void> updateProject(ProjectData original, ProjectData updated) =>
      _commit(_mutations.editProject(_read(), original, updated).data);

  @override
  Future<void> deleteProject(String projectId) =>
      _commit(_mutations.deleteProject(_read(), projectId).data);

  @override
  Future<void> reorderProjects(List<ProjectData> orderedProjects) =>
      _commit(_read().copyWith(projects: List.of(orderedProjects)));

  @override
  Future<void> addTodo(TodoData todo) =>
      _commit(_mutations.addTodo(_read(), todo));

  @override
  Future<void> updateTodo(TodoData original, TodoData updated) =>
      _commit(_mutations.updateTodo(_read(), updated));

  @override
  Future<void> deleteTodo(String todoId) =>
      _commit(_mutations.deleteTodo(_read(), todoId));

  @override
  Future<void> setTodoDone(String todoId, {required bool done}) {
    final todo = _read().todos.firstWhere((item) => item.id == todoId);
    return _commit(_mutations.updateTodo(_read(), todo.copyWith(done: done)));
  }

  @override
  Future<void> addSubTodo(TodoData todo, SubTodoData subTodo) => _commit(
    _mutations.updateTodo(
      _read(),
      todo.copyWith(subTodos: [...todo.subTodos, subTodo]),
    ),
  );

  @override
  Future<void> setSubTodoDone(String subTodoId, {required bool done}) {
    final todo = _read().todos.firstWhere(
      (item) => item.subTodos.any((sub) => sub.id == subTodoId),
    );
    final updated = todo.copyWith(
      subTodos: [
        for (final sub in todo.subTodos)
          if (sub.id == subTodoId) sub.copyWith(done: done) else sub,
      ],
    );
    return _commit(_mutations.updateTodo(_read(), updated));
  }

  @override
  Future<void> addAsset(AssetData asset) =>
      _commit(_read().copyWith(assets: [..._read().assets, asset]));

  @override
  Future<void> editAsset(AssetData original, AssetData updated) =>
      _commit(_mutations.editAsset(_read(), original, updated).data);

  @override
  Future<void> deleteAsset(String assetId) {
    final asset = _read().assets.firstWhere((item) => item.id == assetId);
    return _commit(_mutations.deleteAsset(_read(), asset));
  }

  @override
  Future<void> addAssetTag(AssetTag tag) =>
      _commit(_read().copyWith(assetTags: [..._read().assetTags, tag]));

  @override
  Future<void> updateAssetTag(AssetTag tag) => _commit(
    _read().copyWith(
      assetTags: [
        for (final item in _read().assetTags)
          if (item.id == tag.id) tag else item,
      ],
    ),
  );

  @override
  Future<void> deleteAssetTag(String tagId) => _commit(
    _read().copyWith(
      assetTags: _read().assetTags.where((item) => item.id != tagId).toList(),
      assets: _read().assets.map((asset) {
        if (!asset.tagIds.contains(tagId)) return asset;
        final remaining = asset.tagIds.where((id) => id != tagId).toList();
        return asset.copyWith(
          tagIds: remaining,
          clearTagIds: remaining.isEmpty,
        );
      }).toList(),
    ),
  );

  @override
  Future<void> updateAssetsTags(Set<String> assetIds, Set<String> tagIds) =>
      _commit(
        _read().copyWith(
          assets: _read().assets.map((asset) {
            if (!assetIds.contains(asset.id)) return asset;
            return asset.copyWith(
              tagIds: tagIds.toList(),
              clearTagIds: tagIds.isEmpty,
            );
          }).toList(),
        ),
      );
}
