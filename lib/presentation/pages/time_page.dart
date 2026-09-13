// 时间与番茄钟页面：专注计时、番茄钟、手动时间记录 CRUD 与耗时统计。
//
// 后台计时语义：所有进行中的时长都从墙钟（startedAt）推算而非本地累加，
// 应用切后台/关屏后时间仍然准确；进行中的番茄钟会话只存在于本地库，
// 不进入同步通道（见 TimeTrackingStore 契约）。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/time_tracking_store.dart';
import '../../domain/cardory_models.dart';
import '../../domain/schedule_queries.dart';
import '../../domain/time_models.dart';
import '../cardory_theme.dart';
import '../widgets/confirm_dialogs.dart';
import '../widgets/section_title.dart';

class TimePage extends StatefulWidget {
  const TimePage({
    super.key,
    required this.store,
    required this.projects,
    this.now,
  });

  final TimeTrackingStore store;
  final List<ProjectData> projects;

  /// 当前时间（测试可注入固定值）。
  final DateTime? now;

  @override
  State<TimePage> createState() => _TimePageState();
}

class _TimePageState extends State<TimePage> {
  static const _pomodoroModes = <(String, String, int)>[
    ('focus', '专注', 25 * 60),
    ('shortBreak', '短休', 5 * 60),
    ('longBreak', '长休', 15 * 60),
  ];

  List<TimeEntryData> _entries = [];
  PomodoroSessionData? _runningSession;
  TimeEntryData? _runningTimer;
  int _accumulatedSeconds = 0;
  Timer? _ticker;
  bool _loading = true;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _restore() async {
    final entries = await widget.store.loadEntries(limit: 100);
    final open = await widget.store.loadOpenEntries();
    final running = await widget.store.loadRunningSession();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _runningSession = running;
      _runningTimer = open.where((entry) => entry.source != 'manual').isEmpty
          ? null
          : open.where((entry) => entry.source != 'manual').first;
      _loading = false;
    });
    // 应用重启后恢复：进行中会话已超过计划时长则按计划收尾。
    if (_runningSession != null) {
      final elapsed = _now.difference(_runningSession!.startedAt).inSeconds;
      if (elapsed >= _runningSession!.plannedSeconds) {
        await _completePomodoro(_runningSession!);
      }
    }
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // 墙钟驱动的重绘：后台返回后显示立即正确。
      if (_runningSession != null || _runningTimer != null) {
        setState(() {});
        final session = _runningSession;
        if (session != null &&
            _now.difference(session.startedAt).inSeconds >=
                session.plannedSeconds) {
          _completePomodoro(session);
        }
      }
    });
  }

  // ---- 番茄钟 ----

  Future<void> _startPomodoro(String mode, int plannedSeconds) async {
    final session = await widget.store.startSession(
      mode: mode,
      plannedSeconds: plannedSeconds,
      startedAt: _now,
    );
    setState(() => _runningSession = session);
  }

  Future<void> _completePomodoro(PomodoroSessionData session) async {
    final plannedEnd = session.startedAt.add(
      Duration(seconds: session.plannedSeconds),
    );
    final endedAt = _now.isBefore(plannedEnd) ? _now : plannedEnd;
    final elapsed = endedAt.difference(session.startedAt).inSeconds;
    await widget.store.finishSession(
      session.id,
      completed: elapsed >= session.plannedSeconds,
      actualSeconds: elapsed,
      endedAt: endedAt,
    );
    // 完成的专注会话同时写入 time_entries，供统计与同步。
    if (session.mode == 'focus' && elapsed > 0) {
      await widget.store.createEntry(
        startedAt: session.startedAt,
        endedAt: endedAt,
        source: 'pomodoro',
        projectId: session.projectId,
        taskId: session.taskId,
        note: '番茄钟专注',
      );
    }
    if (!mounted) return;
    setState(() => _runningSession = null);
    await _refreshEntries();
  }

  Future<void> _abortPomodoro(PomodoroSessionData session) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '结束番茄钟',
      content: '本次会话尚未完成，提前结束将记为中断。确定结束吗？',
      confirmLabel: '结束',
    );
    if (confirmed != true || !mounted) return;
    final elapsed = _now.difference(session.startedAt).inSeconds;
    await widget.store.finishSession(
      session.id,
      completed: false,
      actualSeconds: elapsed > 0 ? elapsed : 0,
      endedAt: _now,
    );
    if (!mounted) return;
    setState(() => _runningSession = null);
  }

  // ---- 专注计时器 ----

  Future<void> _startTimer() async {
    final entry = await widget.store.startEntry(source: 'timer');
    setState(() {
      _runningTimer = entry;
      _accumulatedSeconds = 0;
    });
  }

  /// 暂停：闭合当前区间，累计时长，等待继续或结束。
  Future<void> _pauseTimer() async {
    final running = _runningTimer;
    if (running == null) return;
    final stopped = await widget.store.stopEntry(running.id, endedAt: _now);
    setState(() {
      _accumulatedSeconds += stopped.durationSeconds;
      _runningTimer = null;
    });
    await _refreshEntries();
  }

  Future<void> _finishTimer() async {
    if (_runningTimer != null) await _pauseTimer();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('本次专注 ${formatDuration(_accumulatedSeconds)} 已记录。'),
      ),
    );
    setState(() => _accumulatedSeconds = 0);
  }

  Future<void> _refreshEntries() async {
    final entries = await widget.store.loadEntries(limit: 100);
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  // ---- 统计 ----

  int get _todaySeconds {
    final today = localDayKey(_now);
    var total = 0;
    for (final entry in _entries) {
      if (entry.isRunning) continue;
      if (localDayKey(entry.startedAt) == today) {
        total += entry.durationSeconds;
      }
    }
    return total;
  }

  int get _weekSeconds {
    final (start, end) = calendarRangeBounds(CalendarRange.week, _now);
    var total = 0;
    for (final entry in _entries) {
      if (entry.isRunning) continue;
      final day = localDayKey(entry.startedAt);
      if (!day.isBefore(start) && !day.isAfter(end)) {
        total += entry.durationSeconds;
      }
    }
    return total;
  }

  List<(String, int)> get _projectTotals {
    final titles = {
      for (final project in widget.projects) project.id: project.title,
    };
    final totals = <String, int>{};
    for (final entry in _entries) {
      if (entry.isRunning || entry.projectId == null) continue;
      totals.update(
        titles[entry.projectId] ?? '未知项目',
        (value) => value + entry.durationSeconds,
        ifAbsent: () => entry.durationSeconds,
      );
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final entry in sorted.take(5)) (entry.key, entry.value)];
  }

  // ---- 手动记录 ----

  Future<void> _addManualEntry() async {
    final result = await showDialog<ManualEntryResult>(
      context: context,
      builder: (_) =>
          ManualTimeEntryDialog(projects: widget.projects, initialDay: _now),
    );
    if (result == null) return;
    await widget.store.createEntry(
      startedAt: result.startedAt,
      endedAt: result.endedAt,
      projectId: result.projectId,
      note: result.note,
    );
    await _refreshEntries();
  }

  Future<void> _editEntry(TimeEntryData entry) async {
    final result = await showDialog<ManualEntryResult>(
      context: context,
      builder: (_) => ManualTimeEntryDialog(
        projects: widget.projects,
        entry: entry,
        initialDay: entry.startedAt,
      ),
    );
    if (result == null) return;
    await widget.store.updateEntry(
      entry.copyWith(
        startedAt: result.startedAt,
        endedAt: result.endedAt,
        durationSeconds: result.endedAt.difference(result.startedAt).inSeconds,
        projectId: result.projectId,
        note: result.note,
      ),
    );
    await _refreshEntries();
  }

  Future<void> _deleteEntry(TimeEntryData entry) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除时间记录',
      content: '确定删除这条时间记录吗？',
      confirmLabel: '删除',
    );
    if (confirmed != true) return;
    await widget.store.deleteEntry(entry.id);
    await _refreshEntries();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1100;
    final pomodoroCard = _PomodoroCard(
      key: const Key('pomodoro-card'),
      modes: _pomodoroModes,
      running: _runningSession,
      now: _now,
      projects: widget.projects,
      onStart: _startPomodoro,
      onFinish: _completePomodoro,
      onAbort: _abortPomodoro,
    );
    final timerCard = _TimerCard(
      key: const Key('focus-timer-card'),
      running: _runningTimer,
      accumulatedSeconds: _accumulatedSeconds,
      now: _now,
      onStart: _startTimer,
      onPause: _pauseTimer,
      onFinish: _finishTimer,
    );
    final statsCard = _StatsCard(
      todaySeconds: _todaySeconds,
      weekSeconds: _weekSeconds,
      projectTotals: _projectTotals,
    );
    final entriesCard = _EntriesCard(
      entries: _entries,
      projects: widget.projects,
      now: _now,
      onAdd: _addManualEntry,
      onEdit: _editEntry,
      onDelete: _deleteEntry,
    );

    if (wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: pomodoroCard),
              const SizedBox(width: 16),
              Expanded(child: timerCard),
            ],
          ),
          const SizedBox(height: 16),
          statsCard,
          const SizedBox(height: 16),
          entriesCard,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pomodoroCard,
        const SizedBox(height: 16),
        timerCard,
        const SizedBox(height: 16),
        statsCard,
        const SizedBox(height: 16),
        entriesCard,
      ],
    );
  }
}

String formatDuration(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

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

class _PomodoroCard extends StatelessWidget {
  const _PomodoroCard({
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
      modeLabel ??= session.mode;
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

class _TimerCard extends StatelessWidget {
  const _TimerCard({
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

class _StatsCard extends StatelessWidget {
  const _StatsCard({
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

class _EntriesCard extends StatelessWidget {
  const _EntriesCard({
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

/// 手动时间记录的编辑结果。
class ManualEntryResult {
  const ManualEntryResult({
    required this.startedAt,
    required this.endedAt,
    this.projectId,
    this.note = '',
  });

  final DateTime startedAt;
  final DateTime endedAt;
  final String? projectId;
  final String note;
}

/// 手动新增 / 编辑时间记录对话框。
class ManualTimeEntryDialog extends StatefulWidget {
  const ManualTimeEntryDialog({
    super.key,
    required this.projects,
    this.entry,
    required this.initialDay,
  });

  final List<ProjectData> projects;
  final TimeEntryData? entry;
  final DateTime initialDay;

  @override
  State<ManualTimeEntryDialog> createState() => _ManualTimeEntryDialogState();
}

class _ManualTimeEntryDialogState extends State<ManualTimeEntryDialog> {
  late DateTime _startedAt =
      widget.entry?.startedAt ??
      DateTime(
        widget.initialDay.year,
        widget.initialDay.month,
        widget.initialDay.day,
        DateTime.now().hour - 1,
      );
  late DateTime _endedAt =
      widget.entry?.endedAt ??
      DateTime(
        widget.initialDay.year,
        widget.initialDay.month,
        widget.initialDay.day,
        DateTime.now().hour,
      );
  late final TextEditingController _noteController;

  String? _projectId;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.entry?.note ?? '');
    _projectId = widget.entry?.projectId;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool start}) async {
    final base = start ? _startedAt : _endedAt;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: minPickerDate,
      lastDate: maxPickerDate,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null || !mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      if (start) {
        _startedAt = picked;
        if (_endedAt.isBefore(picked)) _endedAt = picked;
      } else {
        _endedAt = picked;
      }
    });
  }

  void _submit(BuildContext context) {
    if (!_endedAt.isAfter(_startedAt)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('结束时间需要晚于开始时间。')));
      return;
    }
    Navigator.of(context).pop(
      ManualEntryResult(
        startedAt: _startedAt,
        endedAt: _endedAt,
        projectId: _projectId,
        note: _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.entry == null ? '新增时间记录' : '编辑时间记录'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(start: true),
                  child: Text(
                    '开始 ${_startedAt.hour.toString().padLeft(2, '0')}:${_startedAt.minute.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(start: false),
                  child: Text(
                    '结束 ${_endedAt.hour.toString().padLeft(2, '0')}:${_endedAt.minute.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
            ],
          ),
          Text(
            '${formatDate(_startedAt)} · 时长 ${formatDuration(_endedAt.difference(_startedAt).inSeconds)}',
            style: TextStyle(fontSize: 12, color: CardoryColors.gray500),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _projectId,
            decoration: const InputDecoration(labelText: '关联项目（可选）'),
            items: [
              const DropdownMenuItem(value: null, child: Text('不关联')),
              for (final project in widget.projects)
                DropdownMenuItem(value: project.id, child: Text(project.title)),
            ],
            onChanged: (value) => setState(() => _projectId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(labelText: '备注'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: () => _submit(context), child: const Text('保存')),
    ],
  );
}
