// 回收站对话框：列出软删除条目并支持恢复。
//
// 数据面约束见 RecycleBinRepository：条目保留 30 天后随同步清理永久
// 消失；附件文件在删除时已物理清除、不进入回收站；恢复经 sync_changes
// 同步到其他设备。

import 'package:flutter/material.dart';

import '../../application/workspace_controller.dart';
import '../../domain/cardory_utils.dart';
import '../../domain/recycle_bin_models.dart';
import '../cardory_theme.dart';

class RecycleBinDialog extends StatefulWidget {
  const RecycleBinDialog({super.key, required this.controller});

  final WorkspaceController controller;

  static Future<void> show(
    BuildContext context, {
    required WorkspaceController controller,
  }) => showDialog<void>(
    context: context,
    builder: (_) => RecycleBinDialog(controller: controller),
  );

  @override
  State<RecycleBinDialog> createState() => _RecycleBinDialogState();
}

class _RecycleBinDialogState extends State<RecycleBinDialog> {
  static const _retentionDays = 30;

  List<RecycleBinEntry>? _entries;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final entries = await widget.controller.loadRecycleBinEntries();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _error = '无法读取回收站：$error';
      });
    }
  }

  Future<void> _restore(RecycleBinEntry entry) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('恢复条目'),
        content: Text('恢复「${entry.title}」？恢复后会重新出现在工作台，并同步到其他设备。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.controller.restoreRecycleBinEntry(entry);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已恢复「${entry.title}」。')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error is StateError ? error.message : '恢复失败：$error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _reload();
  }

  static ({IconData icon, String label}) _typeStyle(
    RecycleBinEntityType type,
  ) => switch (type) {
    RecycleBinEntityType.project => (icon: Icons.folder_outlined, label: '项目'),
    RecycleBinEntityType.task => (
      icon: Icons.check_circle_outline,
      label: '待办',
    ),
    RecycleBinEntityType.asset => (
      icon: Icons.inventory_2_outlined,
      label: '资产',
    ),
    RecycleBinEntityType.milestone => (icon: Icons.flag_outlined, label: '里程碑'),
  };

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return AlertDialog(
      title: const Text('回收站'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '已删除的条目保留 $_retentionDays 天，之后自动永久清除。'
              '附件文件在删除时已一并移除，不在恢复范围内。',
              style: TextStyle(color: CardoryColors.gray500, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(
                  color: cardoryEnsureWhiteContrast(CardoryColors.error),
                ),
              )
            else if (entries == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('回收站是空的。')),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _RecycleBinTile(
                    entry: entries[index],
                    busy: _busy,
                    onRestore: () => _restore(entries[index]),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _RecycleBinTile extends StatelessWidget {
  const _RecycleBinTile({
    required this.entry,
    required this.busy,
    required this.onRestore,
  });

  final RecycleBinEntry entry;
  final bool busy;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final style = _RecycleBinDialogState._typeStyle(entry.type);
    final deletedLocal = entry.deletedAt.toLocal();
    final elapsed = DateTime.now().difference(deletedLocal).inDays;
    final remaining = (_RecycleBinDialogState._retentionDays - elapsed).clamp(
      0,
      _RecycleBinDialogState._retentionDays,
    );
    final subtitleParts = [
      '删除于 ${formatDateTime(deletedLocal)}',
      '剩余 $remaining 天',
      if (entry.subtitle.isNotEmpty) entry.subtitle,
    ];
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(style.icon, color: CardoryColors.gray500),
      title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitleParts.join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: CardoryColors.gray500, fontSize: 12),
      ),
      trailing: TextButton(
        onPressed: busy ? null : onRestore,
        child: const Text('恢复'),
      ),
    );
  }
}
