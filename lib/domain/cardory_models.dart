// 业务领域模型定义（领域模型聚合入口）。
//
// 领域模型按聚合拆分：
// - [cardory_enums]：项目阶段 [ProjectStage] 与优先级 [ProjectPriority] 枚举
// - [asset_models]：资产聚合（附件/资产/标签/变动记录）
// - [project_models]：项目聚合（项目实体/进度记录）
// - [todo_models]：待办聚合（待办/子待办）
// - [cardory_data]：聚合根 [CardoryData]
// - [app_settings]：应用设置与同步元数据
// - [cardory_utils]：[newId] / [formatDate] / [formatDateTime] 等工具函数
//
// 本文件作为领域模型唯一入口，各模块可继续直接引用该入口。

export 'app_settings.dart';
export 'asset_models.dart';
export 'cardory_data.dart';
export 'cardory_enums.dart';
export 'cardory_utils.dart';
export 'project_models.dart';
export 'todo_models.dart';
