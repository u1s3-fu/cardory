import 'package:flutter/material.dart';

import 'cardory_motion.dart';
import 'cardory_palette.dart';

export 'cardory_breakpoints.dart';
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

/// 随包字体链：西文/数字 Inter，中文思源黑体，兜底系统微软雅黑。
///
/// 组件级 textStyle（按钮/弹窗/SnackBar/Tooltip/Chip/菜单等）必须显式携带
/// 这条链：这些组件在 SDK 内部用样式**替换**环境 DefaultTextStyle 而非
/// 合并，样式里不写 fontFamily 时西文直接落到引擎默认字体
/// （Windows = Segoe UI），与页面正文的 Inter 字形不一致。
/// ThemeData 的 fontFamilyFallback 只能补进 textTheme，够不到组件样式。
const TextStyle _cardoryFontChain = TextStyle(
  fontFamily: 'Inter',
  fontFamilyFallback: ['NotoSansSC', 'Microsoft YaHei UI'],
);

/// 圆角阶梯。
///
/// 此前全库散落 2/4/5/6/9/10/12/14/16/17/18/999 共 12 种圆角，
/// 内外嵌套的层级感被数量淹没。收敛为四级 + 一个装饰例外：
/// 内嵌微件 sm → 控件 md → 卡片 lg → 面板 xl → 胶囊 pill（仅限
/// 圆形色板、圆点这类「圆润到顶」的装饰形状；普通容器一律走四级）。
abstract final class CardoryRadius {
  /// 标签、色点、进度条等内嵌微件。
  static const double sm = 8;

  /// 按钮、输入框、入口行等控件。
  static const double md = 12;

  /// 标准卡片。
  static const double lg = 14;

  /// 大面板、看板列、对话框。
  static const double xl = 16;

  /// 胶囊/圆点装饰例外（999 视觉上等同完全圆润）。
  static const double pill = 999;
}

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
  final buttonTextStyle = _cardoryFontChain.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  final textThemeBase = brightness == Brightness.light
      ? Typography.material2021().black
      : Typography.material2021().white;
  // 字阶：相邻级别至少差 2px，避免 11/12/12.5/13/13.5 挤在一起无法区分。
  // 正文 14 / 次要 14 / 辅助 13 / 微标签 12 —— 四级明度与字号同步拉开。
  //
  // 字体随包分发（见 pubspec.yaml fonts 区块）：西文/数字用 Inter，
  // 中文走 fontFamilyFallback 命中思源黑体（NotoSansSC），最后兜底系统
  // 微软雅黑。显式声明回退链，避免 Windows 桌面端中西文分落在
  // Segoe UI / 系统回退字体上，同字号同字重观感粗细不一致。
  // 字重三档规则（全库统一，只允许 w500/w600/w700，禁止其它档位）：
  //   w700 —— 区块/页面标题、看板列头、大数字、选中态导航与日期、
  //           彩色状态徽章、逾期警示、品牌字标；
  //   w600 —— 条目标题（任务/文件/项目名）、按钮文本、设置分组头、
  //           链接/计数/彩色 meta 等次强调；
  //   w500 —— 正文、次要 meta、未选中态。
  //
  // 组件级 textStyle（按钮/弹窗/SnackBar 等）不走 textTheme：SDK 内部用
  // 样式替换环境 DefaultTextStyle，必须显式带字体链（见 _cardoryFontChain）。
  final textTheme = textThemeBase
      .apply(
        bodyColor: CardoryColors.gray800,
        displayColor: CardoryColors.gray900,
        fontFamily: 'Inter',
        fontFamilyFallback: const ['NotoSansSC', 'Microsoft YaHei UI'],
      )
      .copyWith(
        headlineSmall: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          color: CardoryColors.gray900,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: CardoryColors.gray900,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: CardoryColors.gray900,
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: CardoryColors.gray900,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          height: 1.55,
          fontWeight: FontWeight.w500,
          color: CardoryColors.gray800,
        ),
        // 正文级（13/14px）升 Medium(w500)：像素级 A/B 实验结论——
        // Flutter Windows 两条光栅化路径均不执行 hinting，CFF 小字号
        // 中文笔画偏细且同串不均；升 Medium 后墨量 +18%，逐字粗细 CV
        // 全场最低（7.0%）。标题级 w600/w700 与 Inter 同档不受影响。
        // 13px 再加深两档灰（gray600→gray700）：Medium 之外的备用杠杆，
        // 提升细笔画与白底的对比度。
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.5,
          fontWeight: FontWeight.w500,
          color: CardoryColors.gray700,
        ),
        bodySmall: TextStyle(
          fontSize: 13,
          height: 1.45,
          fontWeight: FontWeight.w500,
          color: CardoryColors.gray700,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: CardoryColors.gray800,
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
    // 与 textTheme 的随包字体保持一致：为未经 textTheme 覆盖的组件
    // 默认样式兜底。fallback 必须在这里再传一次：ThemeData 只把 fontFamily
    // 应用到默认字阶再与自定义 textTheme 逐字段合并，下方 copyWith 新建的
    // 9 个字阶自身没有 fallback，不传这个参数回退链会在合并后丢失。
    fontFamily: 'Inter',
    fontFamilyFallback: const ['NotoSansSC', 'Microsoft YaHei UI'],
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
        borderRadius: BorderRadius.all(Radius.circular(CardoryRadius.lg)),
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
      titleTextStyle: _cardoryFontChain.copyWith(
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
            borderRadius: BorderRadius.all(Radius.circular(CardoryRadius.md)),
          ),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      elevation: 0,
      backgroundColor: CardoryColors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(CardoryRadius.xl)),
      ),
      titleTextStyle: _cardoryFontChain.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: CardoryColors.gray900,
      ),
      contentTextStyle: _cardoryFontChain.copyWith(
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
      headerHeadlineStyle: _cardoryFontChain.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: CardoryColors.gray900,
      ),
      headerHelpStyle: _cardoryFontChain.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: CardoryColors.gray500,
      ),
      weekdayStyle: _cardoryFontChain.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: CardoryColors.gray500,
      ),
      dayStyle: _cardoryFontChain.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
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
      yearStyle: _cardoryFontChain.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
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
        _cardoryFontChain.copyWith(fontSize: 14, color: CardoryColors.gray700),
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
        (states) => _cardoryFontChain.copyWith(
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
        textStyle: WidgetStatePropertyAll(
          _cardoryFontChain.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
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
      labelStyle: _cardoryFontChain.copyWith(
        fontSize: 13,
        color: CardoryColors.gray700,
      ),
      secondaryLabelStyle: _cardoryFontChain.copyWith(
        fontSize: 13,
        color: primary,
      ),
      checkmarkColor: primary,
      deleteIconColor: CardoryColors.gray400,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: CardoryColors.gray900,
      contentTextStyle: _cardoryFontChain.copyWith(
        fontSize: 14,
        color: CardoryColors.white,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: CardoryColors.gray900,
        borderRadius: BorderRadius.circular(CardoryRadius.sm),
      ),
      textStyle: _cardoryFontChain.copyWith(
        fontSize: 12,
        color: CardoryColors.white,
      ),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CardoryRadius.sm),
      ),
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
    // 进度条是「正在推进」的语义，用重点色而非中性深灰；
    // 此前全界面唯一的靛紫只出现在徽章 10% 浅底上，等于没有重点色。
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: CardoryColors.gray200,
      circularTrackColor: CardoryColors.gray200,
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

/// 标准内容卡片：白底、14px 圆角、可见边框（扁平化，不使用阴影）。
///
/// 边框用 gray200 而非 gray100：gray100 与白底的对比度仅约 1.06:1，
/// 卡片边界实际上不可见，白卡浮在灰底上时整片糊在一起。
/// gray200 能勾出边界，同时保持发丝级的克制。
BoxDecoration cardoryCard({Color? color, double radius = CardoryRadius.lg}) =>
    BoxDecoration(
      color: color ?? CardoryColors.white,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: CardoryColors.gray200),
    );

/// 嵌套「凹槽」容器：看板列等承载卡片的底板。
///
/// 卡片嵌套时若内外同色同边框会糊成一片（原实现里看板列与项目卡
/// 都是白底 + 极浅边框）。凹槽用比页面更沉的底色，让内部的白卡浮起来。
BoxDecoration cardoryRecessed({double radius = CardoryRadius.xl}) =>
    BoxDecoration(
      color: CardoryColors.gray100,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: CardoryColors.gray200),
    );

/// 品牌深色头图（项目详情页顶部）：纯色 + 极浅阴影（扁平化，不使用渐变）。
///
/// 圆角走 xl 档（此前默认 18 不在档位表内）。
BoxDecoration cardoryDarkHero({double radius = CardoryRadius.xl}) =>
    BoxDecoration(
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
  ) => child;
}
