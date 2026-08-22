import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import 'badges.dart';
import 'section_title.dart';

/// 待办面板：待办列表与子待办展开。
class TodoPanel extends StatelessWidget {
  const TodoPanel({
    super.key,
    required this.todos,
    required this.onAddTodo,
    required this.onToggle,
    required this.onToggleSubTodo,
    required this.onOpenTodo,
    required this.onDeleteTodo,
  });

  final List<TodoData> todos;
  final VoidCallback onAddTodo;
  final Future<void> Function(TodoData todo) onToggle;
  final Future<void> Function(TodoData todo, SubTodoData subTodo)
  onToggleSubTodo;
  final Future<void> Function(TodoData todo) onOpenTodo;
  final Future<bool> Function(TodoData todo) onDeleteTodo;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: SectionTitle(title: '待办', subtitle: '下一步行动，可点击查看/编辑详情'),
            ),
            OutlinedButton.icon(
              onPressed: onAddTodo,
              icon: const Icon(Icons.playlist_add_rounded, size: 18),
              label: const Text('添加待办'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (todos.isEmpty)
          EmptyCard(text: '暂无待办', actionLabel: '添加待办', onAction: onAddTodo)
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: todos.length,
            itemBuilder: (context, index) {
              final todo = todos[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index < todos.length - 1 ? 12 : 0,
                ),
                child: TodoTile(
                  todo: todo,
                  onToggle: onToggle,
                  onToggleSubTodo: onToggleSubTodo,
                  onOpenTodo: onOpenTodo,
                  onDeleteTodo: onDeleteTodo,
                ),
              );
            },
          ),
      ],
    ),
  );
}

/// 单个待办条目：标题、说明、所属项目、优先级与完成状态。
class TodoTile extends StatelessWidget {
  const TodoTile({
    super.key,
    required this.todo,
    required this.onToggle,
    required this.onToggleSubTodo,
    required this.onOpenTodo,
    required this.onDeleteTodo,
  });

  final TodoData todo;
  final Future<void> Function(TodoData todo) onToggle;
  final Future<void> Function(TodoData todo, SubTodoData subTodo)
  onToggleSubTodo;
  final Future<void> Function(TodoData todo) onOpenTodo;
  final Future<bool> Function(TodoData todo) onDeleteTodo;

  @override
  Widget build(BuildContext context) {
    final doneCount = todo.subTodos.where((item) => item.done).length;
    return Material(
      color: todo.done
          ? CardoryColors.success.withValues(alpha: 0.055)
          : CardoryColors.white,
      borderRadius: BorderRadius.circular(14),
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
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onOpenTodo(todo),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    tooltip: todo.done ? '标记未完成' : '标记完成',
                    icon: Icon(
                      todo.done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: todo.done
                          ? cardoryEnsureWhiteContrast(
                              CardoryColors.success,
                              minRatio: 3,
                            )
                          : CardoryColors.gray400,
                    ),
                    onPressed: () => onToggle(todo),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                todo.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: todo.done
                                      ? CardoryColors.gray400
                                      : CardoryColors.gray800,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  decoration: todo.done
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            if (todo.done) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: CardoryColors.success.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '已完成',
                                  style: TextStyle(
                                    color: cardoryEnsureWhiteContrast(
                                      CardoryColors.success,
                                    ),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (todo.description.isNotEmpty)
                          Text(
                            todo.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: CardoryColors.gray500,
                              fontSize: 12.5,
                              height: 1.5,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${todo.projectTitle} · ${todo.dateRangeText}',
                                style: TextStyle(
                                  color: CardoryColors.gray500,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            PriorityBadge(priority: todo.priority),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '删除待办',
                    onPressed: () => onDeleteTodo(todo),
                    icon: const Icon(Icons.delete_outline_rounded, size: 19),
                    color: cardoryEnsureWhiteContrast(CardoryColors.error),
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            if (todo.subTodos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '子待办 $doneCount/${todo.subTodos.length}',
                style: TextStyle(
                  color: CardoryColors.gray500,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              for (final subTodo in todo.subTodos) ...[
                SubTodoTile(
                  todo: todo,
                  subTodo: subTodo,
                  onToggle: onToggleSubTodo,
                ),
                if (subTodo != todo.subTodos.last) const SizedBox(height: 4),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// 子待办条目：支持勾选与创建/提醒时间展示。
class SubTodoTile extends StatelessWidget {
  const SubTodoTile({
    super.key,
    required this.todo,
    required this.subTodo,
    required this.onToggle,
  });

  final TodoData todo;
  final SubTodoData subTodo;
  final Future<void> Function(TodoData todo, SubTodoData subTodo) onToggle;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(10),
    hoverColor: CardoryColors.primarySoft.withValues(alpha: 0.72),
    onTap: () => onToggle(todo, subTodo),
    child: Padding(
      padding: const EdgeInsets.only(left: 32, top: 5, bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              subTodo.done ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 16,
              color: subTodo.done
                  ? CardoryColors.success
                  : CardoryColors.gray300,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subTodo.content,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: subTodo.done
                        ? CardoryColors.gray400
                        : CardoryColors.gray600,
                    decoration: subTodo.done
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                if (subTodo.createdAt != null || subTodo.dueAt != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (subTodo.createdAt != null)
                        _SubTodoTimeLabel(
                          icon: Icons.add_circle_outline_rounded,
                          label: '添加',
                          value: subTodo.createdAt!,
                        ),
                      if (subTodo.dueAt != null)
                        _SubTodoTimeLabel(
                          icon: Icons.alarm_rounded,
                          label: '提醒',
                          value: subTodo.dueAt!,
                          emphasized: true,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _SubTodoTimeLabel extends StatelessWidget {
  const _SubTodoTimeLabel({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final DateTime value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = emphasized
        ? colorScheme.onPrimaryContainer
        : CardoryColors.gray500;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: emphasized
            ? colorScheme.primaryContainer
            : CardoryColors.gray100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$label ${formatDateTime(value)}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
