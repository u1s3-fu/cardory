// 工作区写入口的行级存储契约。
//
// 界面与 [WorkspaceController] 通过本接口写入业务数据，不再构建整包
// CardoryData 快照：生产实现由 drift Repository 提供（每个实体行的
// updatedAt/tombstone 与 sync_changes 在同一事务内提交）；
// 测试可提供内存实现。

import '../domain/cardory_models.dart';

/// 每次调用返回当前会话的行级存储；保险库未解锁时返回 null。
typedef RowLevelWorkspaceStoreBuilder = RowLevelWorkspaceStore? Function();

abstract interface class RowLevelWorkspaceStore {
  // 项目。

  Future<void> addProject(ProjectData project);

  /// 按 (original → updated) 的差异更新项目行，并同步进度记录、
  /// 附件元数据与附件分类的增删改。
  Future<void> updateProject(ProjectData original, ProjectData updated);

  Future<void> deleteProject(String projectId);

  /// 看板拖拽排序：按 [orderedProjects] 的顺序写入阶段与 sortOrder，
  /// 列表未覆盖的行保持原相对顺序追加在后。
  Future<void> reorderProjects(List<ProjectData> orderedProjects);

  // 待办与子待办。

  Future<void> addTodo(TodoData todo);
  Future<void> updateTodo(TodoData original, TodoData updated);
  Future<void> deleteTodo(String todoId);
  Future<void> setTodoDone(String todoId, {required bool done});
  Future<void> addSubTodo(TodoData todo, SubTodoData subTodo);
  Future<void> setSubTodoDone(String subTodoId, {required bool done});

  // 资产与标签。

  Future<void> addAsset(AssetData asset);
  Future<void> editAsset(AssetData original, AssetData updated);
  Future<void> deleteAsset(String assetId);
  Future<void> addAssetTag(AssetTag tag);
  Future<void> updateAssetTag(AssetTag tag);
  Future<void> deleteAssetTag(String tagId);
  Future<void> updateAssetsTags(Set<String> assetIds, Set<String> tagIds);
}
