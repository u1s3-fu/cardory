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
