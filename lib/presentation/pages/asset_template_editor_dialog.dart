import 'package:flutter/material.dart';

import '../../domain/asset_template.dart';
import '../../domain/cardory_utils.dart';

/// 自定义资产模板编辑器：新建或编辑非内置模板。
///
/// 保存后经 Navigator.pop 返回 [AssetTemplate]（取消返回 null）。
/// 字段 key 在创建时生成并保持不变——后续仅允许改名称/类型/标签，
/// 保证已登记资产的自定义字段数据不悬空。内置模板不可经此编辑。
class AssetTemplateEditorDialog extends StatefulWidget {
  const AssetTemplateEditorDialog({super.key, this.initial});

  /// 待编辑模板；null 表示新建。
  final AssetTemplate? initial;

  @override
  State<AssetTemplateEditorDialog> createState() =>
      _AssetTemplateEditorDialogState();
}

class _AssetTemplateEditorDialogState extends State<AssetTemplateEditorDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final List<_FieldDraft> _fields = [
    for (final field in widget.initial?.fields ?? const <AssetTemplateField>[])
      _FieldDraft.fromField(field),
  ];
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    for (final draft in _fields) {
      draft.labelController.dispose();
    }
    super.dispose();
  }

  void _addField() => setState(() => _fields.add(_FieldDraft.fresh()));

  void _removeField(int index) => setState(() {
    _fields[index].labelController.dispose();
    _fields.removeAt(index);
  });

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写模板名称');
      return;
    }
    final fields = <AssetTemplateField>[];
    for (final draft in _fields) {
      final label = draft.labelController.text.trim();
      if (label.isEmpty) continue;
      fields.add(
        AssetTemplateField(
          key: draft.key,
          label: label,
          kind: draft.kind,
          required: draft.requiredFlag,
          remind: draft.remind,
        ),
      );
    }
    Navigator.pop(
      context,
      AssetTemplate(
        id: widget.initial?.id ?? 'tpl-custom-${newId()}',
        name: name,
        typeTag: widget.initial?.typeTag,
        fields: fields,
        builtIn: false,
        enabled: widget.initial?.enabled ?? true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? '新增资产模板' : '编辑资产模板'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('template-name-field'),
              controller: _name,
              autofocus: widget.initial == null,
              decoration: const InputDecoration(
                labelText: '模板名称 *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('字段', style: Theme.of(context).textTheme.labelMedium),
            ),
            const SizedBox(height: 6),
            for (var index = 0; index < _fields.length; index++)
              _fieldRow(index),
            TextButton.icon(
              key: const Key('add-template-field'),
              onPressed: _addField,
              icon: const Icon(Icons.add),
              label: const Text('添加字段'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('保存')),
    ],
  );

  Widget _fieldRow(int index) {
    final draft = _fields[index];
    final keySuffix = draft.isNew ? 'new' : '$index';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: Key('template-field-label-$keySuffix'),
                    controller: draft.labelController,
                    decoration: const InputDecoration(
                      labelText: '字段名称',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<AssetFieldKind>(
                    key: Key('template-field-kind-$keySuffix'),
                    initialValue: draft.kind,
                    decoration: const InputDecoration(
                      labelText: '类型',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: AssetFieldKind.text,
                        child: Text('文本'),
                      ),
                      DropdownMenuItem(
                        value: AssetFieldKind.multiline,
                        child: Text('多行文本'),
                      ),
                      DropdownMenuItem(
                        value: AssetFieldKind.number,
                        child: Text('数字'),
                      ),
                      DropdownMenuItem(
                        value: AssetFieldKind.date,
                        child: Text('日期'),
                      ),
                      DropdownMenuItem(
                        value: AssetFieldKind.url,
                        child: Text('链接'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => draft.kind = value ?? draft.kind),
                  ),
                ),
                IconButton(
                  key: Key('template-field-delete-$keySuffix'),
                  tooltip: '删除字段',
                  onPressed: () => _removeField(index),
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                ),
              ],
            ),
            if (draft.kind == AssetFieldKind.date)
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      key: Key('template-field-required-$keySuffix'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('主到期日', style: TextStyle(fontSize: 13)),
                      value: draft.requiredFlag,
                      onChanged: (value) =>
                          setState(() => draft.requiredFlag = value ?? false),
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      key: Key('template-field-remind-$keySuffix'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        '进入日历提醒',
                        style: TextStyle(fontSize: 13),
                      ),
                      value: draft.remind,
                      onChanged: (value) =>
                          setState(() => draft.remind = value ?? false),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _FieldDraft {
  _FieldDraft.fresh()
    : key = 'c-${newId()}',
      isNew = true,
      labelController = TextEditingController(),
      kind = AssetFieldKind.text,
      requiredFlag = false,
      remind = false;

  _FieldDraft.fromField(AssetTemplateField field)
    : key = field.key,
      isNew = false,
      labelController = TextEditingController(text: field.label),
      kind = field.kind,
      requiredFlag = field.required,
      remind = field.remind;

  final String key;
  final bool isNew;
  final TextEditingController labelController;
  AssetFieldKind kind;
  bool requiredFlag;
  bool remind;
}
