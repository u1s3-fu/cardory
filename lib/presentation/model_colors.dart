/// 卡片模型类型到颜色的映射定义。
///
/// 为不同类型的卡片（文字笔记、图片、链接等）提供预设的颜色标识，生成渐变背景色方案。

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
