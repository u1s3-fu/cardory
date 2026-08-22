// 通用批量操作条。

import 'package:flutter/material.dart';

import '../cardory_theme.dart';

/// 多选状态下的批量操作条：展示选中数量与操作按钮。
class BatchActionBar extends StatelessWidget {
  const BatchActionBar({
    super.key,
    required this.count,
    required this.actions,
  });

  final int count;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: CardoryColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '已选 $count 项',
            style: TextStyle(
              color: CardoryColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
