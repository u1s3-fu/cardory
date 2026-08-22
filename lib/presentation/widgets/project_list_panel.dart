import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import 'badges.dart';
import 'kanban_board.dart' show ProjectCard;
import 'section_title.dart';

/// 首页项目列表：标题 + 新建入口 + 项目卡片网格（响应式列数）。
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
