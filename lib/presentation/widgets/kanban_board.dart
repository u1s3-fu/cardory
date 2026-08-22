import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import '../model_colors.dart';
import 'badges.dart';
import 'section_title.dart';

/// 项目看板：按阶段分列的响应式卡片墙。
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
          final projectsByStage = {
            for (final stage in ProjectStage.values) stage: <ProjectData>[],
          };
          for (final project in data.projects) {
            projectsByStage[project.stage]!.add(project);
          }
          return Wrap(
            key: const Key('kanban-responsive-board'),
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final stage in ProjectStage.values)
                KanbanColumn(
                  width: columnWidth,
                  stage: stage,
                  projects: projectsByStage[stage]!,
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

/// 看板中的单个阶段列。
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
        // 扁平化减重：中性白底，去除阶段彩色底、彩色边框与阴影。
        color: CardoryColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CardoryColors.gray100),
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
                    border: Border.all(
                      color: CardoryColors.white.withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stage.label,
                    style: TextStyle(
                      color: CardoryColors.gray800,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                CountPill(
                  count: projects.length,
                  semanticLabel: '${projects.length} 个项目',
                ),
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
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: projects.length,
              itemBuilder: (context, index) {
                final project = projects[index];
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index < projects.length - 1 ? 12 : 0,
                  ),
                  child: ProjectCard(
                    project: project,
                    onTap: () => onOpenProject(project),
                    onEdit: () => onEditProject(project),
                    onDelete: () => onDeleteProject(project),
                  ),
                );
              },
            ),
        ],
      ),
    ),
  );
}

/// 项目卡片，展示标题、优先级、最近进度与操作菜单。
///
/// 桌面端悬停时阴影与边框柔和增强（抬起感），保持克制不产生位移。
class ProjectCard extends StatefulWidget {
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
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final latest = project.progressEntries.isEmpty
        ? '还没有进度记录'
        : project.progressEntries.last.note;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: CardoryColors.white,
        borderRadius: BorderRadius.circular(14),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          hoverColor: CardoryColors.primarySoft.withValues(alpha: 0.55),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: cardoryAnimDuration(context, CardoryMotion.fast),
            curve: CardoryMotion.inOutCubic,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _hovered
                    ? CardoryColors.gray300
                    : CardoryColors.gray200,
              ),
              // 扁平化：hover 时以边框加深替代阴影浮起。
              boxShadow: const [
                BoxShadow(
                  color: Colors.transparent,
                  blurRadius: 0,
                  offset: Offset(0, 0),
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
                          if (value == 'detail') widget.onTap();
                          if (value == 'edit') widget.onEdit();
                          if (value == 'delete') widget.onDelete();
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
                          color: CardoryColors.gray500,
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
      ),
    );
  }
}
