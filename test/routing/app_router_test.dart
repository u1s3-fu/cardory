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
        WorkbenchCalendar() => const Text('日历区'),
        WorkbenchTime() => const Text('时间区'),
        WorkbenchGantt() => const Text('甘特区'),
        WorkbenchProjects() => const Text('项目区'),
        WorkbenchAssets() => const Text('资产库区'),
        WorkbenchProjectDetail(:final projectId) => Text('项目详情:$projectId'),
        WorkbenchSettings() => const Text('设置区'),
      },
      isVaultUnlocked: () => session.unlocked,
      refreshListenable: session.notifier,
    );
    return (router, session);
  }

  testWidgets('门禁：未解锁时业务路由与未知路径一律回到 /vault', (tester) async {
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
      calendarRoutePath,
      timeRoutePath,
      ganttRoutePath,
      projectsRoutePath,
      '$projectsRoutePath/project-1',
      assetsRoutePath,
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

    // 未知路径也被拦截回门禁页。
    router.go('/no-such-page');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, vaultRoutePath);
  });

  testWidgets('解锁后可达工作台、分区子路由与项目详情；锁定后自动退回门禁页', (tester) async {
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

    // 分区子路由：待办、日历、时间、项目与设置均为独立受门禁路由。
    router.go(todosRoutePath);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, todosRoutePath);
    expect(find.text('待办区'), findsOneWidget);

    router.go(calendarRoutePath);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, calendarRoutePath);
    expect(find.text('日历区'), findsOneWidget);

    router.go(timeRoutePath);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, timeRoutePath);
    expect(find.text('时间区'), findsOneWidget);

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

    // 工作台内可访问甘特分区（真实页面）。
    router.go(ganttRoutePath);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, ganttRoutePath);
    expect(find.text('甘特区'), findsOneWidget);

    router.go(assetsRoutePath);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, assetsRoutePath);
    expect(find.text('资产库区'), findsOneWidget);

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

  /// 内容区当前生效的滑入位移。新路由的 Overlay 入口要在推入后的第二帧才
  /// 构建，所以调用方需先 pump 一帧再推进时间（见各测试内的注释）。
  double slideDxOf(WidgetTester tester, String text) => tester
      .widget<SlideTransition>(
        find.ancestor(
          of: find.text(text),
          matching: find.byType(SlideTransition),
        ),
      )
      .position
      .value
      .dx;

  testWidgets('分区切换带方向性滑入转场，而非瞬时替换', (tester) async {
    final (router, session) = buildRouter(unlocked: true);
    addTearDown(session.dispose);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    router.go(workbenchRoutePath);
    await tester.pumpAndSettle();
    expect(find.text('工作台'), findsOneWidget);

    // 前进（今日 → 待办）：新内容从右侧进入，过渡中位移为正。
    router.go(todosRoutePath);
    await tester.pump(); // 第一帧：路由入栈，Overlay 入口尚未构建。
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('待办区'), findsOneWidget);
    final forwardDx = slideDxOf(tester, '待办区');
    expect(forwardDx, greaterThan(0));
    expect(forwardDx, lessThan(0.06));

    // 过渡结束后位移归零，内容落定。
    await tester.pumpAndSettle();
    expect(slideDxOf(tester, '待办区'), 0);

    // 后退（待办 → 今日）：新内容从左侧进入，位移为负——方向可感知。
    router.go(workbenchRoutePath);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('工作台'), findsOneWidget);
    final backwardDx = slideDxOf(tester, '工作台');
    expect(backwardDx, lessThan(0));
    expect(backwardDx, greaterThan(-0.06));

    await tester.pumpAndSettle();
    expect(slideDxOf(tester, '工作台'), 0);
  });

  testWidgets('分区切换在同层目标间只淡入，不横移', (tester) async {
    final (router, session) = buildRouter(unlocked: true);
    addTearDown(session.dispose);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // 详情 A → 详情 B 是同层（序号同为 5.5）：横向位移始终为 0，
    // 存在感由淡入补足——过渡进行中淡入值介于 0 与 1 之间。
    router.go('$projectsRoutePath/project-1');
    await tester.pumpAndSettle();
    router.go('$projectsRoutePath/project-2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('项目详情:project-2'), findsOneWidget);
    expect(slideDxOf(tester, '项目详情:project-2'), 0);

    final fade = tester.widget<FadeTransition>(
      find.ancestor(
        of: find.text('项目详情:project-2'),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, greaterThan(0));
    expect(fade.opacity.value, lessThan(1));

    await tester.pumpAndSettle();
    expect(fade.opacity.value, 1);
  });

  testWidgets('系统减弱动态效果时分区切换立即完成', (tester) async {
    final (router, session) = buildRouter(unlocked: true);
    addTearDown(session.dispose);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.go(workbenchRoutePath);
    await tester.pumpAndSettle();
    expect(find.text('工作台'), findsOneWidget);

    // 两帧内即完成切换，且内容区没有任何过渡包装：转场被整体短路，
    // 与 cardoryAnimDuration 的判据一致。
    router.go(todosRoutePath);
    await tester.pump();
    await tester.pump();
    expect(find.text('待办区'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('待办区'),
        matching: find.byType(SlideTransition),
      ),
      findsNothing,
    );
  });
}
