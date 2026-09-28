// 甘特时间线：项目/任务起止排期条形 + 里程碑菱形标记 + 月份表头。

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../../domain/milestone_models.dart';
import '../../domain/schedule_queries.dart';
import '../cardory_theme.dart';
import '../model_colors.dart';
import '../widgets/section_title.dart';

/// 甘特时间线卡片：时间窗口自适应日期跨度，任务条点击回调调整排期。
class GanttTimeline extends StatelessWidget {
  const GanttTimeline({
    super.key,
    required this.projects,
    required this.todos,
    required this.milestones,
    required this.now,
    required this.onSelectTodo,
  });

  final List<ProjectData> projects;
  final List<TodoData> todos;
  final List<MilestoneData> milestones;
  final DateTime now;
  final Future<void> Function(TodoData todo) onSelectTodo;

  static const _dayWidth = 22.0;
  static const _rowHeight = 34.0;
  static const _labelWidth = 170.0;

  @override
  Widget build(BuildContext context) {
    // 时间窗口：最早/最晚日期与今天的并集，两侧各留 3 天。
    final dated = <DateTime>[now];
    for (final project in projects) {
      if (project.startDate != null) dated.add(localDayKey(project.startDate!));
      if (project.endDate != null) dated.add(localDayKey(project.endDate!));
    }
    for (final todo in todos) {
      if (todo.startDate != null) dated.add(localDayKey(todo.startDate!));
      if (todo.endDate != null) dated.add(localDayKey(todo.endDate!));
    }
    for (final milestone in milestones) {
      dated.add(localDayKey(milestone.dueAt));
    }
    var start = dated
        .reduce((a, b) => a.isBefore(b) ? a : b)
        .subtract(const Duration(days: 3));
    var end = dated
        .reduce((a, b) => a.isAfter(b) ? a : b)
        .add(const Duration(days: 3));
    final totalDays = end.difference(start).inDays + 1;
    if (totalDays > 240) {
      // 防御极端日期：窗口过宽时向今天收拢。
      start = now.subtract(const Duration(days: 90));
      end = now.add(const Duration(days: 149));
    }

    final milestonesByProject = {
      for (final milestone in milestones)
        milestone.projectId: <MilestoneData>[],
    };
    for (final milestone in milestones) {
      milestonesByProject
          .putIfAbsent(milestone.projectId, () => [])
          .add(milestone);
    }

    final timelineWidth = totalDays * _dayWidth;

    final rows = <Widget>[];
    for (final project in projects) {
      rows.add(
        _GanttBar(
          label: project.title,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          start: project.startDate,
          end: project.endDate,
          color: project.stage.color,
          windowStart: start,
          dayWidth: _dayWidth,
          timelineWidth: timelineWidth,
          height: _rowHeight,
          markers: [
            for (final milestone
                in milestonesByProject[project.id] ?? const <MilestoneData>[])
              _BarMarker(
                day: localDayKey(milestone.dueAt),
                label: milestone.title,
                color: milestone.completed
                    ? CardoryColors.gray400
                    : CardoryColors.gray800,
              ),
          ],
        ),
      );
      final projectTodos =
          todos.where((todo) => todo.projectId == project.id).toList()..sort(
            (a, b) => (a.endDate ?? a.startDate ?? now).compareTo(
              b.endDate ?? b.startDate ?? now,
            ),
          );
      for (final todo in projectTodos) {
        rows.add(
          _GanttBar(
            label: todo.title,
            indent: true,
            start: todo.startDate ?? todo.endDate,
            end: todo.endDate ?? todo.startDate,
            color: todo.done ? CardoryColors.gray300 : const Color(0xFF6B9EDF),
            windowStart: start,
            dayWidth: _dayWidth,
            timelineWidth: timelineWidth,
            height: _rowHeight,
            onTap: () => onSelectTodo(todo),
          ),
        );
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            title: '甘特时间线',
            subtitle: '项目与任务起止排期，◆ 为里程碑，点击任务条调整日期',
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '还没有项目，先在看板新建项目。',
                style: TextStyle(fontSize: 13, color: CardoryColors.gray500),
              ),
            )
          else
            // 水平滚动容器：子项定宽（标签列 + 时间轴全宽）。
            // 不能用 width: double.infinity——水平滚动给无界宽度约束，
            // 无限宽会让 Stack 裁掉首屏之外的条形（时间线显示不完整）。
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _labelWidth + timelineWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TimelineHeader(
                      windowStart: start,
                      totalDays: totalDays,
                      dayWidth: _dayWidth,
                      labelWidth: _labelWidth,
                    ),
                    for (final row in rows) row,
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineHeader extends StatelessWidget {
  const _TimelineHeader({
    required this.windowStart,
    required this.totalDays,
    required this.dayWidth,
    required this.labelWidth,
  });

  final DateTime windowStart;
  final int totalDays;
  final double dayWidth;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final monthMarks = <(int, String)>[];
    for (var day = 0; day < totalDays; day++) {
      final date = windowStart.add(Duration(days: day));
      if (date.day == 1) {
        monthMarks.add((day, '${date.year}/${date.month}'));
      }
    }
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          SizedBox(width: labelWidth),
          // 显式给时间轴全宽：Stack 默认只占视口宽度，月份标签超出部分会被裁剪。
          SizedBox(
            width: totalDays * dayWidth,
            child: Stack(
              children: [
                for (final (day, label) in monthMarks)
                  Positioned(
                    left: day * dayWidth,
                    top: 0,
                    bottom: 0,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: CardoryColors.gray500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarMarker {
  const _BarMarker({
    required this.day,
    required this.label,
    required this.color,
  });

  final DateTime day;
  final String label;
  final Color color;
}

class _GanttBar extends StatelessWidget {
  const _GanttBar({
    required this.label,
    required this.start,
    required this.end,
    required this.color,
    required this.windowStart,
    required this.dayWidth,
    required this.timelineWidth,
    required this.height,
    this.labelStyle,
    this.indent = false,
    this.markers = const [],
    this.onTap,
  });

  final String label;
  final DateTime? start;
  final DateTime? end;
  final Color color;
  final DateTime windowStart;
  final double dayWidth;

  /// 时间轴全宽（条形以 Positioned 定位，Stack 必须与滚动内容等宽，
  /// 否则首屏之外的条形会被裁剪）。
  final double timelineWidth;
  final double height;
  final TextStyle? labelStyle;
  final bool indent;
  final List<_BarMarker> markers;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final barStart = start == null ? null : localDayKey(start!);
    final barEnd = end == null ? null : localDayKey(end!);
    // 条形位置与宽度都夹取到时间轴窗口内，超出窗口的日期不越界绘制。
    final left = barStart == null
        ? null
        : (barStart.difference(windowStart).inDays * dayWidth).clamp(
            0.0,
            timelineWidth,
          );
    final width = barStart == null || barEnd == null
        ? null
        : ((barEnd.difference(barStart).inDays + 1) * dayWidth - 2).clamp(
            4.0,
            timelineWidth - left!,
          );

    return SizedBox(
      height: height,
      child: Row(
        children: [
          SizedBox(
            width: 170,
            child: Padding(
              padding: EdgeInsets.only(left: indent ? 18 : 2),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (labelStyle ?? const TextStyle()).copyWith(
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
          SizedBox(
            width: timelineWidth,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    height: height - 6,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: CardoryColors.gray100,
                          width: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                if (left != null && width != null)
                  Positioned(
                    left: left,
                    top: (height - 16) / 2,
                    child: GestureDetector(
                      onTap: onTap,
                      child: Tooltip(
                        message:
                            '$label（${formatDate(start!)} ~ ${formatDate(end!)}）',
                        child: Container(
                          width: width,
                          height: 16,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  )
                else if (left != null)
                  Positioned(
                    left: left,
                    top: (height - 10) / 2,
                    child: Tooltip(
                      message: '$label（仅截止 ${formatDate(start!)}）',
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                for (final marker in markers)
                  Positioned(
                    left:
                        (marker.day.difference(windowStart).inDays * dayWidth +
                                dayWidth / 2 -
                                5)
                            .clamp(0.0, timelineWidth - 12),
                    top: 2,
                    child: Tooltip(
                      message: '◆ ${marker.label}',
                      child: Text(
                        '◆',
                        style: TextStyle(
                          fontSize: 10,
                          color: marker.color,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
