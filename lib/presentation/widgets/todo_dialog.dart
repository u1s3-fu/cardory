import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import 'date_field.dart';
import 'subtodo_dialogs.dart';

/// 待办创建 / 编辑对话框：返回 [TodoData]（新建或编辑后）。
class TodoDialog extends StatefulWidget {
  const TodoDialog({
    super.key,
    required this.projects,
    this.todo,
    this.initialProject,
    this.recordSubTodoCreatedAt = false,
  });

  final List<ProjectData> projects;
  final TodoData? todo;
  final ProjectData? initialProject;
  final bool recordSubTodoCreatedAt;

  @override
  State<TodoDialog> createState() => _TodoDialogState();
}

class _TodoDialogState extends State<TodoDialog> {
  late final _title = TextEditingController(text: widget.todo?.title ?? '');
  late final _description = TextEditingController(
    text: widget.todo?.description ?? '',
  );
  late List<SubTodoData> _subTodos = List.of(widget.todo?.subTodos ?? const []);
  late ProjectData? _project = widget.todo == null
      ? widget.initialProject
      : widget.projects
            .where((p) => p.id == widget.todo!.projectId)
            .firstOrNull;
  late ProjectPriority _priority = widget.todo?.priority ?? ProjectPriority.p2;
  late DateTime? _startDate = widget.todo?.startDate;
  late DateTime? _endDate = widget.todo?.endDate;
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

  Future<void> _manageSubTodos() async {
    final result = await showDialog<List<SubTodoData>>(
      context: context,
      builder: (_) => SubTodoManagerDialog(
        initialSubTodos: _subTodos,
        recordCreatedAt: widget.recordSubTodoCreatedAt,
      ),
    );
    if (result != null && mounted) setState(() => _subTodos = result);
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final startDateField = DateField(
      label: '开始日期（可选）',
      value: _startDate,
      onTap: () => _pickDate(true),
      onClear: _startDate == null
          ? null
          : () => setState(() => _startDate = null),
    );
    final endDateField = DateField(
      label: '截止日期（可选）',
      value: _endDate,
      onTap: () => _pickDate(false),
      onClear: _endDate == null ? null : () => setState(() => _endDate = null),
    );
    final useVerticalDateLayout = MediaQuery.sizeOf(context).width < 600;
    return AlertDialog(
      title: Text(widget.todo == null ? '新建待办' : '待办详情 / 编辑'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * 0.68,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                autofocus: widget.todo == null,
                decoration: const InputDecoration(labelText: '待办标题 *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '详细说明'),
              ),
              const SizedBox(height: 12),
              if (useVerticalDateLayout)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    startDateField,
                    const SizedBox(height: 8),
                    endDateField,
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(child: startDateField),
                    const SizedBox(width: 10),
                    Expanded(child: endDateField),
                  ],
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ProjectData?>(
                initialValue: _project,
                decoration: const InputDecoration(labelText: '关联项目'),
                items: [
                  const DropdownMenuItem<ProjectData?>(
                    value: null,
                    child: Text('未关联项目'),
                  ),
                  ...widget.projects.map(
                    (p) => DropdownMenuItem<ProjectData?>(
                      value: p,
                      child: Text(p.title),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _project = v),
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
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: CardoryColors.gray300),
                ),
                leading: const Icon(Icons.account_tree_outlined),
                title: const Text('子待办'),
                subtitle: Text(
                  _subTodos.isEmpty
                      ? '未添加，点击打开弹窗管理'
                      : '共 ${_subTodos.length} 项，已完成 ${_subTodos.where((item) => item.done).length} 项',
                ),
                trailing: const Icon(Icons.open_in_new_rounded, size: 19),
                onTap: _manageSubTodos,
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
              setState(() => _error = '请输入待办标题。');
              return;
            }
            if (_startDate != null &&
                _endDate != null &&
                _endDate!.isBefore(_startDate!)) {
              setState(() => _error = '截止日期不能早于开始日期。');
              return;
            }
            Navigator.pop(
              context,
              TodoData(
                id: widget.todo?.id ?? newId(),
                title: _title.text.trim(),
                description: _description.text.trim(),
                startDate: _startDate,
                endDate: _endDate,
                projectId: _project?.id ?? '',
                projectTitle: _project?.title ?? '未关联项目',
                priority: _priority,
                done: widget.todo?.done ?? false,
                subTodos: _subTodos,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
