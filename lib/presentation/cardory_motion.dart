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
/// - [fast]：小组件状态显隐（侧栏项高亮、图标/文字淡入淡出）
/// - [base]：组件状态切换（侧栏展开收起、工作台分区切换）
///
/// 曲线约定：
/// - 出现/进入用 [outCubic]（先快后慢，干净利落）
/// - 退出/消失用 [inCubic]（先慢后快，让位给新内容）
/// - 往返/尺寸/位移用 [inOutCubic]（平滑对称，不拖泥带水）
///
/// 时长只保留实际在用的一档：宁少勿滥，多出来的档位只会被滥用成
/// 「随手挑一个时长」。退出时长由调用方取进入的 75%（见分区转场与
/// 侧栏高亮），不进本表，避免出现「进 220 / 退 300」这类倒挂组合。
abstract final class CardoryMotion {
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 220);

  static const Curve outCubic = Curves.easeOutCubic;
  static const Curve inCubic = Curves.easeInCubic;
  static const Curve inOutCubic = Curves.easeInOutCubic;
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
    // 转场时长由路由的 transitionDuration 决定，PageTransitionsBuilder
    // 拿不到它，因此这里按 cardoryAnimDuration 的同一判据直接短路：
    // 系统「减弱动态效果」开启时原样返回子组件，等价于全部时长归零。
    if (MediaQuery.disableAnimationsOf(context)) return child;

    // 新页面：从右 6% 进入。
    final slide = Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: animation,
            curve: CardoryMotion.outCubic,
            reverseCurve: CardoryMotion.inCubic,
          ),
        );
    // 旧页面：被新页面覆盖时轻微下沉，形成层级关系。
    final secondarySlide =
        Tween<Offset>(begin: Offset.zero, end: const Offset(0, 0.02)).animate(
          CurvedAnimation(
            parent: secondaryAnimation,
            curve: CardoryMotion.outCubic,
            reverseCurve: CardoryMotion.inCubic,
          ),
        );
    // 新页面：柔和淡入。曲线与 slide 保持一致，避免同一动画里出现两套缓动。
    final fade = CurvedAnimation(
      parent: animation,
      curve: CardoryMotion.outCubic,
      reverseCurve: CardoryMotion.inCubic,
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
