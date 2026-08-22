import 'package:flutter/material.dart';

/// 按系统「减弱动态效果」设置换算动画时长：
/// 开启时返回 [Duration.zero] 立即完成，满足无障碍（WCAG）要求。
///
/// 所有显式动画时长都应经此函数换算。
Duration cardoryAnimDuration(BuildContext context, Duration duration) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

/// Cardory 全局动效系统：统一节奏（时长）与缓动曲线。
///
/// 时长分层（由快到慢）：
/// - [micro]：悬停、按压等瞬时反馈
/// - [fast]：小组件状态显隐（侧栏项高亮、图标/文字淡入淡出）
/// - [base]：组件状态切换（侧栏展开收起、内容区切换）
/// - [slow]：面板级过渡
/// - [page]：页面转场
///
/// 曲线约定：
/// - 出现/进入用 [outCubic]（先快后慢，干净利落）
/// - 退出/消失用 [inCubic]（先慢后快，让位给新内容）
/// - 往返/尺寸/位移用 [inOutCubic]（平滑对称，不拖泥带水）
/// - 小元素出现用 [pop]（轻微回弹，克制使用，不滥用）
abstract final class CardoryMotion {
  static const Duration micro = Duration(milliseconds: 120);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 300);
  static const Duration page = Duration(milliseconds: 320);

  static const Curve outCubic = Curves.easeOutCubic;
  static const Curve inCubic = Curves.easeInCubic;
  static const Curve inOutCubic = Curves.easeInOutCubic;
  static const Curve pop = Curves.easeOutBack;
}

/// 页面转场：淡入 + 轻微横移 + 旧页轻微下沉，形成清晰的进出层级。
///
/// 取代 Material 默认的缩放转场，方向感更明确、观感更克制：
/// 新页面从右 6% 平滑进入并淡入（[CardoryMotion.outCubic]），
/// 旧页面随二级动画轻微下沉形成景深，返回时自然反转。
class CardoryPageTransitionsBuilder extends PageTransitionsBuilder {
  const CardoryPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 新页面：从右 6% 进入。
    final slide = Tween<Offset>(
      begin: const Offset(0.06, 0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: animation,
        curve: CardoryMotion.outCubic,
        reverseCurve: CardoryMotion.inCubic,
      ),
    );
    // 旧页面：被新页面覆盖时轻微下沉，形成层级关系。
    final secondarySlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0, 0.02),
    ).animate(
      CurvedAnimation(
        parent: secondaryAnimation,
        curve: CardoryMotion.outCubic,
        reverseCurve: CardoryMotion.inCubic,
      ),
    );
    // 新页面：柔和淡入。
    final fade = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    return SlideTransition(
      position: secondarySlide,
      child: SlideTransition(
        position: slide,
        child: FadeTransition(opacity: fade, child: child),
      ),
    );
  }
}
