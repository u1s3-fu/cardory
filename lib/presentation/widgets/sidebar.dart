import 'package:flutter/material.dart';

import '../app_section.dart';
import '../cardory_theme.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.selected,
    required this.expanded,
    required this.onSelected,
    this.onToggleExpanded,
  });

  final AppSection selected;
  final bool expanded;
  final ValueChanged<AppSection> onSelected;
  final VoidCallback? onToggleExpanded;

  static const _items = [
    (AppSection.home, Icons.space_dashboard_outlined, '看板'),
    (AppSection.todos, Icons.check_circle_outline_rounded, '待办'),
    (AppSection.projects, Icons.folder_outlined, '项目'),
    (AppSection.settings, Icons.settings_outlined, '设置'),
  ];

  @override
  Widget build(BuildContext context) => Container(
    width: expanded ? 208 : 64,
    height: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    decoration: BoxDecoration(
      color: CardoryColors.white.withValues(alpha: 0.72),
      border: Border(
        right: BorderSide(color: CardoryColors.primary.withValues(alpha: 0.06)),
      ),
    ),
    child: Column(
      children: [
        Row(
          children: [
            IconButton(
              style: IconButton.styleFrom(
                minimumSize: const Size(40, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              constraints: const BoxConstraints.tightFor(width: 40, height: 44),
              padding: EdgeInsets.zero,
              onPressed: onToggleExpanded,
              icon: Icon(
                expanded ? Icons.menu_open_rounded : Icons.menu_rounded,
                size: 20,
              ),
              color: CardoryColors.gray500,
            ),
            if (expanded)
              Expanded(
                child: Text(
                  'Cardory',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    foreground: Paint()
                      ..shader = LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          CardoryColors.pink,
                        ],
                      ).createShader(const Rect.fromLTWH(0, 0, 120, 20)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        for (final item in _items) ...[
          SidebarItem(
            icon: item.$2,
            label: item.$3,
            selected: selected == item.$1,
            expanded: expanded,
            onTap: selected == item.$1 ? null : () => onSelected(item.$1),
          ),
          const SizedBox(height: 2),
        ],
      ],
    ),
  );
}

class SidebarItem extends StatelessWidget {
  const SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: expanded ? '' : label,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? CardoryColors.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : CardoryColors.gray400,
            ),
            if (expanded) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: selected
                        ? CardoryColors.gray900
                        : CardoryColors.gray600,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
