import '../domain/cardory_models.dart';

/// 面向应用的端口，用于将工作区摘要发布到平台小组件。
abstract interface class WidgetDataService {
  Future<void> updateWidgetData(CardoryData data);
}

/// 未集成原生小组件的平台使用空操作适配器。
class NullWidgetDataService implements WidgetDataService {
  const NullWidgetDataService();

  @override
  Future<void> updateWidgetData(CardoryData data) async {}
}
