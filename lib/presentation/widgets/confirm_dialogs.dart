import 'package:flutter/material.dart';

import '../cardory_theme.dart';

/// 弹出文本输入对话框，返回去掉首尾空格后的内容；取消返回 null。
///
/// [disallowEmpty] 为 true 时内容为空则禁用“保存”按钮；
/// [minLines]/[maxLines] 大于 1 时按多行输入框渲染。
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String labelText = '',
  String? helperText,
  String confirmLabel = '保存',
  int minLines = 1,
  int maxLines = 1,
  bool disallowEmpty = false,
  bool alignLabelWithHint = false,
  TextInputType? keyboardType,
  TextInputAction? textInputAction,
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final trimmed = controller.text.trim();
        final canSubmit = !disallowEmpty || trimmed.isNotEmpty;
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: minLines,
            maxLines: maxLines,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            decoration: InputDecoration(
              labelText: labelText.isEmpty ? null : labelText,
              helperText: helperText,
              alignLabelWithHint: alignLabelWithHint,
            ),
            onChanged: (_) => setDialogState(() {}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: canSubmit
                  ? () => Navigator.pop(dialogContext, trimmed)
                  : null,
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    ),
  );
  controller.dispose();
  return result;
}

/// 弹出通用确认对话框（取消 / 确认），返回是否确认。
///
/// [confirmColor] 用于危险操作（如删除）时指定确认按钮的背景色，
/// 不传则使用主题主色；传入非白底颜色时自动保证文字对比度。
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  required String confirmLabel,
  String cancelLabel = '取消',
  Color? confirmColor,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: confirmColor == null
              ? null
              : FilledButton.styleFrom(
                  backgroundColor:
                      cardoryEnsureWhiteContrast(confirmColor),
                  foregroundColor: CardoryColors.white,
                ),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}
