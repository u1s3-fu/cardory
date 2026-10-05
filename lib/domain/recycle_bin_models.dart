// 回收站的领域模型：软删除（tombstone）条目的只读视图与恢复入口。
//
// 约束：回收站只覆盖用户可从界面主动删除的四类主实体（项目/待办/资产/
// 里程碑）。附件、计时、番茄钟、依赖等从属数据随宿主删除一并 tombstone，
// 附件文件更是删除时即被物理清除，均不在回收站列出或恢复。

/// 回收站条目类型。
enum RecycleBinEntityType { project, task, asset, milestone }

/// 回收站中的一条软删除记录。
class RecycleBinEntry {
  const RecycleBinEntry({
    required this.type,
    required this.id,
    required this.title,
    required this.deletedAt,
    this.subtitle = '',
  });

  final RecycleBinEntityType type;
  final String id;

  /// 展示标题：项目名 / 待办标题 / 资产名 / 里程碑名。
  final String title;

  /// 补充说明，如「子待办」「曾属于项目 X」（尽力而为，可能为空）。
  final String subtitle;

  /// 软删除时间（UTC）。
  final DateTime deletedAt;
}
