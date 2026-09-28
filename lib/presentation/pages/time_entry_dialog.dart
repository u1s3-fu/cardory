// 手动新增 / 编辑时间记录对话框。

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../../domain/time_models.dart';
import '../cardory_theme.dart';
import 'time_cards.dart' show formatDuration;

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
