import 'package:flutter/material.dart';

/// Cardory 调色板与色彩工具。
///
/// 提供主题可用的调色板数据结构、当前激活调色板的全局访问
/// （[CardoryColors]）、默认调色板，以及亮度/对比度相关纯函数。
///
/// 本文件只依赖 `flutter/material`，不涉及 ThemeData 构建，便于独立测试。
/// 主题构建见 `cardory_theme.dart`。

/// 主题可用的调色板。
///
/// [CardoryColors] 通过 [CardoryColors.apply] 切换当前激活的调色板，
/// 使全应用硬编码的 `CardoryColors.*` 引用能跟随主题预设变化。
class CardoryPalette {
  const CardoryPalette({
    required this.white,
    required this.gray25,
    required this.gray50,
    required this.gray100,
    required this.gray200,
    required this.gray300,
    required this.gray400,
    required this.gray500,
    required this.gray600,
    required this.gray700,
    required this.gray800,
    required this.gray900,
    required this.primary,
    required this.primarySoft,
    required this.success,
    required this.error,
    required this.warning,
    required this.pink,
  });

  final Color white;
  final Color gray25;
  final Color gray50;
  final Color gray100;
  final Color gray200;
  final Color gray300;
  final Color gray400;
  final Color gray500;
  final Color gray600;
  final Color gray700;
  final Color gray800;
  final Color gray900;
  final Color primary;
  final Color primarySoft;
  final Color success;
  final Color error;
  final Color warning;
  final Color pink;
}

/// 当前激活调色板的全局访问。
///
/// 字段为动态 getter，取值来自当前激活的 [CardoryPalette]。
abstract final class CardoryColors {
  static CardoryPalette _active = cardoryDefaultPalette;

  static Color get white => _active.white;
  static Color get gray25 => _active.gray25;
  static Color get gray50 => _active.gray50;
  static Color get gray100 => _active.gray100;
  static Color get gray200 => _active.gray200;
  static Color get gray300 => _active.gray300;
  static Color get gray400 => _active.gray400;
  static Color get gray500 => _active.gray500;
  static Color get gray600 => _active.gray600;
  static Color get gray700 => _active.gray700;
  static Color get gray800 => _active.gray800;
  static Color get gray900 => _active.gray900;
  static Color get primary => _active.primary;
  static Color get primarySoft => _active.primarySoft;
  static Color get success => _active.success;
  static Color get error => _active.error;
  static Color get warning => _active.warning;
  static Color get pink => _active.pink;

  /// 切换当前激活的调色板。
  static void apply(CardoryPalette palette) => _active = palette;
}

/// 默认（蓝紫 / 精致）调色板。
const CardoryPalette cardoryDefaultPalette = CardoryPalette(
  white: Color(0xFFFFFFFF),
  gray25: Color(0xFFFCFCFF),
  gray50: Color(0xFFF5F6FC),
  gray100: Color(0xFFEEF0F8),
  gray200: Color(0xFFE2E5F0),
  gray300: Color(0xFFCDD2E3),
  gray400: Color(0xFF7C86A3),
  gray500: Color(0xFF69738E),
  gray600: Color(0xFF4F5974),
  gray700: Color(0xFF363F59),
  gray800: Color(0xFF252C43),
  gray900: Color(0xFF1E2438),
  primary: Color(0xFF6B62DF),
  primarySoft: Color(0xFFEEECFF),
  success: Color(0xFF44B88A),
  error: Color(0xFFEF7180),
  warning: Color(0xFFF2A354),
  pink: Color(0xFFCF79DF),
);

/// 根据背景色的感知亮度判断是否应使用暗色文字/暗色主题。
///
/// 阈值取 0.5：背景色偏暗则返回暗色模式，偏亮则返回亮色模式。
Brightness brightnessForBackground(Color background) {
  // 用线性亮度近似判断：0.2126 R + 0.7152 G + 0.0722 B（0..1）
  final luminance =
      background.r * 0.2126 + background.g * 0.7152 + background.b * 0.0722;
  return luminance < 0.5 ? Brightness.dark : Brightness.light;
}

/// 计算两个颜色的 WCAG 对比度（0.05 补偿后比值）。
double cardoryContrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// 将 [color] 向黑色方向加深，直至与 [background] 的对比度 ≥ [minRatio]（WCAG AA）。
/// 已达标时原样返回。用于保证彩色文字/图形在特定背景上始终可读。
Color cardoryEnsureContrast(
  Color color,
  Color background, {
  double minRatio = 4.5,
}) {
  if (cardoryContrast(color, background) >= minRatio) return color;
  // 二分查找最小加深比例：向黑色方向 lerp 直至对比度达标。
  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 24; i++) {
    final mid = (low + high) / 2;
    final candidate = Color.lerp(color, Colors.black, mid)!;
    if (cardoryContrast(candidate, background) >= minRatio) {
      high = mid;
    } else {
      low = mid;
    }
  }
  return Color.lerp(color, Colors.black, high)!;
}

/// 将 [color] 加深到与白色对比度 ≥ [minRatio]（默认 4.5:1，图形可用 3:1）。
Color cardoryEnsureWhiteContrast(Color color, {double minRatio = 4.5}) =>
    cardoryEnsureContrast(
      color,
      const Color(0xFFFFFFFF),
      minRatio: minRatio,
    );

/// 由背景色与强调色推导一套完整调色板。
///
/// 亮色背景：灰阶由背景色向黑/白 lerp，产生常规明暗文字阶。
/// 暗色背景：文字色阶由 surface 向白色方向 lerp，保证深底上有足够对比度。
CardoryPalette paletteFromColors(Color background, Color primary) {
  final bg = background;
  Color lerpTo(Color a, Color b, double t) => Color.lerp(a, b, t)!;
  final light = brightnessForBackground(bg) == Brightness.light;

  // 表面色：亮色下比背景更亮（接近白），暗色下比背景更亮一个台阶。
  final surface = light
      ? lerpTo(bg, Colors.white, 0.96)
      : lerpTo(bg, Colors.white, 0.14);
  // 强调色柔和底：亮色下向白，暗色下向表面色。
  final primarySoft = light
      ? Color.lerp(primary, Colors.white, 0.88)!
      : Color.lerp(primary, surface, 0.78)!;

  Color gray(double t) => lerpTo(surface, Colors.white, t);

  // 边框色：暗色下明显高于背景但低于文字，亮色下略深于表面。
  final borderColor = light
      ? lerpTo(surface, Colors.black, 0.10)
      : lerpTo(surface, Colors.white, 0.16);

  return CardoryPalette(
    white: light ? Color(0xFFFFFFFF) : surface,
    gray25: light
        ? lerpTo(surface, Colors.white, 0.96)
        : lerpTo(bg, surface, 0.5),
    gray50: bg,
    gray100: light ? lerpTo(bg, Colors.white, 0.55) : lerpTo(bg, surface, 0.85),
    gray200: borderColor,
    gray300: light ? lerpTo(bg, Colors.black, 0.10) : gray(0.22),
    gray400: light ? lerpTo(bg, Colors.black, 0.40) : gray(0.40),
    gray500: light ? lerpTo(bg, Colors.black, 0.48) : gray(0.55),
    gray600: light ? lerpTo(bg, Colors.black, 0.62) : gray(0.72),
    gray700: light ? lerpTo(bg, Colors.black, 0.74) : gray(0.85),
    gray800: light ? lerpTo(bg, Colors.black, 0.84) : gray(0.93),
    gray900: light ? lerpTo(bg, Colors.black, 0.90) : gray(0.98),
    primary: primary,
    primarySoft: primarySoft,
    success: light ? const Color(0xFF44B88A) : const Color(0xFF5CD0A0),
    error: light ? const Color(0xFFEF7180) : const Color(0xFFF28B97),
    warning: light ? const Color(0xFFF2A354) : const Color(0xFFF5B86E),
    pink: light ? const Color(0xFFCF79DF) : const Color(0xFFD998E5),
  );
}

/// 应用背景色与强调色：切换全局 [CardoryColors] 调色板。
///
/// 供 [buildCardoryTheme] 调用，使全应用硬编码颜色随主题变化。
void applyCardoryColors(Color background, Color primary) {
  CardoryColors.apply(paletteFromColors(background, primary));
}

Color cardoryTint(Color base, double amount) =>
    Color.lerp(base, CardoryColors.white, amount)!;

Color cardoryShade(Color base, double amount) =>
    Color.lerp(base, Colors.black, amount)!;
