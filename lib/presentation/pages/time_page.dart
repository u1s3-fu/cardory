// 时间与番茄钟页面：专注计时、番茄钟、手动时间记录 CRUD 与耗时统计。
//
// 后台计时语义：所有进行中的时长都从墙钟（startedAt）推算而非本地累加，
// 应用切后台/关屏后时间仍然准确；进行中的番茄钟会话只存在于本地库，
// 不进入同步通道（见 TimeTrackingStore 契约）。
//
// 卡片与对话框拆分在同目录：time_cards / time_entry_dialog；
// 此处 re-export 公共类型以保持旧导入路径兼容。

import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/time_tracking_store.dart';
import '../../domain/cardory_models.dart';
import '../../domain/schedule_queries.dart';
import '../../domain/time_models.dart';
import '../widgets/confirm_dialogs.dart';
import 'time_cards.dart';
import 'time_entry_dialog.dart';

export 'time_cards.dart' show formatDuration;
export 'time_entry_dialog.dart' show ManualEntryResult, ManualTimeEntryDialog;

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
    final pomodoroCard = PomodoroCard(
      key: const Key('pomodoro-card'),
      modes: _pomodoroModes,
      running: _runningSession,
      now: _now,
      projects: widget.projects,
      onStart: _startPomodoro,
      onFinish: _completePomodoro,
      onAbort: _abortPomodoro,
    );
    final timerCard = TimerCard(
      key: const Key('focus-timer-card'),
      running: _runningTimer,
      accumulatedSeconds: _accumulatedSeconds,
      now: _now,
      onStart: _startTimer,
      onPause: _pauseTimer,
      onFinish: _finishTimer,
    );
    final statsCard = StatsCard(
      todaySeconds: _todaySeconds,
      weekSeconds: _weekSeconds,
      projectTotals: _projectTotals,
    );
    final entriesCard = EntriesCard(
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
