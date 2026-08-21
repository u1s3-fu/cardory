import 'package:flutter/material.dart';

import '../../domain/cardory_models.dart';

class ProgressDialog extends StatefulWidget {
  const ProgressDialog({super.key, this.currentProgress, this.entry})
    : assert(currentProgress != null || entry != null);

  final double? currentProgress;
  final ProjectProgressEntry? entry;

  @override
  State<ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<ProgressDialog> {
  late final _note = TextEditingController(text: widget.entry?.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.entry == null ? '记录进度' : '编辑进度'),
    content: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 460,
        maxHeight: MediaQuery.sizeOf(context).height * 0.68,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _note,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(labelText: '进度说明'),
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
        onPressed: () {
          Navigator.pop(
            context,
            ProjectProgressEntry(
              id: widget.entry?.id ?? newId(),
              note: _note.text.trim().isEmpty ? '更新项目进度' : _note.text.trim(),
              progress: widget.entry?.progress ?? widget.currentProgress ?? 0,
              createdAt: widget.entry?.createdAt ?? DateTime.now(),
            ),
          );
        },
        child: const Text('保存'),
      ),
    ],
  );
}
