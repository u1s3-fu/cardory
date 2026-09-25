import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 凭据展示行：用户名默认明文，密码默认掩码。
///
/// 密码揭示 30 秒后自动隐藏；复制经 [Clipboard.setData] 并回调提示。
/// 空值时整行显示「未填写」，不提供眼睛与复制按钮。
class CredentialRow extends StatefulWidget {
  const CredentialRow({
    super.key,
    required this.label,
    required this.value,
    this.secret = false,
    this.onCopied,
  });

  final String label;
  final String value;

  /// true：默认掩码 + 眼睛揭示；false：明文。
  final bool secret;

  /// 复制成功回调（宿主用它弹 SnackBar）。
  final void Function(String value)? onCopied;

  @override
  State<CredentialRow> createState() => _CredentialRowState();
}

class _CredentialRowState extends State<CredentialRow> {
  static const _revealDuration = Duration(seconds: 30);

  bool _revealed = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _toggleReveal() {
    setState(() {
      if (_revealed) {
        _hideTimer?.cancel();
        _revealed = false;
      } else {
        _revealed = true;
        _hideTimer = Timer(_revealDuration, () {
          if (mounted) setState(() => _revealed = false);
        });
      }
    });
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    widget.onCopied?.call(widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final masked = widget.secret && !_revealed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 3),
          if (value.isEmpty)
            const Text('未填写')
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    masked ? '•' * value.length : value,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.secret)
                  IconButton(
                    key: const Key('credential-reveal'),
                    icon: Icon(
                      _revealed
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    tooltip: _revealed ? '隐藏' : '显示',
                    onPressed: _toggleReveal,
                  ),
                IconButton(
                  key: const Key('credential-copy'),
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  tooltip: '复制',
                  onPressed: _copy,
                ),
              ],
            ),
        ],
      ),
    );
  }
}
