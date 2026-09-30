// 任务依赖的自动排期（finish-to-start 约束传播）。
//
// 规则：后继任务的最早开始 = max(自身开始, 所有前驱的结束日 + 1 天)；
// 仅当后继当前开始早于该日才调整（不推迟已排的更晚日期）；后继未排期
// 时自动设为该日；结束日随开始平移保持时长（原无开始日时保留截止日、
// 不早于新开始；无结束日则设为开始日）。前驱无任何日期时不产生约束。
// 结果为需要写回的任务变更对，由调用方经行级存储落库（自动进入同步通道）。

import 'cardory_models.dart';
import 'milestone_models.dart';
import 'schedule_queries.dart';

/// 一次传播产生的任务变更：original 为库中现值，updated 为调整后值。
class DependencyScheduleUpdate {
  const DependencyScheduleUpdate({
    required this.original,
    required this.updated,
  });

  final TodoData original;
  final TodoData updated;
}

/// 依据依赖关系计算 [seedTodoIds]（完成或日期变更的任务）沿后继链
/// 传播产生的排期调整（纯函数，便于单测）。
///
/// 传播按广度优先逐层进行：链式依赖 A→B→C 在 A 完成后可同时重排 B 与 C。
/// 防御性 visited 集合兜底环数据（正常由 addDependency 环检测拦截）。
List<DependencyScheduleUpdate> propagateDependencySchedule({
  required List<TodoData> todos,
  required List<TaskDependencyData> dependencies,
  required Set<String> seedTodoIds,
}) {
  final todoById = {for (final todo in todos) todo.id: todo};
  // 传播过程中的生效日期（种子与已调整的后继），供下游层使用。
  final effectiveEnd = <String, DateTime>{};
  final updates = <DependencyScheduleUpdate>[];
  final visited = <String>{};
  final queue = <String>[
    for (final id in seedTodoIds)
      if (todoById.containsKey(id)) id,
  ];

  // 一个任务的生效结束日：优先传播中的调整值，回退库中现值。
  DateTime? endDateOf(String todoId) {
    final effective = effectiveEnd[todoId];
    if (effective != null) return effective;
    final todo = todoById[todoId];
    if (todo == null) return null;
    final end = todo.endDate ?? todo.startDate;
    return end == null ? null : localDayKey(end);
  }

  while (queue.isNotEmpty) {
    final currentId = queue.removeAt(0);
    if (visited.contains(currentId)) continue;
    visited.add(currentId);

    final predecessorEnd = endDateOf(currentId);
    // 传播只在后继进行；前驱无日期则本链到此为止。
    if (predecessorEnd == null) continue;

    for (final dependency in dependencies) {
      if (dependency.predecessorTaskId != currentId) continue;
      final successor = todoById[dependency.successorTaskId];
      if (successor == null || visited.contains(successor.id)) continue;

      // 已完成的后继不再调整排期（完成的任务不应被搬到未来），
      // 但其日期仍是更下游任务的约束。
      if (successor.done) {
        final successorEnd = successor.endDate ?? successor.startDate;
        if (successorEnd != null) {
          effectiveEnd[successor.id] = localDayKey(successorEnd);
          queue.add(successor.id);
        }
        continue;
      }

      final earliest = predecessorEnd.add(const Duration(days: 1));
      final currentStart = successor.startDate == null
          ? null
          : localDayKey(successor.startDate!);
      final needsShift =
          currentStart == null || currentStart.isBefore(earliest);
      if (!needsShift) {
        // 未调整也要入队：后继自身的日期是更下游任务的约束。
        effectiveEnd[successor.id] = localDayKey(
          successor.endDate ?? successor.startDate!,
        );
        queue.add(successor.id);
        continue;
      }

      final DateTime shiftedEnd;
      if (successor.endDate == null) {
        shiftedEnd = earliest;
      } else if (currentStart == null) {
        // 原本只设了截止日：保留截止日（不早于新开始）。
        final existingEnd = localDayKey(successor.endDate!);
        shiftedEnd = existingEnd.isBefore(earliest) ? earliest : existingEnd;
      } else {
        // 随开始平移，保持时长。
        shiftedEnd = earliest.add(
          localDayKey(successor.endDate!).difference(currentStart),
        );
      }
      final updated = successor.copyWith(
        startDate: earliest,
        endDate: shiftedEnd,
      );
      updates.add(
        DependencyScheduleUpdate(original: successor, updated: updated),
      );
      effectiveEnd[successor.id] = localDayKey(shiftedEnd);
      queue.add(successor.id);
    }
  }
  return updates;
}
