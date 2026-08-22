import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';

/// 首页数据总览：项目数、推进中、高优先级、待办四张统计卡。
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

/// 单张统计卡：图标 + 标签 + 数值。
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: cardoryCard(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 扁平化减重：统一灰色小图标，去除彩色图标块。
        Row(
          children: [
            Icon(icon, size: 16, color: CardoryColors.gray400),
            const SizedBox(width: 8),
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
        const SizedBox(height: 14),
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
