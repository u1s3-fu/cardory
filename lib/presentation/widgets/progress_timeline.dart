import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import 'badges.dart';
import 'section_title.dart';

/// 项目进度时间线：按时间倒序展示最近进度记录。
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
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: CardoryColors.gray100),
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
                            color: CardoryColors.gray500,
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
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          padding: EdgeInsets.zero,
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
