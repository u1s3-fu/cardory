// 首页面板顺序：HomePanel 规范化、设置持久化往返与拖拽排序宿主。

import 'package:cardory/domain/app_settings.dart';
import 'package:cardory/presentation/widgets/home_panel_order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePanel extends StatelessWidget {
  const _FakePanel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 200,
    child: Container(
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: Text(title),
    ),
  );
}

Widget _host({
  required List<HomePanel> order,
  required Future<void> Function(List<HomePanel>) onReorder,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 600,
      height: 1400,
      child: HomePanelOrderHost(
        order: order,
        panels: const {
          HomePanel.todayTasks: _FakePanel(title: '面板一'),
          HomePanel.kanban: _FakePanel(title: '面板二'),
          HomePanel.reminders: _FakePanel(title: '面板三'),
        },
        onReorder: onReorder,
      ),
    ),
  ),
);

/// 长按起点并拖到目标点后松开，返回拖拽是否已触发。
Future<void> _dragFromTo(WidgetTester tester, Offset from, Offset to) async {
  final gesture = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 700));
  await gesture.moveBy(to - from);
  await tester.pumpAndSettle();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('HomePanel.normalize', () {
    test('默认顺序为今日任务 / 项目看板 / 主要提醒', () {
      expect(HomePanel.defaultOrder, [
        HomePanel.todayTasks,
        HomePanel.kanban,
        HomePanel.reminders,
      ]);
    });

    test('空列表补齐为完整默认顺序', () {
      expect(HomePanel.normalize(const []), HomePanel.defaultOrder);
    });

    test('过滤未知 id、去重并补齐缺失项', () {
      expect(HomePanel.normalize(['kanban', 'bogus', 'kanban']), [
        HomePanel.kanban,
        HomePanel.todayTasks,
        HomePanel.reminders,
      ]);
    });

    test('保留用户顺序', () {
      expect(HomePanel.normalize(['reminders', 'todayTasks']), [
        HomePanel.reminders,
        HomePanel.todayTasks,
        HomePanel.kanban,
      ]);
    });
  });

  group('AppSettings.homePanelOrder 持久化', () {
    test('toJson / fromJson 往返保留顺序', () {
      const settings = AppSettings(
        homePanelOrder: [
          HomePanel.reminders,
          HomePanel.todayTasks,
          HomePanel.kanban,
        ],
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.homePanelOrder, settings.homePanelOrder);
    });

    test('旧配置缺少键时回退默认顺序', () {
      final restored = AppSettings.fromJson(const {});
      expect(restored.homePanelOrder, HomePanel.defaultOrder);
    });

    test('云端配置子集往返保留顺序', () {
      const remote = AppSettings(
        homePanelOrder: [
          HomePanel.kanban,
          HomePanel.reminders,
          HomePanel.todayTasks,
        ],
      );
      final applied = const AppSettings().applySyncConfig(
        remote.toSyncConfigJson(),
      );
      expect(applied.homePanelOrder, remote.homePanelOrder);
    });

    test('copyWith 覆盖顺序', () {
      const settings = AppSettings();
      final next = settings.copyWith(
        homePanelOrder: const [HomePanel.reminders],
      );
      expect(next.homePanelOrder, const [HomePanel.reminders]);
      // 未传时保持原值。
      expect(settings.copyWith().homePanelOrder, HomePanel.defaultOrder);
    });
  });

  group('HomePanelOrderHost', () {
    testWidgets('长按拖到另一张卡片上：插入其前方', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1500);
      addTearDown(tester.view.reset);
      List<HomePanel>? applied;
      await tester.pumpWidget(
        _host(
          order: const [
            HomePanel.todayTasks,
            HomePanel.kanban,
            HomePanel.reminders,
          ],
          onReorder: (order) async => applied = order,
        ),
      );

      final first = tester.getCenter(find.text('面板一'));
      final third = tester.getCenter(find.text('面板三'));
      await _dragFromTo(tester, first, third);

      // 面板一被拖到面板三上：移除后插到面板三前方。
      expect(applied, [
        HomePanel.kanban,
        HomePanel.todayTasks,
        HomePanel.reminders,
      ]);
    });

    testWidgets('拖到末尾空白区：移动到最后', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1500);
      addTearDown(tester.view.reset);
      List<HomePanel>? applied;
      await tester.pumpWidget(
        _host(
          order: const [
            HomePanel.todayTasks,
            HomePanel.kanban,
            HomePanel.reminders,
          ],
          onReorder: (order) async => applied = order,
        ),
      );

      final first = tester.getCenter(find.text('面板一'));
      // 三张面板各 200 + 间距 22：末尾放置区约在 [644, 692]。
      await _dragFromTo(tester, first, Offset(first.dx, 670));

      expect(applied, [
        HomePanel.kanban,
        HomePanel.reminders,
        HomePanel.todayTasks,
      ]);
    });

    testWidgets('拖到自已身上不触发重排', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1500);
      addTearDown(tester.view.reset);
      List<HomePanel>? applied;
      await tester.pumpWidget(
        _host(
          order: const [
            HomePanel.todayTasks,
            HomePanel.kanban,
            HomePanel.reminders,
          ],
          onReorder: (order) async => applied = order,
        ),
      );

      final first = tester.getCenter(find.text('面板一'));
      await _dragFromTo(tester, first, Offset(first.dx, first.dy + 4));

      expect(applied, isNull);
    });
  });
}
