// 甘特页对话框：里程碑新增/编辑与任务依赖新增。

import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../../domain/milestone_models.dart';
import '../cardory_theme.dart';

/// 新增 / 编辑里程碑。
class MilestoneDialog extends StatefulWidget {
  const MilestoneDialog({
    super.key,
    required this.projects,
    required this.now,
    this.milestone,
  });

  final List<ProjectData> projects;
  final MilestoneData? milestone;
  final DateTime now;

  @override
  State<MilestoneDialog> createState() => _MilestoneDialogState();
}

class _MilestoneDialogState extends State<MilestoneDialog> {
  late String? _projectId = widget.milestone?.projectId;
  late final TextEditingController _titleController = TextEditingController(
    text: widget.milestone?.title ?? '',
  );
  late final TextEditingController _noteController = TextEditingController(
    text: widget.milestone?.note ?? '',
  );
  late DateTime _dueAt = widget.milestone?.dueAt ?? widget.now;

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueAt,
      firstDate: minPickerDate,
      lastDate: maxPickerDate,
    );
    if (picked != null) setState(() => _dueAt = picked);
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty || _projectId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择项目并填写里程碑名称。')));
      return;
    }
    Navigator.of(context).pop(
      (widget.milestone ??
              MilestoneData(
                id: '',
                projectId: _projectId!,
                title: title,
                dueAt: _dueAt,
              ))
          .copyWith(
            title: title,
            dueAt: _dueAt,
            note: _noteController.text.trim(),
          ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.milestone == null ? '新增里程碑' : '编辑里程碑'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _projectId,
            decoration: const InputDecoration(labelText: '所属项目'),
            items: [
              for (final project in widget.projects)
                DropdownMenuItem(value: project.id, child: Text(project.title)),
            ],
            onChanged: (value) => setState(() => _projectId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: '里程碑名称'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '目标日期 ${formatDate(_dueAt)}',
                style: TextStyle(fontSize: 13, color: CardoryColors.gray700),
              ),
              const Spacer(),
              TextButton(onPressed: _pickDate, child: const Text('选择日期')),
            ],
          ),
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

/// 新增任务依赖：选择前置与后继任务。
class DependencyDialog extends StatefulWidget {
  const DependencyDialog({super.key, required this.todos});

  final List<TodoData> todos;

  @override
  State<DependencyDialog> createState() => _DependencyDialogState();
}

class _DependencyDialogState extends State<DependencyDialog> {
  String? _predecessorId;
  String? _successorId;

  void _submit() {
    if (_predecessorId == null || _successorId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请选择前置与后继任务。')));
      return;
    }
    Navigator.of(context).pop((_predecessorId!, _successorId!));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('新增任务依赖'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _predecessorId,
            decoration: const InputDecoration(labelText: '前置任务（先完成）'),
            items: [
              for (final todo in widget.todos)
                DropdownMenuItem(value: todo.id, child: Text(todo.title)),
            ],
            onChanged: (value) => setState(() => _predecessorId = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _successorId,
            decoration: const InputDecoration(labelText: '后继任务（后开始）'),
            items: [
              for (final todo in widget.todos)
                DropdownMenuItem(value: todo.id, child: Text(todo.title)),
            ],
            onChanged: (value) => setState(() => _successorId = value),
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
