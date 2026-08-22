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
  Widget build(BuildContext context) => AnimatedContainer(
    duration: cardoryAnimDuration(context, CardoryMotion.base),
    curve: CardoryMotion.inOutCubic,
    clipBehavior: Clip.hardEdge,
    width: expanded ? 208 : 64,
    height: double.infinity,
    padding: EdgeInsets.fromLTRB(10, expanded ? 12 : 6, 10, 12),
    decoration: BoxDecoration(
      color: CardoryColors.white.withValues(alpha: 0.72),
      border: Border(
        right: BorderSide(color: CardoryColors.gray200),
      ),
    ),
    child: Column(
      children: [
        Row(
          children: [
            Tooltip(
              message: expanded ? '折叠侧栏' : '展开侧栏',
              child: IconButton(
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
            ),
            Expanded(
              child: AnimatedOpacity(
                duration: cardoryAnimDuration(context, CardoryMotion.fast),
                curve: CardoryMotion.inOutCubic,
                opacity: expanded ? 1 : 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: expanded ? 1 : 0,
                  child: Text(
                    'Cardory',
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: expanded ? 10 : 6),
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

class SidebarItem extends StatefulWidget {
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
  State<SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<SidebarItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: CardoryMotion.fast,
    value: widget.selected ? 1 : 0,
  );

  late final Animation<Color?> _background = ColorTween(
    begin: Colors.transparent,
    end: CardoryColors.primarySoft,
  ).animate(_controller);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 系统开启「减弱动态效果」时，选中高亮动画直接跳转。
    _controller.duration = cardoryAnimDuration(context, CardoryMotion.fast);
  }

  @override
  void didUpdateWidget(SidebarItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    if (widget.selected) {
      // 新选中：播放选中高亮动画
      _controller.forward();
    } else {
      // 取消选中：立即复位，不播放动画
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.expanded ? '' : widget.label,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: _background.value,
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        ),
        child: Row(
          children: [
            Icon(
              widget.icon,
              size: 20,
              color: widget.selected
                  ? Theme.of(context).colorScheme.primary
                  : CardoryColors.gray400,
            ),
            Expanded(
              child: AnimatedOpacity(
                duration: cardoryAnimDuration(context, CardoryMotion.fast),
                curve: CardoryMotion.inOutCubic,
                opacity: widget.expanded ? 1 : 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: widget.expanded ? 1 : 0,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      widget.label,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: widget.selected
                            ? CardoryColors.gray900
                            : CardoryColors.gray600,
                        fontWeight:
                            widget.selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
