import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 保险库门禁页，是唯一不受门禁保护的路由。
///
/// 应用始终从该页启动：创建 / 解锁保险库成功后才切换到 [workbenchRoutePath]。
const vaultRoutePath = '/vault';

/// 解锁后的工作台主页（今日视图 / 工作台 Shell）。
const workbenchRoutePath = '/today';

/// 工作台分区子路由：待办列表、项目列表、项目详情与设置。
const todosRoutePath = '/todos';
const projectsRoutePath = '/projects';
const settingsRoutePath = '/settings';

/// 业务路由规划（破坏性版本阶段 §6）：
/// - /vault、/today、/todos、/projects、/projects/:projectId、/settings 已落地；
/// - 以下模块暂以「受保护占位页」挂载，页面就绪后替换占位 builder。
const calendarRoutePath = '/calendar';
const timeRoutePath = '/time';
const ganttRoutePath = '/gantt';
const assetsRoutePath = '/assets';

/// 占位路由清单：{ path, 标题, 图标, 说明 }。
///
/// 由 [createAppRouter] 统一展开为受门禁保护的路由。
const placeholderRoutes =
    <({String path, String title, IconData icon, String description})>[
      (
        path: calendarRoutePath,
        title: '日历',
        icon: Icons.calendar_month_outlined,
        description: '以日历视图安排任务，即将在后续版本开放。',
      ),
      (
        path: timeRoutePath,
        title: '时间与番茄钟',
        icon: Icons.timer_outlined,
        description: '时间记录与番茄钟专注模块，即将在后续版本开放。',
      ),
      (
        path: ganttRoutePath,
        title: '甘特图',
        icon: Icons.view_timeline_outlined,
        description: '项目排期甘特视图，即将在后续版本开放。',
      ),
      (
        path: assetsRoutePath,
        title: '素材库',
        icon: Icons.folder_outlined,
        description: '全局素材与附件管理，即将在后续版本开放。',
      ),
    ];

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

class WorkbenchSettings extends WorkbenchLocation {
  const WorkbenchSettings();
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
/// - 工作台四个分区（/today、/todos、/projects、/settings）与项目详情
///   （/projects/:projectId）通过 [ShellRoute] 共享同一个工作台 Shell，
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

  // 工作台子路由使用无过渡页：子内容在同一 Shell 内瞬时切换，避免页面
  // 过渡动画期间旧内容（看板等 shrinkWrap 列表）在新布局约束下继续重排。
  GoRoute workbenchChildRoute(String path, WorkbenchLocation location) =>
      GoRoute(
        path: path,
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: ValueKey('workbench-$path'),
          child: workbenchContentBuilder(context, location),
        ),
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
          workbenchChildRoute(projectsRoutePath, const WorkbenchProjects()),
          GoRoute(
            path: '$projectsRoutePath/:projectId',
            pageBuilder: (context, state) => NoTransitionPage<void>(
              key: ValueKey(
                'workbench-project-${state.pathParameters['projectId']}',
              ),
              child: workbenchContentBuilder(
                context,
                WorkbenchProjectDetail(state.pathParameters['projectId'] ?? ''),
              ),
            ),
            redirect: protectedRedirect,
          ),
          workbenchChildRoute(settingsRoutePath, const WorkbenchSettings()),
        ],
      ),
      for (final entry in placeholderRoutes)
        GoRoute(
          path: entry.path,
          builder: (context, state) => _PlaceholderPage(entry: entry),
          redirect: protectedRedirect,
        ),
      GoRoute(
        path: '/:unmatched(.*)',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
        redirect: wildcardRedirect,
      ),
    ],
  );
}

/// 「开发中」占位页：用于尚未实现的业务模块，保留路由结构便于后续替换。
class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({required this.entry});

  final ({String path, String title, IconData icon, String description}) entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.title),
        leading: IconButton(
          tooltip: '返回今日',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(workbenchRoutePath),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(entry.icon, size: 56, color: colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  entry.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  entry.description,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => context.go(workbenchRoutePath),
                  icon: const Icon(Icons.today_outlined),
                  label: const Text('返回今日'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
