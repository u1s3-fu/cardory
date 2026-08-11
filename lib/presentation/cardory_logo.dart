import 'package:flutter/material.dart';

/// Cardory 品牌 logo（位图版本）。
///
/// 直接渲染 `assets/branding/app_icon_source.png`。
/// 使用 [BoxFit.contain] 与 [AspectRatio] 保持原始宽高比，
/// 避免父容器约束（如 Column 的 stretch）造成拉伸变形。
class CardoryLogo extends StatelessWidget {
  const CardoryLogo({
    super.key,
    this.size = 48,
  });

  /// logo 边长（正方形）。
  final double size;

  static const String assetPath = 'assets/branding/app_icon_source.png';

  /// 源图原始宽高比（1024×1024 → 1:1）。
  static const double _aspectRatio = 1.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: AspectRatio(
        aspectRatio: _aspectRatio,
        child: ClipRect(
          child: Image.asset(
            assetPath,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            isAntiAlias: true,
          ),
        ),
      ),
    );
  }
}