import 'package:flutter/material.dart';

import '../cardory_theme.dart';

/// 首页顶部欢迎区：标语 + 新建项目 / 添加待办入口。
///
/// 窄屏下纵向堆叠，宽屏下标题与操作按钮横向排布。
class HeroHeader extends StatelessWidget {
  const HeroHeader({
    super.key,
    required this.onAddProject,
    required this.onAddTodo,
  });

  final VoidCallback onAddProject;
  final VoidCallback onAddTodo;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 760;
      final heading = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '把项目推进，落到今天',
            style: TextStyle(
              color: CardoryColors.gray900,
              fontSize: compact ? 24 : 28,
              height: 1.2,
              letterSpacing: -0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '集中查看项目阶段、关键待办和最近进度。数据保存在你的本地保险库。',
            style: TextStyle(
              color: CardoryColors.gray500,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
        ],
      );
      final actions = Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton.icon(
            onPressed: onAddProject,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('新建项目'),
          ),
          OutlinedButton.icon(
            onPressed: onAddTodo,
            icon: const Icon(Icons.playlist_add_rounded, size: 18),
            label: const Text('添加待办'),
          ),
        ],
      );
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : 6,
          vertical: compact ? 16 : 20,
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 18), actions],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 24),
                  actions,
                ],
              ),
      );
    },
  );
}
