import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../cardory_theme.dart';
import 'confirm_dialogs.dart';

/// 快捷添加子提醒对话框：直接返回新建的 [SubTodoData]。
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

/// 子待办管理对话框：新增 / 编辑 / 删除 / 完成子待办，返回修改后的列表。
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
    final content = await showTextInputDialog(
      context,
      title: '编辑子待办',
      initialValue: subTodo.content,
      labelText: '内容 *',
      minLines: 4,
      maxLines: 10,
      disallowEmpty: true,
      alignLabelWithHint: true,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
    );
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
                        key: ValueKey('subtodo-${item.id}'),
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
                                                color: CardoryColors.gray500,
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

/// 创建子待办数据。
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

/// 弹出日期 + 时间选择器，返回组合后的时间。
Future<DateTime?> _showReminderDateTimePicker(
  BuildContext context,
  DateTime initial,
) async {
  final firstDate = minPickerDate;
  final lastDate = maxPickerDate;
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
