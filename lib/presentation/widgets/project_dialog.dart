import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import 'date_field.dart';

/// 项目创建 / 编辑对话框：返回 [ProjectData]（新建或编辑后）。
class ProjectDialog extends StatefulWidget {
  const ProjectDialog({super.key, this.project});

  final ProjectData? project;

  @override
  State<ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<ProjectDialog> {
  late final _title = TextEditingController(text: widget.project?.title ?? '');
  late final _description = TextEditingController(
    text: widget.project?.description ?? '',
  );
  late ProjectPriority _priority =
      widget.project?.priority ?? ProjectPriority.p2;
  late ProjectStage _stage = widget.project?.stage ?? ProjectStage.planned;
  late DateTime? _startDate = widget.project?.startDate;
  late DateTime? _endDate = widget.project?.endDate;
  String? _error;

  Future<void> _pickDate(bool start) async {
    final minimum = start ? minPickerDate : _startDate ?? minPickerDate;
    final candidate = (start ? _startDate : _endDate) ?? DateTime.now();
    final initial = candidate.isBefore(minimum) ? minimum : candidate;
    final picked = await showDatePicker(
      context: context,
      firstDate: minimum,
      lastDate: maxPickerDate,
      initialDate: initial,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
      _error = null;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.project == null ? '新建项目' : '编辑项目'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.68,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: '项目名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '项目说明'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DateField(
                      label: '开始日期（可选）',
                      value: _startDate,
                      onTap: () => _pickDate(true),
                      onClear: _startDate == null
                          ? null
                          : () => setState(() => _startDate = null),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DateField(
                      label: '结束日期（可选）',
                      value: _endDate,
                      onTap: () => _pickDate(false),
                      onClear: _endDate == null
                          ? null
                          : () => setState(() => _endDate = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ProjectPriority>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: '优先级'),
                items: ProjectPriority.values
                    .map(
                      (p) => DropdownMenuItem(value: p, child: Text(p.label)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _priority = v ?? _priority),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ProjectStage>(
                initialValue: _stage,
                decoration: const InputDecoration(labelText: '阶段'),
                items: ProjectStage.values
                    .map(
                      (s) => DropdownMenuItem(value: s, child: Text(s.label)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _stage = v ?? _stage),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: cardoryEnsureWhiteContrast(CardoryColors.error),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) {
              setState(() => _error = '请输入项目名称。');
              return;
            }
            if (_startDate != null &&
                _endDate != null &&
                _endDate!.isBefore(_startDate!)) {
              setState(() => _error = '结束日期不能早于开始日期。');
              return;
            }
            Navigator.pop(
              context,
              ProjectData(
                id: widget.project?.id ?? newId(),
                title: _title.text.trim(),
                description: _description.text.trim(),
                startDate: _startDate,
                endDate: _endDate,
                priority: _priority,
                stage: _stage,
                progressEntries: widget.project?.progressEntries ?? const [],
                attachments: widget.project?.attachments ?? const [],
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
