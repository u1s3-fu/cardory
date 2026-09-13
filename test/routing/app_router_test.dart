import 'package:cardory/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 模拟应用层 vault 会话状态：redirect 门禁读取 [unlocked]，
/// 状态变化通过 [notifier] 通知 go_router 重新评估 redirect。
class _SessionState {
  _SessionState({required this.unlocked});

  bool unlocked;
  final ValueNotifier<bool> notifier = ValueNotifier<bool>(false);

  void dispose() => notifier.dispose();
}

void main() {
  /// 构建测试路由：工作台 Shell 透传子内容，内容区按位置渲染标记文本。
  (GoRouter, _SessionState) buildRouter({required bool unlocked}) {
    final session = _SessionState(unlocked: unlocked);
    final router = createAppRouter(
      vaultGateBuilder: (context) => const Scaffold(body: Text('门禁页')),
      workbenchShellBuilder: (context, child) => child,
      workbenchContentBuilder: (context, location) => switch (location) {
        WorkbenchToday() => const Text('工作台'),
        WorkbenchTodos() => const Text('待办区'),
        WorkbenchProjects() => const Text('项目区'),
        WorkbenchProjectDetail(:final projectId) => Text('项目详情:$projectId'),
        WorkbenchSettings() => const Text('设置区'),
      },
      isVaultUnlocked: () => session.unlocked,
      refreshListenable: session.notifier,
    );
    return (router, session);
  }

  testWidgets('门禁：未解锁时业务路由、占位路由与未知路径一律回到 /vault', (tester) async {
    final (router, session) = buildRouter(unlocked: false);
    addTearDown(session.dispose);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    // 冷启动落在门禁页。
    expect(router.routeInformationProvider.value.uri.path, vaultRoutePath);
    expect(find.text('门禁页'), findsOneWidget);

    // 直接访问工作台与各分区子路由被重定向回门禁页。
    for (final path in [
      workbenchRoutePath,
      todosRoutePath,
      projectsRoutePath,
      '$projectsRoutePath/project-1',
      settingsRoutePath,
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri.path,
        vaultRoutePath,
        reason: '$path 未解锁时应被拦截',
      );
      expect(find.text('工作台'), findsNothing);
    }

    // 访问占位业务路由同样被拦截。
    router.go(calendarRoutePath);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, vaultRoutePath);
    expect(find.text('门禁页'), findsOneWidget);

    // 未知路径也被拦截回门禁页。
    router.go('/no-such-page');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, vaultRoutePath);
  });

  testWidgets('解锁后可达工作台、分区子路由与受保护占位页；锁定后自动退回门禁页', (tester) async {
    final (router, session) = buildRouter(unlocked: false);
    addTearDown(session.dispose);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    // 解锁会话后进入工作台。
    session.unlocked = true;
    session.notifier.value = true;
    router.go(workbenchRoutePath);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, workbenchRoutePath);
    expect(find.text('工作台'), findsOneWidget);

    // 分区子路由：待办、项目与设置均为独立受门禁路由。
    router.go(todosRoutePath);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, todosRoutePath);
    expect(find.text('待办区'), findsOneWidget);

    router.go(projectsRoutePath);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, projectsRoutePath);
    expect(find.text('项目区'), findsOneWidget);

    // 项目详情携带路径参数。
    router.go('$projectsRoutePath/project-1');
    await tester.pumpAndSettle();
    expect(
      router.routeInformationProvider.value.uri.path,
      '$projectsRoutePath/project-1',
    );
    expect(find.text('项目详情:project-1'), findsOneWidget);

    router.go(settingsRoutePath);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, settingsRoutePath);
    expect(find.text('设置区'), findsOneWidget);

    // 工作台内可访问受保护占位页（渲染真实占位内容）。
    router.go(calendarRoutePath);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, calendarRoutePath);
    // 标题同时出现在 AppBar 与正文，正文含说明文字与返回入口。
    expect(find.text('以日历视图安排任务，即将在后续版本开放。'), findsOneWidget);
    expect(find.text('返回今日'), findsOneWidget);

    router.go(assetsRoutePath);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, assetsRoutePath);
    expect(find.text('全局素材与附件管理，即将在后续版本开放。'), findsOneWidget);

    // 会话锁定：状态变化触发 refresh，redirect 把当前页踢回门禁页。
    session.unlocked = false;
    session.notifier.value = false;
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, vaultRoutePath);
    expect(find.text('门禁页'), findsOneWidget);
    expect(find.text('工作台'), findsNothing);
  });

  testWidgets('解锁后未知路径收敛回工作台', (tester) async {
    final (router, session) = buildRouter(unlocked: true);
    addTearDown(session.dispose);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.go('/does-not-exist');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, workbenchRoutePath);
    expect(find.text('工作台'), findsOneWidget);
  });
}
