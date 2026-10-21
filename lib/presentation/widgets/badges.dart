import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import '../model_colors.dart';

/// 徽章（优先级/阶段）统一样式。
///
/// 一律使用「彩色浅底 + 加深文字」，由 [cardoryEnsureWhiteContrast] 把文字
/// 压到与浅底对比度 ≥ 4.5:1；扁平化之后已无深色 hero 场景，早期的 onDark
/// 分支（实底 + 白字）随之移除。
class _BadgeContainer extends StatelessWidget {
  const _BadgeContainer({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ink = cardoryEnsureWhiteContrast(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(CardoryRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: ink,
          // 11.5px 的中文标签偏挤，提到 12 是中文可读的下限。
          fontSize: 12,
          height: 1.3,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.priority});

  final ProjectPriority priority;

  @override
  Widget build(BuildContext context) =>
      _BadgeContainer(label: priority.label, color: priority.color);
}

class StageBadge extends StatelessWidget {
  const StageBadge({super.key, required this.stage});

  final ProjectStage stage;

  @override
  Widget build(BuildContext context) =>
      _BadgeContainer(label: stage.label, color: stage.color);
}

class CountPill extends StatelessWidget {
  const CountPill({super.key, required this.count, this.semanticLabel});

  final int count;

  /// 读屏语义标签（如“3 个项目”）；未提供时仅朗读数字。
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: CardoryColors.gray100,
        borderRadius: BorderRadius.circular(CardoryRadius.sm),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: CardoryColors.gray600,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final label = semanticLabel;
    return label == null
        ? pill
        : Semantics(label: label, excludeSemantics: true, child: pill);
  }
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({
    super.key,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
    decoration: BoxDecoration(
      color: CardoryColors.gray50,
      borderRadius: BorderRadius.circular(CardoryRadius.md),
      border: Border.all(color: CardoryColors.gray200),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: CardoryColors.gray600, fontSize: 13),
        ),
        if (onAction != null && actionLabel != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(actionLabel!),
          ),
        ],
      ],
    ),
  );
}
