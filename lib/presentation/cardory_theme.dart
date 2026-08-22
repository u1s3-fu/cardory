import 'package:flutter/material.dart';

import 'cardory_motion.dart';
import 'cardory_palette.dart';

export 'cardory_motion.dart';
export 'cardory_palette.dart';

/// Cardory 设计系统：扁平化的蓝紫基调搭配克制的功能色。
///
/// 以「明快留白、边框分层、克制状态色」为原则：
/// - 雾蓝灰背景承接内容，蓝紫仅用于导航与关键动作
/// - 12–16px 圆角与浅阴影建立层次，不使用渐变与厚重阴影
/// - 清晰字阶与克制的状态色，便于快速扫描项目进展
///
/// 调色板与色彩工具见 `cardory_palette.dart`，本文件只负责主题构建。

/// 所有可点击控件统一使用的鼠标光标（桌面端 hover 反馈）。
const WidgetStateProperty<MouseCursor> _cardoryClickCursor =
    WidgetStatePropertyAll(SystemMouseCursors.click);

/// 构建 Cardory 全局主题。
///
/// [seed] 来自用户设置的强调色，[background] 为用户设置的背景色。
/// 调用时会先应用背景色+强调色推导的全局调色板，使全应用硬编码颜色随主题变化；
/// 并根据背景色亮度自动启用亮/暗模式。
ThemeData buildCardoryTheme(
  Color seed, {
  Color background = const Color(0xFFF5F6FC),
}) {
  // 强调色若过浅，白字按钮/文字会不达标；统一加深到与白色对比度 ≥ 4.5:1。
  final primary = cardoryEnsureWhiteContrast(seed);
  applyCardoryColors(background, primary);
  final brightness = brightnessForBackground(background);
  final primaryContainer = cardoryTint(primary, 0.88);
  final onPrimaryContainer = cardoryShade(primary, 0.24);

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
    // 扁平化：桌面端彻底隐藏滚动条，保留滚轮/键盘/触控板滚动。
    // 任何平台都不构建 Scrollbar 组件（见 CardoryScrollBehavior）。
    scrollbarTheme: ScrollbarThemeData(
      thumbVisibility: const WidgetStatePropertyAll(false),
      trackVisibility: const WidgetStatePropertyAll(false),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      interactive: true,
      thickness: const WidgetStatePropertyAll(0),
      minThumbLength: 44,
      radius: const Radius.circular(8),
      mainAxisMargin: 2,
      crossAxisMargin: 2,
      thumbColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    // 全平台统一使用「淡入 + 轻微横移」的页面转场，见 CardoryPageTransitionsBuilder。
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CardoryPageTransitionsBuilder(),
        TargetPlatform.iOS: CardoryPageTransitionsBuilder(),
        TargetPlatform.windows: CardoryPageTransitionsBuilder(),
        TargetPlatform.macOS: CardoryPageTransitionsBuilder(),
        TargetPlatform.linux: CardoryPageTransitionsBuilder(),
        TargetPlatform.fuchsia: CardoryPageTransitionsBuilder(),
      },
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
      ).copyWith(mouseCursor: _cardoryClickCursor),
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
            mouseCursor: _cardoryClickCursor,
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
      ).copyWith(mouseCursor: _cardoryClickCursor),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: CardoryColors.gray500,
        hoverColor: CardoryColors.gray100,
        shape: buttonShape,
      ).copyWith(mouseCursor: _cardoryClickCursor),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CardoryColors.white,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      hintStyle: TextStyle(color: CardoryColors.gray500, fontSize: 14),
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
      circularTrackColor: CardoryColors.gray100,
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

/// 标准内容卡片：白底、14px 圆角、极浅边框（扁平化，不使用阴影）。
BoxDecoration cardoryCard({Color? color, double radius = 14}) => BoxDecoration(
  color: color ?? CardoryColors.white,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: CardoryColors.gray100),
);

/// 品牌深色头图（项目详情页顶部）：纯色 + 极浅阴影（扁平化，不使用渐变）。
BoxDecoration cardoryDarkHero({double radius = 18}) => BoxDecoration(
  color: cardoryShade(CardoryColors.primary, 0.18),
  borderRadius: BorderRadius.circular(radius),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ],
);

/// 各表现页面通用的标准内容卡片装饰。
BoxDecoration cardDecoration() => cardoryCard();

/// Cardory 全局滚动行为：桌面端彻底隐藏滚动条。
///
/// [buildScrollbar] 直接返回子组件，任何平台都不构建 Scrollbar 组件，
/// 但保留滚轮 / 键盘 / 触控板滚动能力。移动端也遵循同一策略，
/// 与主题中的 `scrollbarTheme` 保持一致。
class CardoryScrollBehavior extends MaterialScrollBehavior {
  const CardoryScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
