// 新建系统日程对话框：标题 + 起止时间 + 备注，返回 [SystemEventDraft]。

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';

/// 新建系统日程的输入结果。
class SystemEventDraft {
  const SystemEventDraft({
    required this.title,
    required this.start,
    required this.end,
    this.note = '',
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String note;
}

/// 新建系统日程对话框（移动端写系统日历，桌面端由调用方落 .ics 文件）。
class SystemEventDialog extends StatefulWidget {
  const SystemEventDialog({super.key, required this.initialDay});

  final DateTime initialDay;

  @override
  State<SystemEventDialog> createState() => _SystemEventDialogState();
}

class _SystemEventDialogState extends State<SystemEventDialog> {
  late final TextEditingController _titleController = TextEditingController();
  late final TextEditingController _noteController = TextEditingController();
  late int _startMinutes = 9 * 60;
  late int _durationMinutes = 60;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool start}) async {
    final base = start ? _startMinutes : _startMinutes + _durationMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (base ~/ 60) % 24, minute: base % 60),
    );
    if (picked == null || !mounted) return;
    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      if (start) {
        _startMinutes = minutes;
        if (_durationMinutes <= 0) _durationMinutes = 60;
      } else {
        _durationMinutes = minutes - _startMinutes;
        if (_durationMinutes <= 0) _durationMinutes += 24 * 60;
      }
    });
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请填写日程标题。')));
      return;
    }
    final day = widget.initialDay;
    final start = DateTime(
      day.year,
      day.month,
      day.day,
      _startMinutes ~/ 60,
      _startMinutes % 60,
    );
    final end = start.add(Duration(minutes: _durationMinutes));
    Navigator.of(context).pop(
      SystemEventDraft(
        title: title,
        start: start,
        end: end,
        note: _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新建日程'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: '日程标题'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(start: true),
                  child: Text(
                    '开始 ${_startMinutes ~/ 60}:${(_startMinutes % 60).toString().padLeft(2, '0')}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickTime(start: false),
                  child: Text(
                    '结束 ${(_startMinutes + _durationMinutes) ~/ 60 % 24}:${(_startMinutes + _durationMinutes) % 60}',
                  ),
                ),
              ),
            ],
          ),
          Text(
            '日期：${formatDate(widget.initialDay)} · 时长 $_durationMinutes 分钟',
            style: TextStyle(fontSize: 12, color: CardoryColors.gray500),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(labelText: '备注（可选）'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('保存')),
    ],
  );
}
