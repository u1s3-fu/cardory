import 'package:flutter/material.dart';

import '../app_section.dart';
import '../cardory_theme.dart';

class SectionNavigation extends StatelessWidget {
  const SectionNavigation({
    super.key,
    required this.selected,
    required this.compact,
    required this.onSelected,
  });

  final AppSection selected;
  final bool compact;
  final ValueChanged<AppSection> onSelected;

  static const _items = [
    (AppSection.home, Icons.space_dashboard_outlined, '看板'),
    (AppSection.todos, Icons.checklist_rounded, '待办'),
    (AppSection.projects, Icons.folder_outlined, '项目'),
    (AppSection.settings, Icons.settings_outlined, '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return NavigationBar(
        height: 64,
        selectedIndex: _items.indexWhere((item) => item.$1 == selected),
        onDestinationSelected: (index) {
          final section = _items[index].$1;
          if (section != selected) onSelected(section);
        },
        destinations: [
          for (final item in _items)
            NavigationDestination(icon: Icon(item.$2), label: item.$3),
        ],
      );
    }
    return Container(
      height: 48,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: CardoryColors.white.withValues(alpha: 0.72),
        border: Border(
          bottom: BorderSide(
            color: CardoryColors.primary.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final item in _items)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: TextButton.icon(
                  onPressed: selected == item.$1
                      ? null
                      : () => onSelected(item.$1),
                  icon: Icon(item.$2, size: 17),
                  label: Text(item.$3),
                  style: TextButton.styleFrom(
                    foregroundColor: selected == item.$1
                        ? Theme.of(context).colorScheme.primary
                        : CardoryColors.gray500,
                    backgroundColor: selected == item.$1
                        ? CardoryColors.primarySoft
                        : Colors.transparent,
                    textStyle: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected == item.$1
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
