import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import '../model_colors.dart';

class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.priority});

  final ProjectPriority priority;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: priority.color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      priority.label,
      style: TextStyle(
        color: priority.color,
        fontSize: 11,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class StageBadge extends StatelessWidget {
  const StageBadge({super.key, required this.stage});

  final ProjectStage stage;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: stage.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      stage.label,
      style: TextStyle(
        color: stage.color,
        fontSize: 11,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class CountPill extends StatelessWidget {
  const CountPill({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: CardoryColors.gray100,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      '$count',
      style: TextStyle(
        color: CardoryColors.gray600,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
    decoration: BoxDecoration(
      color: CardoryColors.gray50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: CardoryColors.gray200),
    ),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: CardoryColors.gray400, fontSize: 12.5),
    ),
  );
}
