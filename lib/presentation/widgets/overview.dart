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
        // 按最小列宽连续推导，避免 519px 一列 / 520px 两列的跳变。
        final columns = cardoryColumns(
          constraints.maxWidth,
          minColumnWidth: 250,
          max: 4,
        );
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
        // 极浅重点色底 + 主题色图标：既保留扁平克制的底色，
        // 又让四张统计卡有一个可扫读的焦点（此前图标全灰，整排糊成一片）。
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: CardoryColors.primarySoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                icon,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: CardoryColors.gray600,
                fontSize: 13,
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
            fontSize: 32,
            height: 1,
            letterSpacing: -1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
