import 'cardory_models.dart';

/// 面向应用的端口，用于将工作区摘要发布到平台小组件。
abstract interface class WidgetDataService {
  Future<void> updateWidgetData(CardoryData data);

  /// 清除已发布的小组件摘要。
  ///
  /// 在保险库锁定 / 退出时调用：待办等敏感内容不能停留在桌面小组件上，
  /// 清除后原生侧应回退到「打开应用以同步」占位。
  Future<void> clearWidgetData();
}

/// 未集成原生小组件的平台使用空操作适配器。
class NullWidgetDataService implements WidgetDataService {
  const NullWidgetDataService();

  @override
  Future<void> updateWidgetData(CardoryData data) async {}

  @override
  Future<void> clearWidgetData() async {}
}
