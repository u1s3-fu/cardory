import '../domain/cardory_models.dart';

class WorkspaceDeleteResult {
  const WorkspaceDeleteResult({required this.data, required this.attachments});

  final CardoryData data;
  final List<AttachmentData> attachments;
}

class ProjectEditResult {
  const ProjectEditResult({
    required this.data,
    required this.removedAttachments,
    required this.addedAttachments,
  });

  final CardoryData data;
  final List<AttachmentData> removedAttachments;
  final List<AttachmentData> addedAttachments;
}

class AssetEditResult {
  const AssetEditResult({required this.data, required this.recorded});

  final CardoryData data;
  final AssetData recorded;
}

/// 纯粹的工作区状态变换。持久化与外部副作用保留在
/// [WorkspaceController] 中，使这些规则可独立测试。
class WorkspaceMutationService {
  const WorkspaceMutationService();

  CardoryData addProject(CardoryData data, ProjectData project) =>
      data.copyWith(projects: [...data.projects, project]);

  ProjectEditResult editProject(
    CardoryData data,
    ProjectData original,
    ProjectData updated,
  ) {
    final originalIds = original.attachments.map((item) => item.id).toSet();
    final updatedIds = updated.attachments.map((item) => item.id).toSet();
    return ProjectEditResult(
      data: data.copyWith(
        projects: data.projects
            .map((item) => item.id == updated.id ? updated : item)
            .toList(),
        todos: data.todos
            .map(
              (todo) => todo.projectId == updated.id
                  ? todo.copyWith(projectTitle: updated.title)
                  : todo,
            )
            .toList(),
      ),
      removedAttachments: original.attachments
          .where((item) => !updatedIds.contains(item.id))
          .toList(),
      addedAttachments: updated.attachments
          .where((item) => !originalIds.contains(item.id))
          .toList(),
    );
  }

  WorkspaceDeleteResult deleteProject(CardoryData data, String projectId) {
    return WorkspaceDeleteResult(
      data: data.copyWith(
        projects: data.projects
            .where((project) => project.id != projectId)
            .toList(),
        todos: data.todos.where((todo) => todo.projectId != projectId).toList(),
        assets: data.assets
            .where((asset) => asset.projectId != projectId)
            .toList(),
      ),
      attachments: data.projects
          .where((project) => project.id == projectId)
          .expand((project) => project.attachments)
          .toList(),
    );
  }

  CardoryData addTodo(CardoryData data, TodoData todo) =>
      data.copyWith(todos: [...data.todos, todo]);

  CardoryData updateTodo(CardoryData data, TodoData todo) => data.copyWith(
    todos: data.todos.map((item) => item.id == todo.id ? todo : item).toList(),
  );

  CardoryData deleteTodo(CardoryData data, String todoId) => data.copyWith(
    todos: data.todos.where((todo) => todo.id != todoId).toList(),
  );

  TodoData toggleTodo(TodoData todo) => todo.copyWith(done: !todo.done);

  TodoData toggleSubTodo(TodoData todo, SubTodoData subTodo) => todo.copyWith(
    subTodos: todo.subTodos
        .map(
          (item) =>
              item.id == subTodo.id ? item.copyWith(done: !item.done) : item,
        )
        .toList(),
  );

  AssetData recordNewAsset(AssetData asset) => asset.copyWith(
    activities: [
      AssetActivity(
        kind: AssetActivityKind.created,
        message: '创建资产',
        timestamp: DateTime.now(),
      ),
      ...asset.activities,
    ],
  );

  AssetEditResult editAsset(
    CardoryData data,
    AssetData original,
    AssetData updated,
  ) {
    final changed = _changedAssetFields(original, updated);
    final recorded = updated.copyWith(
      activities: [
        AssetActivity(
          kind: AssetActivityKind.updated,
          message: '更新${changed.join('、')}',
          timestamp: DateTime.now(),
        ),
        ...updated.activities,
      ],
    );
    return AssetEditResult(
      data: data.copyWith(
        assets: data.assets
            .map((item) => item.id == updated.id ? recorded : item)
            .toList(),
      ),
      recorded: recorded,
    );
  }

  CardoryData deleteAsset(CardoryData data, AssetData asset) => data.copyWith(
    assets: data.assets.where((item) => item.id != asset.id).toList(),
  );

  List<String> _changedAssetFields(AssetData original, AssetData updated) {
    final changed = <String>[];
    if (updated.name != original.name) changed.add('名称');
    if (updated.version != original.version) changed.add('版本');
    if (updated.port != original.port) changed.add('端口');
    if (updated.path != original.path) changed.add('路径');
    if (updated.serialNumber != original.serialNumber) changed.add('序列号');
    if (updated.network != original.network) changed.add('网络');
    if (updated.serverType != original.serverType) changed.add('服务器类型');
    if (updated.username != original.username) changed.add('账号');
    if (updated.password != original.password) changed.add('密码');
    if (updated.note != original.note) changed.add('备注');
    if (changed.isEmpty) changed.add('字段');
    return changed;
  }
}
