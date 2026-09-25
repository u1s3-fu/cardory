import 'package:flutter/material.dart';

import '../../domain/asset_template.dart';
import '../../domain/cardory_models.dart';
import '../widgets/password_text_field.dart';

/// 资产对话框的返回值：确认后返回更新后的资产数据。
class AssetDialogResult {
  const AssetDialogResult({required this.asset});

  final AssetData asset;
}

class AssetDialog extends StatefulWidget {
  const AssetDialog({
    super.key,
    this.asset,
    this.projectId = '',
    required this.templates,
    this.serverTypes = const [],
    this.assetTags = const [],
  });

  final AssetData? asset;
  final String projectId;

  /// 资产类型模板清单（来自设置；为空时表单无自定义字段）。
  final List<AssetTemplate> templates;
  final List<String> serverTypes;
  final List<AssetTag> assetTags;

  @override
  State<AssetDialog> createState() => _AssetDialogState();
}

class _AssetDialogState extends State<AssetDialog> {
  late String _templateId = _initialTemplateId();
  late final _name = TextEditingController(text: widget.asset?.name ?? '');
  late final _username = TextEditingController(
    text: widget.asset?.username ?? '',
  );
  late final _password = TextEditingController(
    text: widget.asset?.password ?? '',
  );
  late final _note = TextEditingController(text: widget.asset?.note ?? '');
  late Map<String, TextEditingController> _fieldControllers =
      _buildFieldControllers();
  late final Set<String> _selectedTagIds = {...?widget.asset?.tagIds};
  String? _error;

  /// 当前生效的模板；templates 为空时退化为无字段模板，避免崩溃。
  AssetTemplate get _template {
    for (final template in widget.templates) {
      if (template.id == _templateId) return template;
    }
    return const AssetTemplate(id: '', name: '', fields: []);
  }

  /// 初始模板：优先资产自身 templateId，其次按旧 AssetType 匹配 typeTag。
  String _initialTemplateId() {
    final asset = widget.asset;
    if (widget.templates.isEmpty) return '';
    if (asset != null && asset.templateId.isNotEmpty) {
      final exists = widget.templates.any((t) => t.id == asset.templateId);
      if (exists) return asset.templateId;
    }
    if (asset != null) {
      for (final template in widget.templates) {
        if (template.typeTag == asset.type.name) return template.id;
      }
    }
    return widget.templates.first.id;
  }

  /// 为当前模板字段建控制器；编辑时预填 customFields，
  /// 缺失的键回退到旧顶层字段（version/port/path 等内置键）。
  Map<String, TextEditingController> _buildFieldControllers() {
    final asset = widget.asset;
    final custom = asset?.customFields ?? const {};
    return {
      for (final field in _template.fields)
        field.key: TextEditingController(
          text: custom[field.key] ?? _legacyFieldValue(asset, field.key) ?? '',
        ),
    };
  }

  static String? _legacyFieldValue(AssetData? asset, String key) {
    if (asset == null) return null;
    switch (key) {
      case 'version':
        return asset.version;
      case 'port':
        return asset.port;
      case 'path':
        return asset.path;
      case 'serialNumber':
        return asset.serialNumber;
      case 'network':
        return asset.network;
      case 'serverType':
        return asset.serverType;
    }
    return null;
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    _note.dispose();
    for (final controller in _fieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  InputDecoration _decoration(String label) =>
      InputDecoration(labelText: label, border: const OutlineInputBorder());

  void _onTemplateChanged(String? value) {
    if (value == null || value == _templateId) return;
    setState(() {
      _templateId = value;
      final old = _fieldControllers;
      // 切模板保留同名 key 的已填值，只补建缺失的控制器。
      _fieldControllers = {
        for (final field in _template.fields)
          field.key:
              old.remove(field.key) ??
              TextEditingController(
                text: _legacyFieldValue(widget.asset, field.key) ?? '',
              ),
      };
      for (final controller in old.values) {
        controller.dispose();
      }
    });
  }

  Future<void> _pickDate(AssetTemplateField field) async {
    final controller = _fieldControllers[field.key];
    if (controller == null) return;
    final initial = _tryParseDate(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.text =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }

  static DateTime? _tryParseDate(String text) {
    final parts = text.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  Widget _buildField(AssetTemplateField field) {
    final controller = _fieldControllers[field.key]!;
    final label = field.label;
    switch (field.kind) {
      case AssetFieldKind.multiline:
        return TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: _decoration(label),
        );
      case AssetFieldKind.number:
        return TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: _decoration(label),
        );
      case AssetFieldKind.url:
        return TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: _decoration(label),
        );
      case AssetFieldKind.date:
        return TextField(
          controller: controller,
          readOnly: true,
          decoration: _decoration(label),
          onTap: () => _pickDate(field),
        );
      case AssetFieldKind.text:
        return TextField(
          controller: controller,
          decoration: _decoration(label),
        );
    }
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写资产名称');
      return;
    }
    final template = _template;
    final customFields = <String, String>{
      for (final field in template.fields)
        field.key: _fieldControllers[field.key]?.text.trim() ?? '',
    };
    for (final field in template.fields) {
      if (field.required && (customFields[field.key]?.isEmpty ?? true)) {
        setState(() => _error = '请填写${field.label}');
        return;
      }
    }
    Navigator.pop(
      context,
      AssetDialogResult(
        asset: AssetData(
          id: widget.asset?.id ?? newId(),
          type: template.typeTag == 'hardware'
              ? AssetType.hardware
              : AssetType.software,
          name: name,
          projectId: widget.asset?.projectId ?? widget.projectId,
          // 内置软件/硬件模板键与旧顶层字段同名，镜像填充保持旧读路径兼容。
          version: customFields['version'] ?? '',
          port: customFields['port'] ?? '',
          path: customFields['path'] ?? '',
          serialNumber: customFields['serialNumber'] ?? '',
          network: customFields['network'] ?? '',
          serverType: customFields['serverType'] ?? '',
          username: _username.text.trim(),
          password: _password.text,
          note: _note.text.trim(),
          tagIds: _selectedTagIds.toList(),
          templateId: template.id,
          customFields: customFields,
          activities: widget.asset?.activities ?? const [],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.asset == null ? '新增资产' : '编辑资产'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.templates.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _templateId,
                decoration: _decoration('资产类型'),
                items: [
                  for (final template in widget.templates)
                    DropdownMenuItem(
                      value: template.id,
                      child: Text(template.name),
                    ),
                ],
                onChanged: _onTemplateChanged,
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              decoration: _decoration('资产名称 *'),
            ),
            const SizedBox(height: 12),
            for (final field in _template.fields) ...[
              _buildField(field),
              const SizedBox(height: 12),
            ],
            TextField(controller: _username, decoration: _decoration('登录用户名')),
            const SizedBox(height: 12),
            PasswordTextField(
              controller: _password,
              decoration: _decoration('登录密码'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              decoration: _decoration('备注 / 用途'),
            ),
            if (widget.assetTags.isNotEmpty) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '标签',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final tag in widget.assetTags)
                    FilterChip(
                      key: Key('asset-tag-chip-${tag.id}'),
                      label: Text(tag.name),
                      selected: _selectedTagIds.contains(tag.id),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onSelected: (value) => setState(() {
                        if (value) {
                          _selectedTagIds.add(tag.id);
                        } else {
                          _selectedTagIds.remove(tag.id);
                        }
                      }),
                    ),
                ],
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
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
}
