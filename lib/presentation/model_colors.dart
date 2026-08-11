// 项目阶段与优先级的颜色映射，以及主题色提取扩展。
//
// [ProjectStage.color] 为 planned/doing/review/done 四个阶段提供视觉标识，
// [ProjectPriority.color] 为 P0-P3 四级优先级着色，
// [AppSettings.themeColor] 从整型值恢复 [Color] 供主题系统使用。

import 'package:flutter/material.dart';

import '../domain/cardory_models.dart';

extension AppSettingsColors on AppSettings {
  Color get themeColor => Color(themeColorValue);
}

extension ProjectStageColors on ProjectStage {
  Color get color => switch (this) {
    ProjectStage.planned => const Color(0xFF8B8AB5),
    ProjectStage.doing => const Color(0xFF6B62DF),
    ProjectStage.review => const Color(0xFFF2A354),
    ProjectStage.done => const Color(0xFF44B88A),
  };
}

extension ProjectPriorityColors on ProjectPriority {
  Color get color => switch (this) {
    ProjectPriority.p0 => const Color(0xFFEF7180),
    ProjectPriority.p1 => const Color(0xFFF2A354),
    ProjectPriority.p2 => const Color(0xFF6B62DF),
    ProjectPriority.p3 => const Color(0xFF8B8AB5),
  };
}
