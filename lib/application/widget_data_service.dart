import '../domain/cardory_models.dart';

/// Application port for publishing a workspace summary to a platform widget.
abstract interface class WidgetDataService {
  Future<void> updateWidgetData(CardoryData data);
}

/// No-op adapter for platforms without a native widget integration.
class NullWidgetDataService implements WidgetDataService {
  const NullWidgetDataService();

  @override
  Future<void> updateWidgetData(CardoryData data) async {}
}
