// 业务领域枚举：项目阶段与优先级。

/// 项目阶段。
enum ProjectStage {
  planned('计划中'),
  doing('进行中'),
  review('待验收'),
  done('已完成');

  const ProjectStage(this.label);

  final String label;

  static ProjectStage fromName(String name) => ProjectStage.values.firstWhere(
    (item) => item.name == name,
    orElse: () => ProjectStage.planned,
  );
}

/// 项目/待办优先级。
enum ProjectPriority {
  p0('高优先级'),
  p1('中'),
  p2('普通'),
  p3('低');

  const ProjectPriority(this.label);

  final String label;

  static ProjectPriority fromName(String name) => ProjectPriority.values
      .firstWhere(
        (item) => item.name == name,
        orElse: () => ProjectPriority.p2,
      );
}
