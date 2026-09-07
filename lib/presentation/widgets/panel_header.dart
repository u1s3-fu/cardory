// 面板头部：标题区 + 操作按钮；窄屏自动换成两行，避免横向溢出。

import 'package:flutter/material.dart';

import 'section_title.dart';

/// 面板头部：宽屏单行（标题 + 次要操作 + 主操作），
/// 窄屏两行（标题 + 主操作一行，次要操作一行）。
class PanelHeader extends StatelessWidget {
  const PanelHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.primaryAction,
  });

  final String title;
  final String subtitle;

  /// 次要操作（图标按钮、视图切换等）。
  final List<Widget> actions;

  /// 主操作按钮（新增资产 / 添加文件）。
  final Widget primaryAction;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final titleRow = Row(
        children: [
          Expanded(child: SectionTitle(title: title, subtitle: subtitle)),
          primaryAction,
        ],
      );
      if (constraints.maxWidth < 560) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleRow,
            const SizedBox(height: 12),
            Row(mainAxisSize: MainAxisSize.min, children: actions),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: SectionTitle(title: title, subtitle: subtitle)),
          ...actions,
          const SizedBox(width: 8),
          primaryAction,
        ],
      );
    },
  );
}
