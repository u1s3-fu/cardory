// 业务领域枚举：项目阶段与优先级。

/// 项目阶段。
enum ProjectStage {
  planned('计划中'),
  doing('进行中'),
  done('已结束');

  const ProjectStage(this.label);

  final String label;

  /// 按持久化名称还原阶段。
  ///
  /// 存量兼容：已删除的 review（待验收）归入 done——该阶段的语义是活已做完、
  /// 等待确认，最贴近「已结束」。数据库与备份 JSON 里仍可能存在旧名称，
  /// 经此别名读取，无需数据迁移。
  static ProjectStage fromName(String name) {
    const legacyNames = <String, String>{'review': 'done'};
    return ProjectStage.values.firstWhere(
      (item) => item.name == (legacyNames[name] ?? name),
      orElse: () => ProjectStage.planned,
    );
  }
}

/// 项目/待办优先级。
///
/// 枚举名刻意保留旧四级的 p0 / p2 / p3（跳过 p1）：名称即持久化契约，
/// 复用旧名可让存量数据零迁移生效——只有被删除的 p1（中）需要别名。
/// 若改用连续的 p0 / p1 / p2，旧「普通」(p2) 与新「低」(p2) 将同名不同义，
/// 读取时无法区分新旧数据，造成静默的数据损坏。
enum ProjectPriority {
  p0('高'),
  p2('普通'),
  p3('低');

  const ProjectPriority(this.label);

  final String label;

  /// 按持久化名称还原优先级。
  ///
  /// 存量兼容：旧四级的 p1（中）并入 p2（普通）；p0 / p2 / p3 名称与含义
  /// 均未变，原样命中。
  static ProjectPriority fromName(String name) {
    const legacyNames = <String, String>{'p1': 'p2'};
    return ProjectPriority.values.firstWhere(
      (item) => item.name == (legacyNames[name] ?? name),
      orElse: () => ProjectPriority.p2,
    );
  }
}
