import '../domain/app_settings.dart';

String reminderPriorityRangeLabel(ProjectPriority priority) =>
    switch (priority) {
      ProjectPriority.p0 => '高优先级及以上',
      ProjectPriority.p1 => '中优先级及以上',
      ProjectPriority.p2 => '普通优先级及以上',
      ProjectPriority.p3 => '全部优先级',
    };
