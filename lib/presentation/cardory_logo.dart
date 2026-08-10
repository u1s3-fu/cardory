import 'package:flutter/material.dart';

/// Cardory 品牌矢量 logo（CustomPainter 绘制，可无限缩放、无位图依赖）。
///
/// 概念对应「板记」：一张正面任务卡片（标题 + 副标题横线、紫色圆形对勾
/// 徽章），背后叠着两张浅紫卡片，传达「待办卡片 + 项目进度」的产品语义。
/// 纯扁平几何、硬边填充，无渐变、无阴影，作为品牌标识保持稳定的辨识度。
class CardoryLogo extends StatelessWidget {
  const CardoryLogo({
    super.key,
    this.size = 48,
    this.cardColor,
    this.foregroundColor = Colors.white,
  });

  /// logo 的边长（正方形）。
  final double size;

  /// 主卡片填充色；默认品牌靛蓝 [Color(0xFF4F46E5)]。
  final Color? cardColor;

  /// 卡片内横线与对勾的颜色；默认白色，深色场景下可传入浅色主题色。
  final Color foregroundColor;

  static const Color brandIndigo = Color(0xFF4F46E5);
  static const Color brandViolet = Color(0xFF7C3AED);
  static const Color brandLavender = Color(0xFFDDD6FE);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _CardoryLogoPainter(
        cardColor: cardColor ?? brandIndigo,
        accentColor: brandViolet,
        backCardColor: brandLavender,
        foregroundColor: foregroundColor,
      ),
    );
  }
}

class _CardoryLogoPainter extends CustomPainter {
  const _CardoryLogoPainter({
    required this.cardColor,
    required this.accentColor,
    required this.backCardColor,
    required this.foregroundColor,
  });

  final Color cardColor;
  final Color accentColor;
  final Color backCardColor;
  final Color foregroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 以 100 x 100 的逻辑坐标构图，再整体缩放到实际尺寸。
    final scale = size.shortestSide / 100;
    canvas.scale(scale, scale);

    // 背景两张浅紫卡片：部分被主卡遮挡，先绘制。
    _drawBackCard(canvas, offset: const Offset(-20, -19), rotation: 0.12);
    _drawBackCard(
      canvas,
      offset: const Offset(-17, 16),
      rotation: -0.12,
      alpha: 0.55,
    );

    // 主卡片：微倾的正面任务卡。
    canvas.save();
    canvas.translate(8, 2);
    canvas.rotate(-0.08);
    final mainRect = const Rect.fromLTRB(-31, -35, 31, 35);
    final mainPaint = Paint()..color = cardColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(mainRect, const Radius.circular(13)),
      mainPaint,
    );

    // 标题 / 副标题横线。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(-19, -20, -1, -15),
        const Radius.circular(2.4),
      ),
      Paint()..color = foregroundColor.withValues(alpha: 0.95),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(-19, -10, -6, -6),
        const Radius.circular(1.8),
      ),
      Paint()..color = foregroundColor.withValues(alpha: 0.55),
    );

    // 对勾徽章：紫色圆形 + 白色对勾。
    const badgeCenter = Offset(22, 4);
    final badgeRadius = 11.0;
    canvas.drawCircle(badgeCenter, badgeRadius, Paint()..color = accentColor);
    canvas.drawCircle(
      badgeCenter,
      badgeRadius,
      Paint()
        ..color = foregroundColor.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    final checkPaint = Paint()
      ..color = foregroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final checkPath = Path()
      ..moveTo(badgeCenter.dx - 4.6, badgeCenter.dy + 0.5)
      ..lineTo(badgeCenter.dx - 0.6, badgeCenter.dy + 4.8)
      ..lineTo(badgeCenter.dx + 6.2, badgeCenter.dy - 5.4);
    canvas.drawPath(checkPath, checkPaint);
    canvas.restore();
  }

  void _drawBackCard(
    Canvas canvas, {
    required Offset offset,
    required double rotation,
    double alpha = 1,
  }) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.rotate(rotation);
    final paint = Paint()
      ..color = backCardColor.withValues(alpha: alpha)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(-21, -23, 21, 23),
        const Radius.circular(9),
      ),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardoryLogoPainter oldDelegate) =>
      oldDelegate.cardColor != cardColor ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.backCardColor != backCardColor ||
      oldDelegate.foregroundColor != foregroundColor;
}
