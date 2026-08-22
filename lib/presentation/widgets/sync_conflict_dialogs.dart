import 'package:flutter/material.dart';

import '../../domain/sync_status.dart';

/// 弹出同步冲突对话框：返回保留本地 / 使用远端 / 手动合并 / 取消。
Future<SyncConflictChoice?> showSyncConflictDialog(
  BuildContext context,
  List<SyncConflictItem> conflicts,
) {
  return showDialog<SyncConflictChoice>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('同步冲突'),
      content: SizedBox(
        width: 460,
        child: conflicts.isEmpty
            ? const Text('本地和云端都存在未同步的修改。请选择要保留的数据版本。')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('发现 ${conflicts.length} 项差异：'),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: conflicts.length,
                      itemBuilder: (_, index) {
                        final item = conflicts[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            item.side == SyncConflictSide.local
                                ? Icons.computer
                                : Icons.cloud_outlined,
                          ),
                          title: Text(item.title),
                          subtitle: Text(
                            '${item.category} · ${item.side == SyncConflictSide.local ? '本地有变化' : '远端新增'}',
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
          onPressed: () =>
              Navigator.of(dialogContext).pop(SyncConflictChoice.cancel),
          child: const Text('取消'),
        ),
        OutlinedButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(SyncConflictChoice.manualMerge),
          child: const Text('手动合并'),
        ),
        OutlinedButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(SyncConflictChoice.keepRemote),
          child: const Text('使用远端'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(SyncConflictChoice.keepLocal),
          child: const Text('保留本地'),
        ),
      ],
    ),
  );
}

/// 弹出手动合并对话框：逐项选择本地 / 远端来源，返回 id → 来源 的映射。
Future<Map<String, SyncConflictSide>?> showManualMergeDialog(
  BuildContext context,
  List<SyncConflictItem> conflicts,
) {
  final choices = <String, SyncConflictSide>{
    for (final item in conflicts) item.id: item.side,
  };
  return showDialog<Map<String, SyncConflictSide>>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('手动合并'),
        content: SizedBox(
          width: 460,
          child: ListView(
            shrinkWrap: true,
            children: conflicts.map((item) {
              final selected = choices[item.id] ?? item.side;
              return ListTile(
                key: ValueKey('conflict-${item.id}'),
                title: Text(item.title),
                subtitle: Text(item.category),
                trailing: DropdownButton<SyncConflictSide>(
                  value: selected,
                  items: const [
                    DropdownMenuItem(
                      value: SyncConflictSide.local,
                      child: Text('本地'),
                    ),
                    DropdownMenuItem(
                      value: SyncConflictSide.remote,
                      child: Text('远端'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => choices[item.id] = value);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, choices),
            child: const Text('应用合并'),
          ),
        ],
      ),
    ),
  );
}
