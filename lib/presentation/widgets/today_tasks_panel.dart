import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../../domain/schedule_queries.dart';
import '../cardory_theme.dart';
import 'badges.dart';
import 'section_title.dart';

/// 今日任务面板：逾期（红色标识）与今日截止两组，按优先级排序。
class TodayTasksPanel extends StatelessWidget {
  const TodayTasksPanel({
    super.key,
    required this.todos,
    required this.now,
    required this.onToggleTodo,
    required this.onOpenTodo,
  });

  final List<TodoData> todos;

  /// 当前时间（测试可注入固定值）。
  final DateTime now;
  final Future<TodoData> Function(TodoData todo) onToggleTodo;
  final Future<TodoData?> Function(TodoData todo) onOpenTodo;

  @override
  Widget build(BuildContext context) {
    final aggregate = aggregateTodayTasks(todos, now: now);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: '今日任务',
            subtitle: aggregate.isEmpty
                ? '今天没有待办，尽情安排其他事情'
                : '逾期 ${aggregate.overdue.length} 项 · 今日截止 '
                      '${aggregate.dueToday.length} 项',
          ),
          const SizedBox(height: 16),
          if (aggregate.isEmpty)
            Row(
              children: [
                Icon(
                  Icons.wb_sunny_outlined,
                  size: 18,
                  color: CardoryColors.gray400,
                ),
                const SizedBox(width: 8),
                Text(
                  '暂无逾期与今日截止的任务',
                  style: TextStyle(color: CardoryColors.gray500, fontSize: 13),
                ),
              ],
            )
          else ...[
            for (final todo in aggregate.overdue)
              _TodayTile(
                todo: todo,
                now: now,
                overdue: true,
                onToggleTodo: onToggleTodo,
                onOpenTodo: onOpenTodo,
              ),
            for (final todo in aggregate.dueToday)
              _TodayTile(
                todo: todo,
                now: now,
                overdue: false,
                onToggleTodo: onToggleTodo,
                onOpenTodo: onOpenTodo,
              ),
          ],
        ],
      ),
    );
  }
}

class _TodayTile extends StatelessWidget {
  const _TodayTile({
    required this.todo,
    required this.now,
    required this.overdue,
    required this.onToggleTodo,
    required this.onOpenTodo,
  });

  final TodoData todo;
  final DateTime now;
  final bool overdue;
  final Future<TodoData> Function(TodoData todo) onToggleTodo;
  final Future<TodoData?> Function(TodoData todo) onOpenTodo;

  @override
  Widget build(BuildContext context) {
    final due = todo.endDate!;
    final dueLabel = overdue
        ? '逾期至 ${formatDate(due)}'
        : '今日 ${due.hour == 0 && due.minute == 0 ? '' : ' ${due.hour.toString().padLeft(2, '0')}:${due.minute.toString().padLeft(2, '0')}'}'
              .trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onOpenTodo(todo),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Checkbox(
                  value: todo.done,
                  onChanged: (_) => onToggleTodo(todo),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todo.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: todo.done
                            ? CardoryColors.gray400
                            : CardoryColors.gray900,
                        decoration: todo.done
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        PriorityBadge(priority: todo.priority),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            dueLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: overdue
                                  ? cardoryEnsureWhiteContrast(
                                      CardoryColors.error,
                                      minRatio: 3,
                                    )
                                  : CardoryColors.gray500,
                              fontWeight: overdue
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (todo.projectTitle.isNotEmpty)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      todo.projectTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: CardoryColors.gray400,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
