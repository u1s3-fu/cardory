import 'package:flutter/material.dart';

/// Cardory 设计系统：柔和蓝紫基调搭配轻盈的彩色状态层次。
///
/// 以「明快留白、低饱和状态色、圆润卡片」为原则：
/// - 雾蓝灰背景承接内容，蓝紫仅用于导航与关键动作
/// - 14px 圆角与细腻阴影建立层次，避免厚重的模板化面板
/// - 清晰字阶与克制的状态色，便于快速扫描项目进展
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

/// Cardory 设计系统：柔和蓝紫基调搭配轻盈的彩色状态层次。
///
/// 以「明快留白、低饱和状态色、圆润卡片」为原则：
/// - 雾蓝灰背景承接内容，蓝紫仅用于导航与关键动作
/// - 14px 圆角与细腻阴影建立层次，避免厚重的模板化面板
/// - 清晰字阶与克制的状态色，便于快速扫描项目进展
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
  gray400: Color(0xFF98A1BA),
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
    gray400: light ? lerpTo(bg, Colors.black, 0.30) : gray(0.40),
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

/// 构建 Cardory 全局主题。
///
/// [seed] 来自用户设置的强调色，[background] 为用户设置的背景色。
/// 调用时会先应用背景色+强调色推导的全局调色板，使全应用硬编码颜色随主题变化；
/// 并根据背景色亮度自动启用亮/暗模式。
ThemeData buildCardoryTheme(
  Color seed, {
  Color background = const Color(0xFFF5F6FC),
}) {
  applyCardoryColors(background, seed);
  final brightness = brightnessForBackground(background);
  final primary = seed;
  final primaryContainer = cardoryTint(seed, 0.88);
  final onPrimaryContainer = cardoryShade(seed, 0.24);

  final colorScheme =
      ColorScheme.fromSeed(seedColor: seed, brightness: brightness).copyWith(
        primary: primary,
        onPrimary: CardoryColors.white,
        primaryContainer: primaryContainer,
        onPrimaryContainer: onPrimaryContainer,
        secondary: CardoryColors.gray600,
        onSecondary: CardoryColors.white,
        secondaryContainer: CardoryColors.gray100,
        onSecondaryContainer: CardoryColors.gray700,
        surface: CardoryColors.white,
        onSurface: CardoryColors.gray900,
        surfaceContainerLowest: CardoryColors.white,
        surfaceContainerLow: CardoryColors.gray50,
        surfaceContainer: CardoryColors.gray100,
        onSurfaceVariant: CardoryColors.gray500,
        outline: CardoryColors.gray300,
        outlineVariant: CardoryColors.gray200,
        error: CardoryColors.error,
      );

  const buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );
  const buttonTextStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);

  final textThemeBase = brightness == Brightness.light
      ? Typography.material2021().black
      : Typography.material2021().white;
  final textTheme = textThemeBase
      .apply(
        bodyColor: CardoryColors.gray700,
        displayColor: CardoryColors.gray900,
        fontFamily: null,
      )
      .copyWith(
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: CardoryColors.gray900,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: CardoryColors.gray900,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          color: CardoryColors.gray900,
        ),
        titleSmall: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: CardoryColors.gray900,
        ),
        bodyLarge: TextStyle(
          fontSize: 14.5,
          height: 1.55,
          color: CardoryColors.gray700,
        ),
        bodyMedium: TextStyle(
          fontSize: 13.5,
          height: 1.5,
          color: CardoryColors.gray600,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          height: 1.45,
          color: CardoryColors.gray500,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: CardoryColors.gray700,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: CardoryColors.gray500,
        ),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: null,
    colorScheme: colorScheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: CardoryColors.gray50,
    dividerColor: CardoryColors.gray200,
    splashFactory: InkRipple.splashFactory,
    hoverColor: CardoryColors.gray100.withValues(alpha: 0.6),
    highlightColor: Colors.transparent,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: CardoryColors.white,
      shadowColor: Colors.black.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: CardoryColors.gray200),
      ),
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: CardoryColors.gray900,
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: CardoryColors.gray900,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: buttonShape,
        textStyle: buttonTextStyle,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            foregroundColor: CardoryColors.gray700,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: buttonShape,
            textStyle: buttonTextStyle,
            side: BorderSide(color: CardoryColors.gray300),
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.hovered)
                  ? CardoryColors.gray100
                  : null,
            ),
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: CardoryColors.gray600,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: buttonShape,
        textStyle: buttonTextStyle,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: CardoryColors.gray500,
        hoverColor: CardoryColors.gray100,
        shape: buttonShape,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CardoryColors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(color: CardoryColors.gray400, fontSize: 14),
      labelStyle: TextStyle(color: CardoryColors.gray500, fontSize: 14),
      border: _inputBorder(CardoryColors.gray300),
      enabledBorder: _inputBorder(CardoryColors.gray300),
      focusedBorder: _inputBorder(primary, width: 1.5),
      errorBorder: _inputBorder(CardoryColors.error),
      focusedErrorBorder: _inputBorder(CardoryColors.error, width: 1.5),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(isDense: true),
      menuStyle: MenuStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 0,
      backgroundColor: CardoryColors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: CardoryColors.gray900,
      ),
      contentTextStyle: TextStyle(
        fontSize: 14,
        height: 1.55,
        color: CardoryColors.gray600,
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: CardoryColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: CardoryColors.gray200),
      ),
      headerBackgroundColor: CardoryColors.gray50,
      headerForegroundColor: CardoryColors.gray900,
      headerHeadlineStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: CardoryColors.gray900,
      ),
      headerHelpStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: CardoryColors.gray500,
      ),
      weekdayStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: CardoryColors.gray500,
      ),
      dayStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return CardoryColors.gray300;
        if (states.contains(WidgetState.selected)) return CardoryColors.white;
        return CardoryColors.gray700;
      }),
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        if (states.contains(WidgetState.hovered)) return CardoryColors.gray100;
        return Colors.transparent;
      }),
      todayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return CardoryColors.white;
        return primary;
      }),
      todayBackgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      todayBorder: BorderSide(color: primary),
      yearStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      yearForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return CardoryColors.white;
        return CardoryColors.gray700;
      }),
      yearBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        if (states.contains(WidgetState.hovered)) return CardoryColors.gray100;
        return Colors.transparent;
      }),
      dividerColor: CardoryColors.gray200,
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: CardoryColors.gray600,
        shape: buttonShape,
        textStyle: buttonTextStyle,
      ),
      confirmButtonStyle: TextButton.styleFrom(
        foregroundColor: primary,
        shape: buttonShape,
        textStyle: buttonTextStyle,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CardoryColors.white,
        isDense: true,
        border: _inputBorder(CardoryColors.gray300),
        enabledBorder: _inputBorder(CardoryColors.gray300),
        focusedBorder: _inputBorder(primary, width: 1.5),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      surfaceTintColor: Colors.transparent,
      color: CardoryColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: CardoryColors.gray200),
      ),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 13.5, color: CardoryColors.gray700),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 66,
      elevation: 0,
      backgroundColor: CardoryColors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: primaryContainer,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? CardoryColors.white
              : CardoryColors.gray600,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? primary
              : CardoryColors.gray500,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? primary
                : CardoryColors.gray300,
          ),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? CardoryColors.white
              : states.contains(WidgetState.disabled)
                  ? CardoryColors.gray400
                  : CardoryColors.gray600,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : states.contains(WidgetState.disabled)
                  ? CardoryColors.gray100
                  : CardoryColors.white,
        ),
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? primary.withValues(alpha: 0.10)
              : Colors.transparent,
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineWidth: const WidgetStatePropertyAll(1),
      thumbColor: WidgetStatePropertyAll(CardoryColors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? primary
            : CardoryColors.gray300,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : CardoryColors.gray300,
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? primary.withValues(alpha: 0.08)
            : Colors.transparent,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: CardoryColors.white,
      selectedColor: CardoryColors.primarySoft,
      side: BorderSide(color: CardoryColors.gray300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: TextStyle(fontSize: 13, color: CardoryColors.gray700),
      secondaryLabelStyle: TextStyle(fontSize: 13, color: primary),
      checkmarkColor: primary,
      deleteIconColor: CardoryColors.gray400,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: CardoryColors.gray900,
      contentTextStyle: TextStyle(fontSize: 13.5, color: CardoryColors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: CardoryColors.gray900,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(fontSize: 12, color: CardoryColors.white),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? primary
            : states.contains(WidgetState.disabled)
                ? CardoryColors.gray100
                : CardoryColors.white,
      ),
      side: BorderSide(color: CardoryColors.gray300, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.hovered)
            ? primary.withValues(alpha: 0.08)
            : Colors.transparent,
      ),
    ),
    sliderTheme: const SliderThemeData(
      trackHeight: 4,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: CardoryColors.gray900,
      linearTrackColor: CardoryColors.gray100,
    ),
    dividerTheme: DividerThemeData(
      color: CardoryColors.gray200,
      thickness: 1,
      space: 1,
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
  );
}

OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: color, width: width),
    );

/// 标准内容卡片：白底、14px 圆角、细边框和克制阴影。
BoxDecoration cardoryCard({Color? color, double radius = 14}) => BoxDecoration(
  color: color ?? CardoryColors.white,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: CardoryColors.gray200),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.045),
      blurRadius: 18,
      offset: const Offset(0, 7),
    ),
  ],
);

/// 品牌深色头图（项目详情页顶部）。
BoxDecoration cardoryDarkHero({double radius = 18}) => BoxDecoration(
  gradient: const LinearGradient(
    colors: [Color(0xFF4541A8), Color(0xFF6B62DF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ),
  borderRadius: BorderRadius.circular(radius),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.14),
      blurRadius: 24,
      offset: const Offset(0, 12),
    ),
  ],
);

/// 各表现页面通用的标准内容卡片装饰。
BoxDecoration cardDecoration() => cardoryCard();

/// 项目摘要使用的品牌深色卡片装饰。
BoxDecoration darkCardDecoration() => cardoryDarkHero();
