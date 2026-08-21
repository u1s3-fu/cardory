import 'package:flutter/material.dart';

/// Password input with an explicit visibility toggle.
class PasswordTextField extends StatefulWidget {
  const PasswordTextField({
    super.key,
    this.fieldKey,
    required this.controller,
    required this.decoration,
    this.autofocus = false,
    this.enabled = true,
    this.onChanged,
    this.onSubmitted,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final InputDecoration decoration;
  final bool autofocus;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) => TextField(
    key: widget.fieldKey,
    controller: widget.controller,
    obscureText: _obscureText,
    autofocus: widget.autofocus,
    enabled: widget.enabled,
    onChanged: widget.onChanged,
    onSubmitted: widget.onSubmitted,
    decoration: widget.decoration.copyWith(
      suffixIconConstraints: const BoxConstraints.tightFor(width: 28, height: 28),
      suffixIcon: SizedBox(
        width: 28,
        height: 28,
        child: Tooltip(
          message: _obscureText ? '显示密码' : '隐藏密码',
          child: Semantics(
            button: true,
            label: _obscureText ? '显示密码' : '隐藏密码',
            child: InkWell(
              onTap: () => setState(() => _obscureText = !_obscureText),
              child: Center(
                child: Icon(
                  _obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 16,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
