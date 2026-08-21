import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';
import '../settings_models.dart';
import '../widgets/password_text_field.dart';

class AssetDialog extends StatefulWidget {
  const AssetDialog({
    super.key,
    this.asset,
    this.projectId = '',
    required this.serverTypes,
    this.assetTags = const [],
  });

  final AssetData? asset;
  final String projectId;
  final List<String> serverTypes;
  final List<AssetTag> assetTags;

  @override
  State<AssetDialog> createState() => _AssetDialogState();
}

class _AssetDialogState extends State<AssetDialog> {
  late AssetType _type = widget.asset?.type ?? AssetType.software;
  late final _name = TextEditingController(text: widget.asset?.name ?? '');
  late final _version = TextEditingController(
    text: widget.asset?.version ?? '',
  );
  late final _port = TextEditingController(text: widget.asset?.port ?? '');
  late final _path = TextEditingController(text: widget.asset?.path ?? '');
  late final _serialNumber = TextEditingController(
    text: widget.asset?.serialNumber ?? '',
  );
  late final _network = TextEditingController(
    text: widget.asset?.network ?? '',
  );
  late final _serverType = TextEditingController(
    text: widget.asset?.serverType ?? '',
  );
  late final _username = TextEditingController(
    text: widget.asset?.username ?? '',
  );
  late final _password = TextEditingController(
    text: widget.asset?.password ?? '',
  );
  late final _note = TextEditingController(text: widget.asset?.note ?? '');
  late final Set<String> _selectedTagIds = {
    ...?widget.asset?.tagIds,
  };
  String? _error;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _version,
      _port,
      _path,
      _serialNumber,
      _network,
      _serverType,
      _username,
      _password,
      _note,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  InputDecoration _decoration(String label) =>
      InputDecoration(labelText: label, border: const OutlineInputBorder());

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写资产名称');
      return;
    }
    Navigator.pop(
      context,
      AssetDialogResult(
        asset: AssetData(
          id: widget.asset?.id ?? newId(),
          type: _type,
          name: name,
          projectId: widget.asset?.projectId ?? widget.projectId,
          version: _version.text.trim(),
          port: _port.text.trim(),
          path: _path.text.trim(),
          serialNumber: _serialNumber.text.trim(),
          network: _network.text.trim(),
          serverType: _serverType.text.trim(),
          username: _username.text.trim(),
          password: _password.text,
          note: _note.text.trim(),
          tagIds: _selectedTagIds.toList(),
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
            SegmentedButton<AssetType>(
              segments: const [
                ButtonSegment(
                  value: AssetType.software,
                  label: Text('软件资产'),
                  icon: Icon(Icons.apps_outlined),
                ),
                ButtonSegment(
                  value: AssetType.hardware,
                  label: Text('硬件资产'),
                  icon: Icon(Icons.dns_outlined),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) =>
                  setState(() => _type = value.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              decoration: _decoration('资产名称 *'),
            ),
            const SizedBox(height: 12),
            if (_type == AssetType.software) ...[
              TextField(controller: _version, decoration: _decoration('版本')),
              const SizedBox(height: 12),
              TextField(
                controller: _port,
                keyboardType: TextInputType.number,
                decoration: _decoration('端口'),
              ),
              const SizedBox(height: 12),
              TextField(controller: _path, decoration: _decoration('路径')),
            ] else ...[
              TextField(
                controller: _serialNumber,
                decoration: _decoration('服务器序列号'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _network,
                decoration: _decoration('网络 / IP / 网段'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: widget.serverTypes.contains(_serverType.text)
                    ? _serverType.text
                    : null,
                decoration: _decoration('服务器类型'),
                items: widget.serverTypes
                    .map(
                      (type) =>
                          DropdownMenuItem(value: type, child: Text(type)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _serverType.text = value ?? ''),
              ),
              if (widget.serverTypes.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('可在“设置 > 工作台偏好”中新增服务器类型。'),
                ),
            ],
            const SizedBox(height: 12),
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
