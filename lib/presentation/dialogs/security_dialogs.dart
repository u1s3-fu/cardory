import 'package:flutter/material.dart';

import '../cardory_theme.dart';
import '../widgets/password_text_field.dart';

/// 修改密码对话框的返回值。
class PasswordChangeResult {
  const PasswordChangeResult({
    required this.currentPassword,
    required this.newPassword,
  });

  final String currentPassword;
  final String newPassword;
}

class PasswordChangeDialog extends StatefulWidget {
  const PasswordChangeDialog({super.key});

  @override
  State<PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<PasswordChangeDialog> {
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    if (_newPassword.text.length < 8) {
      setState(() => _error = '新密码至少需要 8 个字符。');
      return;
    }
    if (_newPassword.text != _confirmation.text) {
      setState(() => _error = '两次输入的新密码不一致。');
      return;
    }
    Navigator.pop(
      context,
      PasswordChangeResult(
        currentPassword: _currentPassword.text,
        newPassword: _newPassword.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('修改密码'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PasswordTextField(
            controller: _currentPassword,
            autofocus: true,
            decoration: const InputDecoration(labelText: '当前密码'),
          ),
          const SizedBox(height: 12),
          PasswordTextField(
            controller: _newPassword,
            decoration: const InputDecoration(labelText: '新密码'),
          ),
          const SizedBox(height: 12),
          PasswordTextField(
            controller: _confirmation,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: '确认新密码'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(
                color: cardoryEnsureWhiteContrast(CardoryColors.error),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('修改密码')),
    ],
  );
}
