// 项目阶段与优先级的颜色映射，以及主题色提取扩展。
//
// [ProjectStage.color] 为 planned/doing/review/done 四个阶段提供视觉标识，
// [ProjectPriority.color] 为 P0-P3 四级优先级着色，
// [AppSettings.themeColor] 从整型值恢复 [Color] 供主题系统使用。

import 'package:flutter/material.dart';

import '../domain/cardory_models.dart';
import 'cardory_palette.dart';

extension AppSettingsColors on AppSettings {
  Color get themeColor => Color(themeColorValue);
}

/// 阶段与优先级色一律从当前激活调色板派生，不写死常量。
///
/// 此前这里用的是默认调色板的 `const Color`，导致两处错位：
/// 用户在设置里更换强调色后，「进行中」与 P2 仍是默认靛紫，与新主色打架；
/// 暗色模式下语义色也不跟着提亮。这是全应用 token 化之后唯一残留的
/// 硬编码口子，而它出现在每张项目卡、每个待办与甘特色条上。
///
/// 语义映射：未开始=中性灰、进行中=强调色、待验收=警示、已完成=成功；
/// 优先级 P0=错误红、P1=警示橙、P2=强调色、P3=中性灰。
extension ProjectStageColors on ProjectStage {
  Color get color => switch (this) {
    ProjectStage.planned => CardoryColors.gray400,
    ProjectStage.doing => CardoryColors.primary,
    ProjectStage.review => CardoryColors.warning,
    ProjectStage.done => CardoryColors.success,
  };
}

extension ProjectPriorityColors on ProjectPriority {
  Color get color => switch (this) {
    ProjectPriority.p0 => CardoryColors.error,
    ProjectPriority.p1 => CardoryColors.warning,
    ProjectPriority.p2 => CardoryColors.primary,
    ProjectPriority.p3 => CardoryColors.gray400,
  };
}
