import 'package:flutter/material.dart';

import '../cardory_logo.dart';
import '../cardory_theme.dart';

/// 应用顶部栏：Logo + 标题 + 设置入口。
///
/// 紧凑模式下隐藏品牌名，仅保留标题与设置按钮。
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.compact,
    required this.title,
    required this.onOpenSettings,
  });

  final bool compact;
  final String title;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 56 : 60,
      // 左侧 padding 与侧边栏菜单图标左边缘对齐（侧边栏 padding 10 + 图标居中偏移 10）
      padding: EdgeInsets.only(
        left: compact ? 16 : 20,
        right: compact ? 16 : 24,
      ),
      decoration: BoxDecoration(
        color: CardoryColors.white.withValues(alpha: 0.85),
        border: Border(
          bottom: BorderSide(
            color: CardoryColors.gray200,
          ),
        ),
        // 扁平化：不使用阴影。
      ),
      child: Row(
        children: [
          const CardoryLogo(size: 32),

          const SizedBox(width: 12),
          if (!compact) ...[
            Text(
              '板记 Cardory',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: CardoryColors.gray900,
              ),
            ),
            const SizedBox(width: 16),
            Container(width: 1, height: 20, color: CardoryColors.gray200),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                color: compact ? CardoryColors.gray900 : CardoryColors.gray500,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: '设置',
            onPressed: onOpenSettings,
            icon: const Icon(Icons.tune_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}
