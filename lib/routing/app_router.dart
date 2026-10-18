import 'package:cardory/presentation/cardory_motion.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 保险库门禁页，是唯一不受门禁保护的路由。
///
/// 应用始终从该页启动：创建 / 解锁保险库成功后才切换到 [workbenchRoutePath]。
const vaultRoutePath = '/vault';

/// 解锁后的工作台主页（今日视图 / 工作台 Shell）。
const workbenchRoutePath = '/today';

/// 工作台分区子路由：待办列表、日历、时间、项目列表、项目详情与设置。
const todosRoutePath = '/todos';
const calendarRoutePath = '/calendar';
const timeRoutePath = '/time';
const ganttRoutePath = '/gantt';
const projectsRoutePath = '/projects';
const settingsRoutePath = '/settings';

/// 业务路由（破坏性版本阶段 §6）：/vault、/today、/todos、/calendar、
/// /time、/gantt、/projects、/projects/:projectId、/assets、/settings
/// 全部落地为真实页面（工作台分区为 Shell 子路由）。
const assetsRoutePath = '/assets';

/// 工作台分区在导航序列中的序号：推导分区切换转场方向的依据。
/// 项目详情挂在 /projects 之下，取比列表深半级的 5.5，于是
/// 「列表 → 详情」为前进、「详情 → 列表」为后退，
/// 而「详情 A → 详情 B」同序，只淡入不横移。
const Map<String, double> _workbenchSectionOrder = <String, double>{
  workbenchRoutePath: 0,
  todosRoutePath: 1,
  calendarRoutePath: 2,
  timeRoutePath: 3,
  ganttRoutePath: 4,
  projectsRoutePath: 5,
  assetsRoutePath: 6,
  settingsRoutePath: 7,
};
const double _projectDetailSectionOrder = 5.5;

/// 工作台 Shell 内的内容区目标（sealed：穷举安全）。
sealed class WorkbenchLocation {
  const WorkbenchLocation();
}

class WorkbenchToday extends WorkbenchLocation {
  const WorkbenchToday();
}

class WorkbenchTodos extends WorkbenchLocation {
  const WorkbenchTodos();
}

class WorkbenchProjects extends WorkbenchLocation {
  const WorkbenchProjects();
}

class WorkbenchProjectDetail extends WorkbenchLocation {
  const WorkbenchProjectDetail(this.projectId);

  final String projectId;
}

class WorkbenchAssets extends WorkbenchLocation {
  const WorkbenchAssets();
}

class WorkbenchSettings extends WorkbenchLocation {
  const WorkbenchSettings();
}

class WorkbenchCalendar extends WorkbenchLocation {
  const WorkbenchCalendar();
}

class WorkbenchTime extends WorkbenchLocation {
  const WorkbenchTime();
}

class WorkbenchGantt extends WorkbenchLocation {
  const WorkbenchGantt();
}

/// 工作台 Shell 构建器：包住路由子内容（顶部栏 / 侧栏 / 底部导航由 Shell 提供）。
typedef WorkbenchShellBuilder =
    Widget Function(BuildContext context, Widget child);

/// 工作台内容区构建器：按路由位置渲染分区内容。
typedef WorkbenchContentBuilder =
    Widget Function(BuildContext context, WorkbenchLocation location);

/// 构建应用路由。
///
/// 门禁语义：
/// - [vaultRoutePath] 始终可达，承担保险库创建 / 解锁；
/// - 工作台分区（/today、/todos、/calendar、/projects、/settings）与项目
///   详情（/projects/:projectId）通过 [ShellRoute] 共享同一个工作台 Shell，
///   Shell 持有工作区控制器，子路由只切换内容区；
/// - 其余业务路由（占位页）通过 [isVaultUnlocked] 判定，未解锁访问一律
///   重定向回门禁页；
/// - [refreshListenable] 在 vault 状态变化时通知 go_router 重新评估
///   redirect，保证会话过期后立即退回门禁，业务页无法绕过。
GoRouter createAppRouter({
  required WidgetBuilder vaultGateBuilder,
  required WorkbenchShellBuilder workbenchShellBuilder,
  required WorkbenchContentBuilder workbenchContentBuilder,
  bool Function()? isVaultUnlocked,
  Listenable? refreshListenable,
  GlobalKey<NavigatorState>? navigatorKey,
  int Function()? vaultPageEpoch,
}) {
  // 受保护路由的门禁：未解锁一律回 /vault。
  String? protectedRedirect(BuildContext context, GoRouterState state) =>
      (isVaultUnlocked?.call() ?? false) ? null : vaultRoutePath;

  // 通配路由：未知 / 根路径收敛到工作台（未解锁时仍被门禁拦截）。
  String? wildcardRedirect(BuildContext context, GoRouterState state) =>
      (isVaultUnlocked?.call() ?? false) ? workbenchRoutePath : vaultRoutePath;

  // 上一次所在分区。pageBuilder 每次导航只执行一次（同 key 的路由会被
  // Navigator 复用而不重建），所以这里读到的是「来自哪里」，用来决定新内容
  // 从哪一侧进入。初值为工作台首页：冷启动那次进入同序，只淡入不横移。
  var lastWorkbenchPath = workbenchRoutePath;

  /// 分区在导航序列中的序号。路径集合固定，兜底分支实际不可达。
  double sectionOrderOf(String path) => path.startsWith('$projectsRoutePath/')
      ? _projectDetailSectionOrder
      : _workbenchSectionOrder[path] ?? _projectDetailSectionOrder;

  /// 分区切换转场：新内容按导航方向横向滑入，只动 transform / opacity。
  ///
  /// 这里早期用 NoTransitionPage 让子内容瞬时切换，为的是避开过渡动画期间
  /// 旧内容（看板等 shrinkWrap 列表）在新布局约束下继续重排。现在的做法从
  /// 两个方向上解掉那个问题：转场只动 transform / opacity，不触碰任何布局
  /// 属性，整段过渡里新旧内容的约束恒定；子内容再外包一层 [RepaintBoundary]，
  /// 让内容的栅格化结果整块复用，转场期间每帧只做一次图层变换。
  ///
  /// [direction] 为目标分区与来源分区的序号差：>0 前进（新内容从右侧进入）、
  /// <0 后退（从左侧进入）、0 同层（不动，只淡入）。配合退出时长短于进入
  /// 时长，切换有明确的因果感而不是无差别的一刀切。
  Widget buildWorkbenchTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
    double direction,
  ) {
    // 系统「减弱动态效果」：与 cardoryAnimDuration 同一判据，直接短路。
    if (MediaQuery.disableAnimationsOf(context)) return child;

    final curved = CurvedAnimation(
      parent: animation,
      curve: CardoryMotion.outCubic,
      reverseCurve: CardoryMotion.inCubic,
    );
    final slide = Tween<Offset>(
      begin: Offset(0.06 * direction, 0),
      end: Offset.zero,
    ).animate(curved);
    // 曲线与页面级转场保持一致，避免同一套动效里出现两套缓动。
    final fade = CurvedAnimation(
      parent: animation,
      curve: CardoryMotion.outCubic,
      reverseCurve: CardoryMotion.inCubic,
    );

    return RepaintBoundary(
      child: SlideTransition(
        position: slide,
        child: FadeTransition(opacity: fade, child: child),
      ),
    );
  }

  /// 工作台分区页：按目标分区与上次所在分区的序号差推导转场方向。
  ///
  /// 只在 pageBuilder 内调用，每次导航执行一次。
  CustomTransitionPage<void> workbenchSectionPage(
    BuildContext context,
    String path,
    WorkbenchLocation location,
  ) {
    final direction = sectionOrderOf(path) - sectionOrderOf(lastWorkbenchPath);
    if (path != lastWorkbenchPath) lastWorkbenchPath = path;
    return CustomTransitionPage<void>(
      key: ValueKey('workbench-$path'),
      // 退场取进场的 75%（动效规范）：退得更快，把空间让给新内容。
      transitionDuration: cardoryAnimDuration(context, CardoryMotion.base),
      reverseTransitionDuration: cardoryAnimDuration(
        context,
        const Duration(milliseconds: 165),
      ),
      child: workbenchContentBuilder(context, location),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          buildWorkbenchTransition(
            context,
            animation,
            secondaryAnimation,
            child,
            direction,
          ),
    );
  }

  // 工作台子路由：分区之间带方向感的横向滑入转场，见 buildWorkbenchTransition。
  GoRoute workbenchChildRoute(String path, WorkbenchLocation location) =>
      GoRoute(
        path: path,
        pageBuilder: (context, state) =>
            workbenchSectionPage(context, path, location),
        redirect: protectedRedirect,
      );

  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: vaultRoutePath,
    refreshListenable: refreshListenable,
    routes: [
      GoRoute(
        path: vaultRoutePath,
        // 门禁页用 pageBuilder + epoch key：锁定后再回 /vault 时强制重建页面，
        // 让 gate 重新检测保险库状态（避免沿用解锁期间的旧表单状态）。
        pageBuilder: (context, state) => MaterialPage<void>(
          key: ValueKey('vault-epoch-${vaultPageEpoch?.call() ?? 0}'),
          child: vaultGateBuilder(context),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            workbenchShellBuilder(context, child),
        routes: [
          workbenchChildRoute(workbenchRoutePath, const WorkbenchToday()),
          workbenchChildRoute(todosRoutePath, const WorkbenchTodos()),
          workbenchChildRoute(calendarRoutePath, const WorkbenchCalendar()),
          workbenchChildRoute(timeRoutePath, const WorkbenchTime()),
          workbenchChildRoute(ganttRoutePath, const WorkbenchGantt()),
          workbenchChildRoute(projectsRoutePath, const WorkbenchProjects()),
          workbenchChildRoute(assetsRoutePath, const WorkbenchAssets()),
          GoRoute(
            path: '$projectsRoutePath/:projectId',
            pageBuilder: (context, state) {
              final projectId = state.pathParameters['projectId'] ?? '';
              return workbenchSectionPage(
                context,
                '$projectsRoutePath/$projectId',
                WorkbenchProjectDetail(projectId),
              );
            },
            redirect: protectedRedirect,
          ),
          workbenchChildRoute(settingsRoutePath, const WorkbenchSettings()),
        ],
      ),
      GoRoute(
        path: '/:unmatched(.*)',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
        redirect: wildcardRedirect,
      ),
    ],
  );
}
