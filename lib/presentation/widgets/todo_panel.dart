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
    required this.onAddSubTodo,
    required this.onOpenSubTodo,
    required this.onDeleteSubTodo,
    this.blockedIds = const <String>{},
  });

  final List<TodoData> todos;
  final VoidCallback onAddTodo;
  final Future<void> Function(TodoData todo) onToggle;
  final Future<void> Function(TodoData todo, SubTodoData subTodo)
  onToggleSubTodo;
  final Future<void> Function(TodoData todo) onOpenTodo;
  final Future<bool> Function(TodoData todo) onDeleteTodo;

  /// 快捷添加子待办（待办行内入口与右键菜单共用）。
  final Future<void> Function(TodoData todo) onAddSubTodo;

  /// 打开子待办详情弹窗。
  final Future<void> Function(TodoData todo, SubTodoData subTodo) onOpenSubTodo;

  /// 删除子待办。
  final Future<bool> Function(TodoData todo, SubTodoData subTodo)
  onDeleteSubTodo;

  /// 被未完成前置依赖阻塞的任务 id（甘特依赖的待办语义呈现）。
  final Set<String> blockedIds;

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
                  onAddSubTodo: onAddSubTodo,
                  onOpenSubTodo: onOpenSubTodo,
                  onDeleteSubTodo: onDeleteSubTodo,
                  blocked: blockedIds.contains(todo.id),
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
    required this.onAddSubTodo,
    required this.onOpenSubTodo,
    required this.onDeleteSubTodo,
    this.blocked = false,
  });

  final TodoData todo;
  final Future<void> Function(TodoData todo) onToggle;
  final Future<void> Function(TodoData todo, SubTodoData subTodo)
  onToggleSubTodo;
  final Future<void> Function(TodoData todo) onOpenTodo;
  final Future<bool> Function(TodoData todo) onDeleteTodo;
  final Future<void> Function(TodoData todo) onAddSubTodo;
  final Future<void> Function(TodoData todo, SubTodoData subTodo) onOpenSubTodo;
  final Future<bool> Function(TodoData todo, SubTodoData subTodo)
  onDeleteSubTodo;

  /// 前置任务未完成，任务暂不可开始。
  final bool blocked;

  int get _doneCount => todo.subTodos.where((item) => item.done).length;

  /// 待办快捷菜单：桌面端右键 / 移动端长按唤出。
  Future<void> _showTodoMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final selection = await showContextMenuAt<String>(context, globalPosition, [
      PopupMenuItem(
        value: 'open',
        child: ListTile(
          leading: const Icon(Icons.open_in_new_rounded, size: 20),
          title: const Text('编辑详情'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        value: 'toggle',
        child: ListTile(
          leading: Icon(
            todo.done
                ? Icons.radio_button_unchecked_rounded
                : Icons.check_circle_outline_rounded,
            size: 20,
          ),
          title: Text(todo.done ? '标记未完成' : '标记完成'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        value: 'add-sub',
        child: const ListTile(
          leading: Icon(Icons.playlist_add_rounded, size: 20),
          title: Text('添加子待办'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        value: 'delete',
        child: ListTile(
          leading: Icon(
            Icons.delete_outline_rounded,
            size: 20,
            color: cardoryEnsureWhiteContrast(CardoryColors.error),
          ),
          title: Text(
            '删除',
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
              color: cardoryEnsureWhiteContrast(CardoryColors.error),
            ),
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ]);
    switch (selection) {
      case 'open':
        await onOpenTodo(todo);
      case 'toggle':
        await onToggle(todo);
      case 'add-sub':
        await onAddSubTodo(todo);
      case 'delete':
        await onDeleteTodo(todo);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    // 桌面端右键 / 移动端长按：待办快捷菜单。
    onSecondaryTapDown: (details) =>
        _showTodoMenu(context, details.globalPosition),
    onLongPressStart: (details) =>
        _showTodoMenu(context, details.globalPosition),
    child: Material(
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
                          : CardoryColors.gray500,
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
                                style: Theme.of(context).textTheme.bodyMedium!
                                    .copyWith(
                                      color: todo.done
                                          ? CardoryColors.gray600
                                          : CardoryColors.gray900,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      decoration: todo.done
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                              ),
                            ),
                            if (blocked && !todo.done) ...[
                              const SizedBox(width: 8),
                              Tooltip(
                                message: '前置任务未完成，暂不可开始',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CardoryColors.warning.withValues(
                                      alpha: 0.14,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      CardoryRadius.sm,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.link_rounded,
                                        size: 11,
                                        color: cardoryEnsureWhiteContrast(
                                          CardoryColors.warning,
                                        ),
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '被阻塞',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium!
                                            .copyWith(
                                              color: cardoryEnsureWhiteContrast(
                                                CardoryColors.warning,
                                              ),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              height: 1.3,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (todo.inProgress && !todo.done) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(
                                    CardoryRadius.sm,
                                  ),
                                ),
                                child: Text(
                                  '进行中',
                                  style: Theme.of(context).textTheme.bodyMedium!
                                      .copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        height: 1.3,
                                      ),
                                ),
                              ),
                            ],
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
                                  borderRadius: BorderRadius.circular(
                                    CardoryRadius.sm,
                                  ),
                                ),
                                child: Text(
                                  '已完成',
                                  style: Theme.of(context).textTheme.bodyMedium!
                                      .copyWith(
                                        color: cardoryEnsureWhiteContrast(
                                          CardoryColors.success,
                                        ),
                                        fontSize: 12,
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
                            style: Theme.of(context).textTheme.bodyMedium!
                                .copyWith(
                                  color: CardoryColors.gray600,
                                  fontSize: 13,
                                  height: 1.5,
                                ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${todo.projectTitle} · ${todo.dateRangeText}',
                                style: Theme.of(context).textTheme.bodyMedium!
                                    .copyWith(
                                      color: CardoryColors.gray600,
                                      fontSize: 13,
                                    ),
                              ),
                            ),
                            if (todo.repeatFrequency != null) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message:
                                    '重复：${repeatFrequencyLabel(todo.repeatFrequency!)}',
                                child: Icon(
                                  Icons.repeat_rounded,
                                  size: 14,
                                  color: CardoryColors.gray500,
                                ),
                              ),
                            ],
                            PriorityBadge(priority: todo.priority),
                          ],
                        ),
                        if (todo.tags.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final tag in todo.tags)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CardoryColors.gray100,
                                    borderRadius: BorderRadius.circular(
                                      CardoryRadius.sm,
                                    ),
                                  ),
                                  child: Text(
                                    tag,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium!
                                        .copyWith(
                                          color: CardoryColors.gray600,
                                          fontSize: 12,
                                        ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '删除待办',
                    onPressed: () => onDeleteTodo(todo),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
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
                '子待办 $_doneCount/${todo.subTodos.length}',
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: CardoryColors.gray600,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              for (final subTodo in todo.subTodos) ...[
                SubTodoTile(
                  todo: todo,
                  subTodo: subTodo,
                  onToggle: onToggleSubTodo,
                  onOpenDetail: onOpenSubTodo,
                  onDelete: onDeleteSubTodo,
                ),
                if (subTodo != todo.subTodos.last) const SizedBox(height: 4),
              ],
            ],
            _SubTodoQuickAddRow(onTap: () => onAddSubTodo(todo)),
          ],
        ),
      ),
    ),
  );
}

/// 在指针位置弹出快捷菜单（桌面端右键 / 移动端长按共用）。
Future<T?> showContextMenuAt<T>(
  BuildContext context,
  Offset globalPosition,
  List<PopupMenuEntry<T>> items,
) {
  final overlay = Offset.zero & MediaQuery.sizeOf(context);
  return showMenu(
    context: context,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      overlay,
    ),
    items: items,
  );
}

/// 子待办展开区底部的快捷添加入口。
class _SubTodoQuickAddRow extends StatelessWidget {
  const _SubTodoQuickAddRow({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(CardoryRadius.sm),
    hoverColor: CardoryColors.primarySoft.withValues(alpha: 0.72),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.only(left: 32, top: 8, bottom: 2),
      child: Row(
        children: [
          Icon(Icons.add_rounded, size: 16, color: CardoryColors.gray400),
          const SizedBox(width: 8),
          Text(
            '添加子待办',
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              color: CardoryColors.gray500,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

/// 子待办条目：点击内容进入详情，行首圆圈切换完成，右键/长按出菜单。
class SubTodoTile extends StatelessWidget {
  const SubTodoTile({
    super.key,
    required this.todo,
    required this.subTodo,
    required this.onToggle,
    required this.onOpenDetail,
    required this.onDelete,
  });

  final TodoData todo;
  final SubTodoData subTodo;

  /// 切换完成 / 未完成。
  final Future<void> Function(TodoData todo, SubTodoData subTodo) onToggle;

  /// 打开子待办详情弹窗。
  final Future<void> Function(TodoData todo, SubTodoData subTodo) onOpenDetail;

  /// 删除子待办。
  final Future<bool> Function(TodoData todo, SubTodoData subTodo) onDelete;

  /// 子待办快捷菜单：桌面端右键 / 移动端长按唤出。
  Future<void> _showSubTodoMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final selection = await showContextMenuAt<String>(context, globalPosition, [
      PopupMenuItem(
        value: 'detail',
        child: const ListTile(
          leading: Icon(Icons.visibility_outlined, size: 20),
          title: Text('查看详情'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        value: 'toggle',
        child: ListTile(
          leading: Icon(
            subTodo.done
                ? Icons.radio_button_unchecked_rounded
                : Icons.check_circle_outline_rounded,
            size: 20,
          ),
          title: Text(subTodo.done ? '标记未完成' : '标记完成'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem(
        value: 'delete',
        child: ListTile(
          leading: Icon(
            Icons.delete_outline_rounded,
            size: 20,
            color: cardoryEnsureWhiteContrast(CardoryColors.error),
          ),
          title: Text(
            '删除',
            style: Theme.of(context).textTheme.titleMedium!.copyWith(
              color: cardoryEnsureWhiteContrast(CardoryColors.error),
            ),
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ]);
    switch (selection) {
      case 'detail':
        await onOpenDetail(todo, subTodo);
      case 'toggle':
        await onToggle(todo, subTodo);
      case 'delete':
        await onDelete(todo, subTodo);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    // 桌面端右键 / 移动端长按：子待办快捷菜单。
    onSecondaryTapDown: (details) =>
        _showSubTodoMenu(context, details.globalPosition),
    onLongPressStart: (details) =>
        _showSubTodoMenu(context, details.globalPosition),
    child: Padding(
      padding: const EdgeInsets.only(left: 32, top: 5, bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 行首圆圈：切换完成态。
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onToggle(todo, subTodo),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                subTodo.done
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 16,
                color: subTodo.done
                    ? CardoryColors.success
                    : CardoryColors.gray300,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 内容区：点击进入详情。
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(CardoryRadius.sm),
              onTap: () => onOpenDetail(todo, subTodo),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subTodo.content,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontSize: 13,
                      color: subTodo.done
                          ? CardoryColors.gray600
                          : CardoryColors.gray700,
                      decoration: subTodo.done
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  // 有提醒时间时列表不再展示「添加时间」，详情弹窗内仍显示。
                  if (subTodo.createdAt != null || subTodo.dueAt != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (subTodo.createdAt != null && subTodo.dueAt == null)
                          _SubTodoTimeLabel(
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
          ),
        ],
      ),
    ),
  );
}

class _SubTodoTimeLabel extends StatelessWidget {
  const _SubTodoTimeLabel({
    required this.label,
    required this.value,
    this.icon,
    this.emphasized = false,
  });

  final IconData? icon;
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
          if (icon != null) Icon(icon, size: 13, color: foreground),
          if (icon != null) const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$label ${formatDateTime(value)}',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: foreground,
                fontSize: 12,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
