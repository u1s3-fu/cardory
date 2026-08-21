import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_logo.dart';
import '../cardory_theme.dart';
import '../model_labels.dart';
import '../model_colors.dart';
import '../widgets/badges.dart';
import '../widgets/section_title.dart';

class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.compact,
    required this.title,
    required this.onOpenSettings,
  });

  final bool compact;
  final String title;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 56 : 60,
      // 左侧 padding 与侧边栏菜单图标左边缘对齐（侧边栏 padding 10 + 图标居中偏移 10）
      padding: EdgeInsets.only(
        left: compact ? 16 : 20,
        right: compact ? 16 : 24,
      ),
      decoration: BoxDecoration(
        color: CardoryColors.white.withValues(alpha: 0.72),
        border: Border(
          bottom: BorderSide(
            color: CardoryColors.gray200,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const CardoryLogo(size: 32),

          const SizedBox(width: 12),
          if (!compact) ...[
            Text(
              '板记 Cardory',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: CardoryColors.gray900,
              ),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 20, color: CardoryColors.gray200),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                color: compact ? CardoryColors.gray900 : CardoryColors.gray500,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.tune_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.onAddProject,
    required this.onAddTodo,
  });

  final VoidCallback onAddProject;
  final VoidCallback onAddTodo;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '把项目推进，落到今天',
            style: TextStyle(
              color: CardoryColors.gray900,
              fontSize: compact ? 24 : 28,
              height: 1.2,
              letterSpacing: -0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '集中查看项目阶段、关键待办和最近进度。数据保存在你的本地保险库。',
            style: TextStyle(
              color: CardoryColors.gray500,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        ],
      );
      final actions = Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton.icon(
            onPressed: onAddProject,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('新建项目'),
          ),
          OutlinedButton.icon(
            onPressed: onAddTodo,
            icon: const Icon(Icons.playlist_add_rounded, size: 18),
            label: const Text('添加待办'),
          ),
        ],
      );
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 6,
          vertical: compact ? 16 : 20,
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 18), actions],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 24),
                  actions,
                ],
              ),
      );
    },
  );
}

class Overview extends StatelessWidget {
  const Overview({super.key, required this.data});

  final CardoryData data;

  @override
  Widget build(BuildContext context) {
    final activeCount = data.projects
        .where((item) => item.stage != ProjectStage.done)
        .length;
    final p0Count = data.projects
        .where((item) => item.priority == ProjectPriority.p0)
        .length;
    final todoCount = data.todos.where((todo) => !todo.done).length;
    final cards = [
      OverviewCard(
        label: '项目',
        value: '${data.projects.length}',
        icon: Icons.folder_rounded,
      ),
      OverviewCard(
        label: '推进中',
        value: '$activeCount',
        icon: Icons.trending_up_rounded,
      ),
      OverviewCard(
        label: '高优先级',
        value: '$p0Count',
        icon: Icons.priority_high_rounded,
      ),
      OverviewCard(
        label: '待办',
        value: '$todoCount',
        icon: Icons.checklist_rounded,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        const spacing = 12.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class OverviewCard extends StatelessWidget {
  const OverviewCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final accents = [
      CardoryColors.primary,
      CardoryColors.success,
      CardoryColors.warning,
      CardoryColors.error,
    ];
    final accent =
        accents[(label.codeUnitAt(0) + icon.codePoint) % accents.length];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardoryCard(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cardoryTint(accent, 0.88),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: CardoryColors.gray500,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              color: CardoryColors.gray900,
              fontSize: 28,
              height: 1,
              letterSpacing: -0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

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
                            ? CardoryColors.success.withValues(alpha: 0.18)
                            : CardoryColors.primary.withValues(alpha: 0.10),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
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
                                                ? CardoryColors.gray300
                                                : CardoryColors.gray400,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      PriorityBadge(priority: todo.priority),
                                      Text(
                                        todo.dateRangeText,
                                        style: TextStyle(
                                          color: CardoryColors.error,
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

class KanbanBoard extends StatelessWidget {
  const KanbanBoard({
    super.key,
    required this.data,
    required this.onAddProject,
    required this.onOpenProject,
    required this.onEditProject,
    required this.onDeleteProject,
  });

  final CardoryData data;
  final VoidCallback onAddProject;
  final Future<void> Function(ProjectData project) onOpenProject;
  final Future<void> Function(ProjectData project) onEditProject;
  final Future<void> Function(ProjectData project) onDeleteProject;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionTitle(title: '项目看板', subtitle: '点击项目进入详情页记录进度'),
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 12.0;
          final columnCount = constraints.maxWidth >= 960
              ? 4
              : constraints.maxWidth >= 560
              ? 2
              : 1;
          final columnWidth =
              (constraints.maxWidth - spacing * (columnCount - 1)) /
              columnCount;
          return Wrap(
            key: const Key('kanban-responsive-board'),
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final stage in ProjectStage.values)
                KanbanColumn(
                  width: columnWidth,
                  stage: stage,
                  projects: data.projects
                      .where((item) => item.stage == stage)
                      .toList(),
                  onAddProject: onAddProject,
                  onOpenProject: onOpenProject,
                  onEditProject: onEditProject,
                  onDeleteProject: onDeleteProject,
                ),
            ],
          );
        },
      ),
    ],
  );
}

class KanbanColumn extends StatelessWidget {
  const KanbanColumn({
    super.key,
    required this.width,
    required this.stage,
    required this.projects,
    required this.onAddProject,
    required this.onOpenProject,
    required this.onEditProject,
    required this.onDeleteProject,
  });

  final double width;
  final ProjectStage stage;
  final List<ProjectData> projects;
  final VoidCallback onAddProject;
  final Future<void> Function(ProjectData project) onOpenProject;
  final Future<void> Function(ProjectData project) onEditProject;
  final Future<void> Function(ProjectData project) onDeleteProject;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CardoryColors.white.withValues(alpha: 0.55),
        gradient: LinearGradient(
          colors: [
            cardoryTint(stage.color, 0.90),
            CardoryColors.white.withValues(alpha: 0.55),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: stage.color.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: stage.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stage.label,
                    style: TextStyle(
                      color: cardoryShade(stage.color, 0.35),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                CountPill(count: projects.length),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (projects.isEmpty)
            EmptyCard(
              text: '暂无项目',
              actionLabel: '新建项目',
              onAction: onAddProject,
            )
          else
            for (final project in projects) ...[
              ProjectCard(
                project: project,
                onTap: () => onOpenProject(project),
                onEdit: () => onEditProject(project),
                onDelete: () => onDeleteProject(project),
              ),
              if (project != projects.last) const SizedBox(height: 12),
            ],
        ],
      ),
    ),
  );
}

class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final ProjectData project;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final latest = project.progressEntries.isEmpty
        ? '还没有进度记录'
        : project.progressEntries.last.note;
    return Material(
      color: CardoryColors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        hoverColor: CardoryColors.primarySoft.withValues(alpha: 0.55),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: CardoryColors.primary.withValues(alpha: 0.10),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.045),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        project.title,
                        style: TextStyle(
                          color: CardoryColors.gray900,
                          fontSize: 14.5,
                          letterSpacing: -0.1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: PriorityBadge(priority: project.priority),
                  ),
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: PopupMenuButton<String>(
                      tooltip: '项目操作',
                      icon: Icon(
                        Icons.more_horiz_rounded,
                        size: 18,
                        color: CardoryColors.gray400,
                      ),
                      padding: EdgeInsets.zero,
                      onSelected: (value) {
                        if (value == 'detail') onTap();
                        if (value == 'edit') onEdit();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'detail', child: Text('详情')),
                        PopupMenuItem(value: 'edit', child: Text('编辑')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                project.description.isEmpty ? '暂无项目说明' : project.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CardoryColors.gray500,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      latest,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: CardoryColors.gray400,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: CardoryColors.gray400,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProjectListPanel extends StatelessWidget {
  const ProjectListPanel({
    super.key,
    required this.projects,
    required this.onAddProject,
    required this.onOpenProject,
    required this.onEditProject,
    required this.onDeleteProject,
  });

  final List<ProjectData> projects;
  final VoidCallback onAddProject;
  final Future<void> Function(ProjectData project) onOpenProject;
  final Future<void> Function(ProjectData project) onEditProject;
  final Future<void> Function(ProjectData project) onDeleteProject;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(22),
    decoration: cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: SectionTitle(title: '项目', subtitle: '选择项目，查看进度、待办与关联资产'),
            ),
            FilledButton.icon(
              onPressed: onAddProject,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('新建项目'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (projects.isEmpty)
          EmptyCard(text: '暂无项目', actionLabel: '新建项目', onAction: onAddProject)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1080
                  ? 3
                  : constraints.maxWidth >= 680
                  ? 2
                  : 1;
              final cardWidth =
                  (constraints.maxWidth - (columns - 1) * 14) / columns;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: projects
                    .map(
                      (project) => SizedBox(
                        width: cardWidth,
                        child: ProjectCard(
                          project: project,
                          onTap: () => onOpenProject(project),
                          onEdit: () => onEditProject(project),
                          onDelete: () => onDeleteProject(project),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
      ],
    ),
  );
}

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
          for (final todo in todos) ...[
            TodoTile(
              todo: todo,
              onToggle: onToggle,
              onToggleSubTodo: onToggleSubTodo,
              onOpenTodo: onOpenTodo,
              onDeleteTodo: onDeleteTodo,
            ),
            if (todo != todos.last) const SizedBox(height: 12),
          ],
      ],
    ),
  );
}

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
                ? CardoryColors.success.withValues(alpha: 0.18)
                : CardoryColors.gray200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
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
                    icon: Icon(
                      todo.done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: todo.done
                          ? CardoryColors.success
                          : CardoryColors.gray300,
                    ),
                    onPressed: () => onToggle(todo),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
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
                                    color: CardoryColors.success,
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
                                  color: CardoryColors.gray400,
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
                    color: CardoryColors.error,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            if (todo.subTodos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '子待办 $doneCount/${todo.subTodos.length}',
                style: TextStyle(
                  color: CardoryColors.gray400,
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
                fontSize: 10.5,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProgressTimeline extends StatelessWidget {
  const ProgressTimeline({
    super.key,
    required this.entries,
    required this.onEdit,
  });

  final List<ProjectProgressEntry> entries;
  final Future<void> Function(ProjectProgressEntry entry) onEdit;

  @override
  Widget build(BuildContext context) {
    final ordered = entries.reversed.toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '进度记录', subtitle: '按时间记录项目推进情况'),
          const SizedBox(height: 16),
          if (ordered.isEmpty)
            const EmptyCard(text: '暂无进度记录')
          else
            for (final entry in ordered) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: CardoryColors.primarySoft.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: CardoryColors.primary.withValues(alpha: 0.12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 17,
                          color: CardoryColors.primary,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          formatDateTime(entry.createdAt),
                          style: TextStyle(
                            color: CardoryColors.gray400,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: '编辑进度',
                          onPressed: () => onEdit(entry),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          color: CardoryColors.gray500,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      entry.note,
                      style: TextStyle(
                        color: CardoryColors.gray600,
                        fontSize: 13,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
              if (entry != ordered.last) const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class AssetDetailDialog extends StatelessWidget {
  const AssetDetailDialog({
    super.key,
    required this.asset,
    this.assetTags = const [],
  });

  final AssetData asset;
  final List<AssetTag> assetTags;

  @override
  Widget build(BuildContext context) {
    final isSoftware = asset.type == AssetType.software;
    final tagNames = [
      for (final id in asset.tagIds)
        for (final tag in assetTags)
          if (tag.id == id) tag.name,
    ];
    return AlertDialog(
      title: Row(
        children: [
          Icon(isSoftware ? Icons.apps_outlined : Icons.dns_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text(asset.name)),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Chip(label: Text(isSoftware ? '软件资产' : '硬件资产')),
              if (tagNames.isNotEmpty) _AssetDetailRow(
                label: '标签',
                value: tagNames.join('、'),
              ),
              const SizedBox(height: 12),
              if (isSoftware) ...[
                _AssetDetailRow(label: '版本', value: asset.version),
                _AssetDetailRow(label: '端口', value: asset.port),
                _AssetDetailRow(label: '路径', value: asset.path),
              ] else ...[
                _AssetDetailRow(label: '服务器类型', value: asset.serverType),
                _AssetDetailRow(label: '服务器序列号', value: asset.serialNumber),
                _AssetDetailRow(label: '网络', value: asset.network),
              ],
              _AssetDetailRow(label: '登录用户名', value: asset.username),
              _AssetDetailRow(
                label: '登录密码',
                value: asset.password.isEmpty
                    ? ''
                    : '•' * asset.password.length,
              ),
              _AssetDetailRow(label: '备注 / 用途', value: asset.note),
              const SizedBox(height: 8),
              Text('变动记录', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              if (asset.activities.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    '暂无变动记录',
                    style: TextStyle(color: CardoryColors.gray400),
                  ),
                )
              else
                for (final activity in asset.activities)
                  _AssetActivityRow(activity: activity),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          key: const Key('edit-asset-button'),
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('编辑资产'),
        ),
      ],
    );
  }
}

class _AssetActivityRow extends StatelessWidget {
  const _AssetActivityRow({required this.activity});

  final AssetActivity activity;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (activity.kind) {
      AssetActivityKind.created => (
        Icons.add_circle_outline_rounded,
        CardoryColors.success,
      ),
      AssetActivityKind.updated => (Icons.edit_outlined, CardoryColors.primary),
      AssetActivityKind.deleted => (
        Icons.delete_outline_rounded,
        CardoryColors.error,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.message,
                  style: TextStyle(
                    color: CardoryColors.gray700,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDateTime(activity.timestamp),
                  style: TextStyle(
                    color: CardoryColors.gray400,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetDetailRow extends StatelessWidget {
  const _AssetDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 3),
        Text(value.isEmpty ? '未填写' : value),
      ],
    ),
  );
}
