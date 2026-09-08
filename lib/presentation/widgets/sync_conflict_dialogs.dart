import 'package:flutter/material.dart';

import '../../domain/sync_status.dart';
import '../cardory_palette.dart';

/// 弹出同步冲突对话框：返回保留本地 / 使用远端 / 手动合并 / 取消。
///
/// [conflicts] 为差异条目列表；[kind] 区分「首次同步发现本地数据」与
/// 「自上次同步后双向修改」两种场景，决定头部文案与提示语气。
Future<SyncConflictChoice?> showSyncConflictDialog(
  BuildContext context,
  List<SyncConflictItem> conflicts, {
  SyncConflictKind kind = SyncConflictKind.concurrent,
}) {
  final localOnlyCount = conflicts
      .where((item) => item.side == SyncConflictSide.local)
      .length;
  final remoteOnlyCount = conflicts.length - localOnlyCount;
  final isFirstSync = kind == SyncConflictKind.firstSync;

  return showDialog<SyncConflictChoice>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(isFirstSync ? '首次同步：本地与云端数据并存' : '检测到同步冲突'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isFirstSync
                  ? '本地已有数据，而云端此前也已存放了一份数据，且从未同步过。'
                        'Cardory 无法自动判断要保留哪一份，请选择处理方式。'
                  : '自上次成功同步后，本地与云端各自发生了修改。请选择以哪一版数据为准。',
              style: TextStyle(
                fontSize: 13,
                color: cardoryEnsureWhiteContrast(CardoryColors.gray500),
              ),
            ),
            const SizedBox(height: 12),
            if (conflicts.isEmpty)
              const Text('本地和云端都存在未同步的修改。')
            else ...[
              Text(
                isFirstSync
                    ? '差异清单（本地 $localOnlyCount 项 / 仅远端 $remoteOnlyCount 项）：'
                    : '发现 ${conflicts.length} 项差异（本地 $localOnlyCount 项 / 远端 $remoteOnlyCount 项）：',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: conflicts.length,
                  itemBuilder: (_, index) {
                    final item = conflicts[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      leading: Icon(
                        item.side == SyncConflictSide.local
                            ? Icons.computer
                            : Icons.cloud_outlined,
                        size: 18,
                      ),
                      title: Text(item.title, maxLines: 1),
                      subtitle: Text(
                        '${item.category} · ${item.side == SyncConflictSide.local ? '本地侧差异' : '仅远端存在'}',
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            const Text(
              '各选项的影响',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            _ConsequenceRow(text: '保留本地：把本地全部数据推送到云端并覆盖云端记录。'),
            _ConsequenceRow(
              text: isFirstSync
                  ? '使用远端：以云端数据替换本地。仅本地存在的内容将被覆盖'
                        '（操作前会自动备份本地数据）。'
                  : '使用远端：丢弃本地本次修改，恢复为云端数据（本地会先自动备份）。',
              isDestructive: true,
            ),
            _ConsequenceRow(text: '手动合并：逐条选择每一处差异的来源，可同时保留两边的独有内容。'),
            _ConsequenceRow(text: '取消：不做任何更改，稍后可再次同步处理。'),
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
          style: OutlinedButton.styleFrom(
            foregroundColor: isFirstSync
                ? cardoryEnsureWhiteContrast(CardoryColors.error)
                : null,
          ),
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

/// 冲突处理里高风险覆盖操作的二次确认框。
///
/// 目前用于首次同步选择「使用远端」：本地从未上云的数据将被云端版本覆盖，
/// 属于不可逆操作，需用户再次确认。
Future<bool> confirmDestructiveSyncOverride(
  BuildContext context, {
  required bool isFirstSync,
  required List<SyncConflictItem> conflicts,
}) async {
  final localOnlyCount = conflicts
      .where((item) => item.side == SyncConflictSide.local)
      .length;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(isFirstSync ? '确认丢弃本地数据？' : '确认覆盖？'),
      content: Text(
        isFirstSync
            ? '将使用云端数据替换本地当前全部内容'
                  '${localOnlyCount > 0 ? '（涉及仅本地存在的 $localOnlyCount 项）' : ''}。'
                  '\n\nCardory 会在覆盖前把本地数据自动备份到冲突快照目录，'
                  '确认后本地工作台数据将变为云端版本。'
            : '将丢弃本地未同步的修改并恢复为云端数据。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('再想想'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: CardoryColors.error,
            foregroundColor: Colors.white,
          ),
          child: const Text('确认使用远端'),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// 云端快照无法解密时的手动选择框。
///
/// 云端内容不可读（损坏，或由使用不同保险库密码的设备上传），自动流程没有
/// 任何安全默认值可选，因此把「保留本地并覆盖云端 / 跳过」的决定交给用户。
Future<SyncConflictChoice?> showUndecryptableRemoteDialog(
  BuildContext context,
) {
  return showDialog<SyncConflictChoice>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('云端数据无法解密'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '从云端下载的数据快照无法用当前保险库密码解密。可能原因：\n'
              '· 文件在上传或传输过程中损坏；\n'
              '· 快照由使用不同保险库密码的另一台设备上传。\n\n'
              'Cardory 无法读取云端内容，因此不能自动合并或直接使用远端数据，'
              '请手动决定如何处理这份云端快照：',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 10),
            const Text(
              '各选项的影响',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const _ConsequenceRow(
              text:
                  '用本地覆盖云端：以本机数据重新加密上传，替换云端快照'
                  '（覆盖前会先把云端原文件自动备份到快照目录）。',
            ),
            _ConsequenceRow(
              text:
                  '覆盖后，另一台使用不同保险库密码的设备将无法再读取新的云端'
                  '快照——请确认那台设备上的数据已不再需要后再操作。',
              isDestructive: true,
            ),
            const _ConsequenceRow(text: '跳过本次：云端快照保持原样、本地数据不变，稍后可再次同步时处理。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(SyncConflictChoice.cancel),
          child: const Text('跳过本次'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(SyncConflictChoice.keepLocal),
          style: FilledButton.styleFrom(
            backgroundColor: CardoryColors.error,
            foregroundColor: Colors.white,
          ),
          child: const Text('用本地覆盖云端'),
        ),
      ],
    ),
  );
}

/// 云端快照无法解密时选择「用本地覆盖云端」的二次确认框。
///
/// 覆盖是不可逆操作：云端原有快照将被本机数据替换（覆盖前先备份到冲突
/// 快照目录）。因云端内容可能来自另一台密码不同的设备，需用户再次确认。
Future<bool> confirmLocalOverwriteCloud(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('确认用本地数据覆盖云端？'),
      content: const Text(
        '将删除云端当前快照，并以本机数据重新加密上传，'
        '其他设备下次同步将以本机数据为准。\n\n'
        '覆盖前 Cardory 会把云端原文件自动备份到冲突快照目录。'
        '若云端快照来自另一台使用不同保险库密码的设备，'
        '该数据在覆盖后将无法被任何设备直接读取，只能从备份文件另行处理。'
        '\n\n此操作不可撤销。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('再想想'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: CardoryColors.error,
            foregroundColor: Colors.white,
          ),
          child: const Text('确认覆盖云端'),
        ),
      ],
    ),
  );
  return result ?? false;
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

class _ConsequenceRow extends StatelessWidget {
  const _ConsequenceRow({required this.text, this.isDestructive = false});

  final String text;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive
        ? cardoryEnsureWhiteContrast(CardoryColors.error)
        : cardoryEnsureWhiteContrast(CardoryColors.gray500);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Icon(
              isDestructive ? Icons.report_gmailerrorred : Icons.info_outline,
              size: 14,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: color, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
