import 'package:flutter/material.dart';

/// Cardory 品牌 logo（位图版本）。
///
/// 直接渲染 `assets/branding/app_icon_source.png`。源图 1024×1024，
/// 但 logo 内容只占中心约 70%，四周是设计留白。
/// 这里通过 Transform 放大图片并配合外层裁切，让 logo 内容（去掉留白）
/// 按比例充满整个 [size] 区域。
class CardoryLogo extends StatelessWidget {
  const CardoryLogo({
    super.key,
    this.size = 48,
  });

  /// logo 边长（正方形）。
  final double size;

  static const String assetPath = 'assets/branding/app_icon_source.png';

  /// 源图 logo 内容在画布中的实际占比（四周各约 14% 留白 → 0.72）。
  static const double _contentRatio = 0.72;

  @override
  Widget build(BuildContext context) {
    // 放大倍数：让图片的实际 logo 内容刚好填满 size 区域。
    final innerSize = size / _contentRatio;
    return SizedBox(
      width: size,
      height: size,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.center,
          maxWidth: innerSize,
          maxHeight: innerSize,
          child: SizedBox(
            width: innerSize,
            height: innerSize,
            child: Image.asset(
              assetPath,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
      ),
    );
  }
}