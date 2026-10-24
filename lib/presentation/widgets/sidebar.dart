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
    (AppSection.calendar, Icons.calendar_month_outlined, '日历'),
    (AppSection.time, Icons.timer_outlined, '时间'),
    (AppSection.gantt, Icons.view_timeline_outlined, '甘特'),
    (AppSection.projects, Icons.folder_outlined, '项目'),
    (AppSection.assets, Icons.inventory_2_outlined, '资产库'),
    (AppSection.settings, Icons.settings_outlined, '设置'),
  ];

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    // 侧栏是常驻chrome，内容区（看板等重列表）在它旁边滚动/重排时不应
    // 被它的重绘拖着一起重画；这一层把两者的重绘域隔开。
    child: AnimatedContainer(
      duration: cardoryAnimDuration(context, CardoryMotion.base),
      curve: CardoryMotion.inOutCubic,
      clipBehavior: Clip.hardEdge,
      width: expanded ? 208 : 64,
      height: double.infinity,
      // 内边距不随展开态变化：AnimatedContainer 会连内边距一起补间，
      // 那是在动画布局属性，展开/收起期间白白多一层重排。
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      decoration: BoxDecoration(
        // 半透明白叠在灰底上会让侧栏发脏；此处不是浮层，直接用实色。
        color: CardoryColors.white,
        border: Border(right: BorderSide(color: CardoryColors.gray200)),
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
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 44,
                  ),
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
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
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
    final duration = cardoryAnimDuration(context, CardoryMotion.fast);
    _controller.duration = duration;
    // 退出取进入的 75%：取消选中比选中更快收尾，把注意力让给新选中项。
    // 早期这里是 _controller.value = 0 立即复位，高亮「说来就来、说走就走」，
    // 进出节奏不对称。
    _controller.reverseDuration = Duration(
      milliseconds: (duration.inMilliseconds * 3 / 4).round(),
    );
  }

  @override
  void didUpdateWidget(SidebarItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected == widget.selected) return;
    if (widget.selected) {
      // 新选中：播放选中高亮动画。
      _controller.forward();
    } else {
      // 取消选中：播退出动画，与进入对称。
      _controller.reverse();
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
      // 此前三个反馈通道全部设为 transparent，8 个主导航项在鼠标
      // 悬停/按下时毫无反应，用户无法确认「这项能不能点」。
      hoverColor: CardoryColors.gray100,
      highlightColor: CardoryColors.gray200.withValues(alpha: 0.6),
      splashColor: CardoryColors.primarySoft,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Container(
          // 水平内边距 10：侧栏宽度动画区间为 208↔64，任何时刻
          // 内容区可用宽度都 ≥44，图标 20px 不会溢出（曾取 12，
          // 折叠动画中途侧栏宽 43 时可用宽度仅 19，瞬态溢出 1px，
          // 被 widget 测试的布局断言捕获）。
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
                  : CardoryColors.gray500,
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
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        color: widget.selected
                            ? CardoryColors.gray900
                            : CardoryColors.gray600,
                        fontWeight: widget.selected
                            ? FontWeight.w700
                            : FontWeight.w500,
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
