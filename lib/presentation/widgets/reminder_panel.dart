import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import '../model_labels.dart';
import 'badges.dart';
import 'section_title.dart';
import 'todo_panel.dart';

/// 主要提醒面板：按优先级阈值筛选未完成待办。
class ReminderPanel extends StatelessWidget {
  const ReminderPanel({
    super.key,
    required this.todos,
    required this.priorityThreshold,
    required this.onToggleTodo,
    required this.onToggleSubTodo,
    required this.onAddSubTodo,
    required this.onOpenTodo,
  });

  final List<TodoData> todos;
  final ProjectPriority priorityThreshold;
  final Future<TodoData> Function(TodoData todo) onToggleTodo;
  final Future<TodoData> Function(TodoData todo, SubTodoData subTodo)
  onToggleSubTodo;
  final Future<void> Function(TodoData todo) onAddSubTodo;
  final Future<TodoData?> Function(TodoData todo) onOpenTodo;

  @override
  Widget build(BuildContext context) {
    final reminders = todos
        .where(
          (todo) =>
              !todo.done && todo.priority.index <= priorityThreshold.index,
        )
        .toList();
    final shown = reminders;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: '主要提醒',
            subtitle:
                '${reminderPriorityRangeLabel(priorityThreshold)} · 未完成待办',
          ),
          const SizedBox(height: 16),
          if (shown.isEmpty)
            const EmptyCard(text: '暂无重要提醒')
          else
            for (final todo in shown) ...[
              Material(
                color: todo.done
                    ? CardoryColors.success.withValues(alpha: 0.055)
                    : CardoryColors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  hoverColor: CardoryColors.primarySoft.withValues(alpha: 0.55),
                  onTap: () => onOpenTodo(todo),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: todo.done
                            ? CardoryColors.success.withValues(alpha: 0.14)
                            : CardoryColors.gray100,
                      ),
                      // 扁平化：不使用阴影。
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(5),
                                onTap: () => onToggleTodo(todo),
                                child: Icon(
                                  todo.done
                                      ? Icons.check_box_rounded
                                      : Icons.check_box_outline_blank_rounded,
                                  size: 20,
                                  color: todo.done
                                      ? CardoryColors.success
                                      : CardoryColors.gray300,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    todo.title,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      color: todo.done
                                          ? CardoryColors.gray400
                                          : CardoryColors.gray800,
                                      decoration: todo.done
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 200,
                                        ),
                                        child: Text(
                                          todo.projectTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: todo.done
                                                ? CardoryColors.gray400
                                                : CardoryColors.gray500,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      PriorityBadge(priority: todo.priority),
                                      Text(
                                        todo.dateRangeText,
                                        style: TextStyle(
                                          color: cardoryEnsureWhiteContrast(
                                            CardoryColors.error,
                                          ),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (todo.subTodos.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          for (final subTodo in todo.subTodos)
                            SubTodoTile(
                              todo: todo,
                              subTodo: subTodo,
                              onToggle: (todo, subTodo) async {
                                await onToggleSubTodo(todo, subTodo);
                              },
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              if (todo != shown.last) const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}
