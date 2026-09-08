import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 保险库门禁页，是唯一不受门禁保护的路由。
///
/// 应用始终从该页启动：创建 / 解锁保险库成功后才切换到 [workbenchRoutePath]。
const vaultRoutePath = '/vault';

/// 解锁后的工作台主页（今日视图 / 工作台 Shell）。
const workbenchRoutePath = '/today';

/// 业务路由规划（破坏性版本阶段 §6）：
/// - /vault、/today 已落地；
/// - 项目分区（/projects、/projects/:projectId）与设置（/settings）
///   当前仍由工作台分区与页面内导航承担，后续拆分为独立路由；
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

/// 构建应用路由。
///
/// 门禁语义：
/// - [vaultRoutePath] 始终可达，承担保险库创建 / 解锁；
/// - 其余业务路由（工作台与占位页）通过 [isVaultUnlocked] 判定，
///   未解锁访问一律重定向回门禁页；
/// - [refreshListenable] 在 vault 状态变化时通知 go_router 重新评估
///   redirect，保证会话过期后立即退回门禁，业务页无法绕过。
GoRouter createAppRouter({
  required WidgetBuilder vaultGateBuilder,
  required WidgetBuilder workbenchBuilder,
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
      GoRoute(
        path: workbenchRoutePath,
        builder: (context, state) => workbenchBuilder(context),
        redirect: protectedRedirect,
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
