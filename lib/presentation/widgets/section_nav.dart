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
    (AppSection.calendar, Icons.calendar_month_outlined, '日历'),
    (AppSection.time, Icons.timer_outlined, '时间'),
    (AppSection.gantt, Icons.view_timeline_outlined, '甘特'),
    (AppSection.projects, Icons.folder_outlined, '项目'),
    (AppSection.settings, Icons.settings_outlined, '设置'),
  ];

  /// 底部导航只保留 4 个高频分区，其余收纳进「更多」，避免 7 个入口挤满。
  static const _compactPrimary = [
    AppSection.home,
    AppSection.todos,
    AppSection.calendar,
    AppSection.time,
  ];

  void _openOverflowSheet(BuildContext context) {
    final overflow = _items
        .where((item) => !_compactPrimary.contains(item.$1))
        .toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in overflow)
              ListTile(
                leading: Icon(
                  item.$2,
                  color: selected == item.$1
                      ? Theme.of(context).colorScheme.primary
                      : CardoryColors.gray600,
                ),
                title: Text(item.$3),
                trailing: selected == item.$1
                    ? Icon(
                        Icons.check_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  if (item.$1 != selected) onSelected(item.$1);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      final primaryIndex = _compactPrimary.indexOf(selected);
      final selectedIndex = primaryIndex >= 0 ? primaryIndex : 4;
      return NavigationBar(
        height: 64,
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          if (index < _compactPrimary.length) {
            final section = _compactPrimary[index];
            if (section != selected) onSelected(section);
            return;
          }
          _openOverflowSheet(context);
        },
        destinations: [
          for (final section in _compactPrimary)
            NavigationDestination(
              icon: Icon(_items.firstWhere((item) => item.$1 == section).$2),
              label: _items.firstWhere((item) => item.$1 == section).$3,
            ),
          const NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            label: '更多',
          ),
        ],
      );
    }
    return Container(
      height: 48,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: CardoryColors.white.withValues(alpha: 0.72),
        border: Border(bottom: BorderSide(color: CardoryColors.gray200)),
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
