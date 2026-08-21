import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';

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
    final minimum = start ? DateTime(2000) : _startDate ?? DateTime(2000);
    final candidate = (start ? _startDate : _endDate) ?? DateTime.now();
    final initial = candidate.isBefore(minimum) ? minimum : candidate;
    final picked = await showDatePicker(
      context: context,
      firstDate: minimum,
      lastDate: DateTime(2100),
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
                    child: _DateField(
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
                    child: _DateField(
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
                      color: Theme.of(context).colorScheme.error,
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
    final minimum = start ? DateTime(2000) : _startDate ?? DateTime(2000);
    final candidate = (start ? _startDate : _endDate) ?? DateTime.now();
    final initial = candidate.isBefore(minimum) ? minimum : candidate;
    final picked = await showDatePicker(
      context: context,
      firstDate: minimum,
      lastDate: DateTime(2100),
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
    final startDateField = _DateField(
      label: '开始日期（可选）',
      value: _startDate,
      onTap: () => _pickDate(true),
      onClear: _startDate == null
          ? null
          : () => setState(() => _startDate = null),
    );
    final endDateField = _DateField(
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
                      color: Theme.of(context).colorScheme.error,
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

SubTodoData _createSubTodo(
  String content, {
  required bool recordCreatedAt,
  DateTime? reminderAt,
}) {
  return SubTodoData(
    id: newId(),
    content: content,
    done: false,
    createdAt: recordCreatedAt ? DateTime.now() : null,
    dueAt: reminderAt,
  );
}

Future<DateTime?> _showReminderDateTimePicker(
  BuildContext context,
  DateTime initial,
) async {
  final firstDate = DateTime(2000);
  final lastDate = DateTime(2100);
  final initialDate = initial.isBefore(firstDate)
      ? firstDate
      : initial.isAfter(lastDate)
      ? lastDate
      : initial;
  final date = await showDatePicker(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    initialDate: initialDate,
  );
  if (date == null || !context.mounted) return null;

  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

class QuickAddSubTodoDialog extends StatefulWidget {
  const QuickAddSubTodoDialog({super.key, required this.recordCreatedAt});

  final bool recordCreatedAt;

  @override
  State<QuickAddSubTodoDialog> createState() => _QuickAddSubTodoDialogState();
}

class _QuickAddSubTodoDialogState extends State<QuickAddSubTodoDialog> {
  final TextEditingController _content = TextEditingController();
  DateTime? _reminderAt;
  String? _error;

  Future<void> _pickReminderAt() async {
    final selected = await _showReminderDateTimePicker(
      context,
      _reminderAt ?? DateTime.now(),
    );
    if (selected == null || !mounted) return;
    setState(() => _reminderAt = selected);
  }

  void _submit() {
    final content = _content.text.trim();
    if (content.isEmpty) {
      setState(() => _error = '请输入子提醒内容。');
      return;
    }
    Navigator.pop(
      context,
      _createSubTodo(
        content,
        recordCreatedAt: widget.recordCreatedAt,
        reminderAt: _reminderAt,
      ),
    );
  }

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('快捷添加子提醒'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('quick-add-subtodo-content'),
            controller: _content,
            autofocus: true,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: '子提醒内容',
              hintText: '输入内容，支持换行',
              alignLabelWithHint: true,
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('quick-add-subtodo-reminder-time'),
                  onPressed: _pickReminderAt,
                  icon: Icon(
                    _reminderAt == null
                        ? Icons.alarm_add_outlined
                        : Icons.edit_calendar_outlined,
                  ),
                  label: Text(
                    _reminderAt == null
                        ? '设置提醒时间'
                        : '提醒 ${formatDateTime(_reminderAt!)}',
                  ),
                ),
              ),
              if (_reminderAt != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '清除提醒时间',
                  onPressed: () => setState(() => _reminderAt = null),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton.icon(
        onPressed: _submit,
        icon: const Icon(Icons.add_rounded),
        label: const Text('添加'),
      ),
    ],
  );
}

class SubTodoManagerDialog extends StatefulWidget {
  const SubTodoManagerDialog({
    super.key,
    required this.initialSubTodos,
    this.recordCreatedAt = false,
  });

  final List<SubTodoData> initialSubTodos;
  final bool recordCreatedAt;

  @override
  State<SubTodoManagerDialog> createState() => _SubTodoManagerDialogState();
}

class _SubTodoManagerDialogState extends State<SubTodoManagerDialog> {
  late final List<SubTodoData> _subTodos = List.of(widget.initialSubTodos);
  final TextEditingController _newSubTodoContent = TextEditingController();
  final FocusNode _newSubTodoContentFocus = FocusNode();
  String? _addError;

  void _addSubTodo() {
    final content = _newSubTodoContent.text.trim();
    if (content.isEmpty) {
      setState(() => _addError = '请输入子任务内容。');
      return;
    }
    setState(() {
      _subTodos.add(
        _createSubTodo(content, recordCreatedAt: widget.recordCreatedAt),
      );
      _newSubTodoContent.clear();
      _addError = null;
    });
    _newSubTodoContentFocus.requestFocus();
  }

  Future<void> _toggleDueAt(int index, bool enabled) async {
    if (!enabled) {
      setState(
        () => _subTodos[index] = _subTodos[index].copyWith(clearDueAt: true),
      );
      return;
    }
    final current = _subTodos[index].dueAt ?? DateTime.now();
    final reminderAt = await _showReminderDateTimePicker(context, current);
    if (reminderAt == null || !mounted) return;
    setState(() {
      _subTodos[index] = _subTodos[index].copyWith(dueAt: reminderAt);
    });
  }

  Future<void> _changeDueAt(int index) async {
    await _toggleDueAt(index, true);
  }

  Future<void> _editSubTodo(SubTodoData subTodo) async {
    final controller = TextEditingController(text: subTodo.content);
    final content = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑子待办'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(
            labelText: '内容 *',
            alignLabelWithHint: true,
          ),
          minLines: 4,
          maxLines: 10,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(context, value);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (content == null || !mounted) return;
    setState(() {
      final index = _subTodos.indexWhere((item) => item.id == subTodo.id);
      if (index >= 0) _subTodos[index] = subTodo.copyWith(content: content);
    });
  }

  @override
  void dispose() {
    _newSubTodoContent.dispose();
    _newSubTodoContentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('管理子待办'),
    content: SizedBox(
      width: 680,
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _newSubTodoContent,
                  focusNode: _newSubTodoContentFocus,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: '子任务内容',
                    hintText: '输入内容，支持换行',
                    alignLabelWithHint: true,
                    errorText: _addError,
                  ),
                  onChanged: (_) {
                    if (_addError != null) setState(() => _addError = null);
                  },
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _addSubTodo,
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _subTodos.isEmpty
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.account_tree_outlined, size: 42),
                      SizedBox(height: 10),
                      Text('暂无子待办'),
                    ],
                  )
                : ListView.separated(
                    itemCount: _subTodos.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _subTodos[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 4, 6, 6),
                          child: Column(
                            children: [
                              ListTile(
                                leading: IconButton(
                                  tooltip: item.done ? '标记未完成' : '标记完成',
                                  onPressed: () => setState(
                                    () => _subTodos[index] = item.copyWith(
                                      done: !item.done,
                                    ),
                                  ),
                                  icon: Icon(
                                    item.done
                                        ? Icons.check_circle_rounded
                                        : Icons.radio_button_unchecked_rounded,
                                    color: item.done
                                        ? CardoryColors.success
                                        : CardoryColors.gray400,
                                  ),
                                ),
                                title: Text(
                                  item.content,
                                  style: TextStyle(
                                    decoration: item.done
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                subtitle: item.createdAt == null
                                    ? null
                                    : Text(
                                        '添加于 ${formatDateTime(item.createdAt!)}',
                                      ),
                                onTap: () => _editSubTodo(item),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: '编辑',
                                      onPressed: () => _editSubTodo(item),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                    IconButton(
                                      tooltip: '删除',
                                      onPressed: () => setState(
                                        () => _subTodos.removeAt(index),
                                      ),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.schedule_rounded,
                                      size: 18,
                                      color: CardoryColors.gray500,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('提醒时间'),
                                          if (item.dueAt == null)
                                            Text(
                                              '未设置',
                                              style: TextStyle(
                                                color: CardoryColors.gray400,
                                                fontSize: 11.5,
                                              ),
                                            )
                                          else
                                            InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              onTap: () => _changeDueAt(index),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 3,
                                                    ),
                                                child: Text(
                                                  formatDateTime(item.dueAt!),
                                                  style: TextStyle(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Switch.adaptive(
                                      value: item.dueAt != null,
                                      onChanged: (value) =>
                                          _toggleDueAt(index, value),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, List<SubTodoData>.of(_subTodos)),
        child: const Text('完成'),
      ),
    ],
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
          suffixIcon: onClear == null
              ? null
              : IconButton(
                  tooltip: '清除日期',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
        ),
        child: Text(
          value == null ? '未设置' : formatDate(value!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ),
  );
}
