import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import '../model_colors.dart';

/// 徽章（优先级/阶段）统一样式。
///
/// 浅色背景（卡片、列表）下使用「彩色浅底 + 加深文字」保证 4.5:1 对比度；
/// [onDark] 为 true 时（深色 hero 等）改用「加深实底 + 白字」保证可读。
class _BadgeContainer extends StatelessWidget {
  const _BadgeContainer({
    required this.label,
    required this.color,
    required this.onDark,
  });

  final String label;
  final Color color;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final ink = cardoryEnsureWhiteContrast(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: onDark
            ? ink.withValues(alpha: 0.95)
            : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: onDark ? CardoryColors.white : ink,
          fontSize: 11.5,
          height: 1.3,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.priority, this.onDark = false});

  final ProjectPriority priority;

  /// 是否渲染在深色背景（如渐变 hero）上。
  final bool onDark;

  @override
  Widget build(BuildContext context) =>
      _BadgeContainer(label: priority.label, color: priority.color, onDark: onDark);
}

class StageBadge extends StatelessWidget {
  const StageBadge({super.key, required this.stage, this.onDark = false});

  final ProjectStage stage;

  /// 是否渲染在深色背景（如渐变 hero）上。
  final bool onDark;

  @override
  Widget build(BuildContext context) =>
      _BadgeContainer(label: stage.label, color: stage.color, onDark: onDark);
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
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: CardoryColors.gray200),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: CardoryColors.gray500, fontSize: 12.5),
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
