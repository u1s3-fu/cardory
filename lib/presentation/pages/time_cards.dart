// 时间页四张卡片：番茄钟、专注计时、耗时统计与时间记录（含共享壳与格式化）。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/cardory_models.dart';
import '../../domain/time_models.dart';
import '../cardory_theme.dart';
import '../widgets/section_title.dart';

/// 秒数 → `h:mm:ss` / `mm:ss` 展示格式。
String formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

/// 时间页卡片统一壳：内边距 + cardDecoration。
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: cardDecoration(),
    child: child,
  );
}

/// 番茄钟卡片：预置模式 + 自定义时长，运行中显示倒计时。
class PomodoroCard extends StatelessWidget {
  const PomodoroCard({
    super.key,
    required this.modes,
    required this.running,
    required this.now,
    required this.projects,
    required this.onStart,
    required this.onFinish,
    required this.onAbort,
  });

  final List<(String, String, int)> modes;
  final PomodoroSessionData? running;
  final DateTime now;
  final List<ProjectData> projects;
  final Future<void> Function(String mode, int plannedSeconds) onStart;
  final Future<void> Function(PomodoroSessionData session) onFinish;
  final Future<void> Function(PomodoroSessionData session) onAbort;

  @override
  Widget build(BuildContext context) {
    final session = running;
    String? modeLabel;
    if (session != null) {
      for (final (mode, label, _) in modes) {
        if (mode == session.mode) modeLabel = label;
      }
      modeLabel ??= switch (session.mode) {
        'custom' => '自定义',
        _ => session.mode,
      };
    }
    final remaining = session == null
        ? null
        : session.plannedSeconds - now.difference(session.startedAt).inSeconds;
    String? projectTitle;
    if (session?.projectId != null) {
      for (final project in projects) {
        if (project.id == session!.projectId) projectTitle = project.title;
      }
    }
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '番茄钟', subtitle: '完成一个专注循环后自动记入时间统计'),
          const SizedBox(height: 16),
          if (session == null) ...[
            for (final (mode, label, seconds) in modes)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$label · ${seconds ~/ 60} 分钟',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: CardoryColors.gray700,
                        ),
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () => onStart(mode, seconds),
                      child: const Text('开始'),
                    ),
                  ],
                ),
              ),
            _CustomPomodoroRow(onStart: onStart),
          ] else ...[
            Center(
              child: Column(
                children: [
                  Text(
                    '$modeLabel ${remaining == null
                        ? ''
                        : remaining <= 0
                        ? '（已完成）'
                        : ''}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CardoryColors.gray600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatDuration(
                      remaining == null
                          ? 0
                          : remaining < 0
                          ? 0
                          : remaining,
                    ),
                    style: TextStyle(
                      fontSize: 46,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                      color: CardoryColors.gray900,
                    ),
                  ),
                  if (projectTitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      projectTitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: CardoryColors.gray500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (remaining != null && remaining > 0)
                    OutlinedButton(
                      onPressed: () => onAbort(session),
                      child: const Text('提前结束'),
                    )
                  else
                    FilledButton(
                      onPressed: () => onFinish(session),
                      child: const Text('完成收尾'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 专注计时卡片：开始 / 暂停 / 结束，全程墙钟计时。
class TimerCard extends StatelessWidget {
  const TimerCard({
    super.key,
    required this.running,
    required this.accumulatedSeconds,
    required this.now,
    required this.onStart,
    required this.onPause,
    required this.onFinish,
  });

  final TimeEntryData? running;
  final int accumulatedSeconds;
  final DateTime now;
  final Future<void> Function() onStart;
  final Future<void> Function() onPause;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    final current = running == null
        ? 0
        : now.difference(running!.startedAt).inSeconds;
    final total = accumulatedSeconds + current;
    final isRunning = running != null;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '专注计时', subtitle: '开始 / 暂停 / 结束，全程墙钟计时'),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                Text(
                  formatDuration(total),
                  style: TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1,
                    color: isRunning
                        ? CardoryColors.gray900
                        : CardoryColors.gray500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isRunning
                      ? '计时中'
                      : accumulatedSeconds > 0
                      ? '已暂停'
                      : '未开始',
                  style: TextStyle(fontSize: 12, color: CardoryColors.gray500),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!isRunning)
                      FilledButton.icon(
                        onPressed: onStart,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(accumulatedSeconds > 0 ? '继续' : '开始'),
                      )
                    else
                      FilledButton.tonal(
                        onPressed: onPause,
                        child: const Text('暂停'),
                      ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: total > 0 ? onFinish : null,
                      child: const Text('结束并记录'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 耗时统计卡片：今日/本周专注与项目耗时 Top 5。
class StatsCard extends StatelessWidget {
  const StatsCard({
    super.key,
    required this.todaySeconds,
    required this.weekSeconds,
    required this.projectTotals,
  });

  final int todaySeconds;
  final int weekSeconds;
  final List<(String, int)> projectTotals;

  @override
  Widget build(BuildContext context) {
    final maxTotal = projectTotals.isEmpty ? 1 : projectTotals.first.$2;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '耗时统计', subtitle: '按时间记录汇总'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatTile(label: '今日专注', seconds: todaySeconds),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(label: '本周专注', seconds: weekSeconds),
              ),
            ],
          ),
          if (projectTotals.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final (title, seconds) in projectTotals)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: CardoryColors.gray700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: seconds / maxTotal,
                          minHeight: 8,
                          backgroundColor: CardoryColors.gray100,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 64,
                      child: Text(
                        '${(seconds / 60).toStringAsFixed(0)} 分',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          color: CardoryColors.gray500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.seconds});

  final String label;
  final int seconds;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: CardoryColors.gray50,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: CardoryColors.gray500),
        ),
        const SizedBox(height: 4),
        Text(
          '${(seconds / 60).toStringAsFixed(0)} 分钟',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: CardoryColors.gray900,
          ),
        ),
      ],
    ),
  );
}

/// 时间记录清单卡片：手动补记与自动记录。
class EntriesCard extends StatelessWidget {
  const EntriesCard({
    super.key,
    required this.entries,
    required this.projects,
    required this.now,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<TimeEntryData> entries;
  final List<ProjectData> projects;
  final DateTime now;
  final VoidCallback onAdd;
  final Future<void> Function(TimeEntryData entry) onEdit;
  final Future<void> Function(TimeEntryData entry) onDelete;

  String _projectTitle(String? projectId) {
    if (projectId == null) return '';
    for (final project in projects) {
      if (project.id == projectId) return project.title;
    }
    return '';
  }

  String _sourceLabel(String source) => switch (source) {
    'pomodoro' => '番茄钟',
    'timer' => '计时器',
    _ => '手动',
  };

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: SectionTitle(title: '时间记录', subtitle: '手动补记与自动记录'),
            ),
            IconButton(
              tooltip: '新增记录',
              onPressed: onAdd,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '还没有时间记录，点击右上角新增。',
              style: TextStyle(fontSize: 13, color: CardoryColors.gray500),
            ),
          )
        else
          for (final entry in entries.take(20))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onEdit(entry),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: CardoryColors.primarySoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _sourceLabel(entry.source),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: CardoryColors.gray700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.note.isEmpty
                                  ? '${formatDate(entry.startedAt)} ${entry.startedAt.hour.toString().padLeft(2, '0')}:${entry.startedAt.minute.toString().padLeft(2, '0')}'
                                  : entry.note,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: CardoryColors.gray900,
                              ),
                            ),
                            if (_projectTitle(entry.projectId).isNotEmpty)
                              Text(
                                _projectTitle(entry.projectId),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: CardoryColors.gray400,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        entry.isRunning
                            ? '计时中'
                            : formatDuration(entry.durationSeconds),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: CardoryColors.gray600,
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: IconButton(
                          tooltip: '删除记录',
                          icon: Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: CardoryColors.gray400,
                          ),
                          onPressed: () => onDelete(entry),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    ),
  );
}

/// 自定义番茄钟时长输入（分钟）。
class _CustomPomodoroRow extends StatefulWidget {
  const _CustomPomodoroRow({required this.onStart});

  final Future<void> Function(String mode, int plannedSeconds) onStart;

  @override
  State<_CustomPomodoroRow> createState() => _CustomPomodoroRowState();
}

class _CustomPomodoroRowState extends State<_CustomPomodoroRow> {
  late final TextEditingController _minutesController = TextEditingController(
    text: '40',
  );

  @override
  void dispose() {
    _minutesController.dispose();
    super.dispose();
  }

  void _start() {
    final minutes = int.tryParse(_minutesController.text.trim());
    if (minutes == null || minutes < 1 || minutes > 600) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入 1-600 之间的分钟数。')));
      return;
    }
    widget.onStart('custom', minutes * 60);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _minutesController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '自定义时长（分钟，1-600）',
              isDense: true,
            ),
            onSubmitted: (_) => _start(),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.tonal(onPressed: _start, child: const Text('开始')),
      ],
    ),
  );
}
