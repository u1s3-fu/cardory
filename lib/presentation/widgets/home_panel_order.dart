import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../domain/app_settings.dart';
import '../cardory_theme.dart';

/// 首页面板标题（拖拽反馈与手柄提示共用）。
String homePanelTitle(HomePanel panel) => switch (panel) {
  HomePanel.todayTasks => '今日任务',
  HomePanel.kanban => '项目看板',
  HomePanel.reminders => '主要提醒',
};

/// 首页面板拖拽手柄：长按整张卡片即可拖动，手柄只作可发现性提示。
class HomePanelDragHandle extends StatelessWidget {
  const HomePanelDragHandle({super.key, required this.panel});

  final HomePanel panel;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '长按${homePanelTitle(panel)}卡片，拖动调整面板顺序',
    child: MouseRegion(
      cursor: SystemMouseCursors.move,
      child: Icon(
        Icons.drag_indicator_rounded,
        size: 20,
        color: CardoryColors.gray400,
      ),
    ),
  );
}

/// 首页面板拖拽排序宿主：长按面板卡片拖动，落到另一张卡片上插入其前方，
/// 落到末尾空白区则移到最后。
class HomePanelOrderHost extends StatelessWidget {
  const HomePanelOrderHost({
    super.key,
    required this.order,
    required this.panels,
    required this.onReorder,
  });

  final List<HomePanel> order;

  /// 面板 id → 面板内容（缺失的面板跳过渲染）。
  final Map<HomePanel, Widget> panels;

  /// 拖拽落定后的新顺序（已包含被拖面板）。
  final Future<void> Function(List<HomePanel> order) onReorder;

  void _move(HomePanel dragged, {HomePanel? before}) {
    if (dragged == before) return;
    final next = order.where((panel) => panel != dragged).toList();
    final index = before == null ? next.length : next.indexOf(before);
    if (index < 0 || listEquals(next, order)) return;
    next.insert(index, dragged);
    onReorder(next);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var index = 0; index < order.length; index++) ...[
        if (index > 0) const SizedBox(height: 22),
        _DraggablePanel(
          panel: order[index],
          onDropBefore: _move,
          child: panels[order[index]] ?? const SizedBox.shrink(),
        ),
      ],
      // 末尾放置区：拖到空白处即移到最后（非拖拽时保留一小条基座，
      // 高度为 0 的区域无法被指针命中，也就永远进不了悬停态）。
      // hitTestBehavior 必须为 opaque：悬停判定走命中测试，空子盒
      // （deferToChild）不可命中，不加这一条基座永远进不了悬停态。
      DragTarget<HomePanel>(
        hitTestBehavior: HitTestBehavior.opaque,
        onAcceptWithDetails: (details) {
          _move(details.data);
        },
        builder: (context, candidate, rejected) => SizedBox(
          // width 必须撑满：子为空时 SizedBox 宽度为 0，命中区域退化成
          // 零宽线，指针进不来（悬停判定走命中测试）。
          width: double.infinity,
          height: candidate.isEmpty ? 48 : 140,
          child: candidate.isEmpty ? null : const _PanelDropHint(),
        ),
      ),
    ],
  );
}

class _DraggablePanel extends StatelessWidget {
  const _DraggablePanel({
    required this.panel,
    required this.child,
    required this.onDropBefore,
  });

  final HomePanel panel;
  final Widget child;

  /// 被拖面板落到本面板上时的回调（插入其前方）。
  final void Function(HomePanel dragged, {HomePanel? before}) onDropBefore;

  @override
  Widget build(BuildContext context) => LongPressDraggable<HomePanel>(
    data: panel,
    dragAnchorStrategy: pointerDragAnchorStrategy,
    feedback: _PanelDragFeedback(title: homePanelTitle(panel)),
    childWhenDragging: Opacity(opacity: 0.45, child: child),
    child: DragTarget<HomePanel>(
      onAcceptWithDetails: (details) {
        onDropBefore(details.data, before: panel);
      },
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CardoryRadius.xl),
            border: hovering
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                : null,
          ),
          child: child,
        );
      },
    ),
  );
}

class _PanelDragFeedback extends StatelessWidget {
  const _PanelDragFeedback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      color: scheme.surface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.primary),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.drag_indicator_rounded, color: scheme.primary),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                color: CardoryColors.gray900,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PanelDropHint extends StatelessWidget {
  const _PanelDropHint();

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Theme.of(context).colorScheme.primary),
    ),
    child: Text(
      '松开以移动到末尾',
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
