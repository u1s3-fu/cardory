import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../domain/widget_data_service.dart';
import '../domain/cardory_models.dart';

/// 基于 [HomeWidget] 包的桌面小组件数据服务。
///
/// 将 [CardoryData] 的待办摘要通过 [HomeWidget.saveWidgetData]
/// 写入平台共享存储，供 Android / iOS 小组件读取。
class HomeWidgetDataService implements WidgetDataService {
  // ------------------------------------------------------------------
  // 与 Android / iOS 原生小组件侧保持一致的常量
  // ------------------------------------------------------------------
  static const String _dataKey = 'cardory_todos';
  static const String _androidWidgetName = 'CardoryWidgetProvider';
  static const String _iosWidgetName = 'CardoryWidget';
  static const String _iosAppGroupId = 'group.com.cardoryapp.widget';

  /// 小组件最多展示的待办条数（与原生侧 MAX_ITEMS 一致）。
  static const int maxItems = 5;

  const HomeWidgetDataService();

  @override
  Future<void> updateWidgetData(CardoryData data) async {
    final payload = _buildPayload(data);
    try {
      await HomeWidget.setAppGroupId(_iosAppGroupId);
      await HomeWidget.saveWidgetData<String>(_dataKey, payload);
      await HomeWidget.updateWidget(
        androidName: _androidWidgetName,
        iOSName: _iosWidgetName,
      );
    } catch (_) {
      // 小组件更新失败不影响主流程
    }
  }

  // ----  helper  -------------------------------------------------------

  /// 优先级名称到中文标签的映射（与 iOS WidgetTodo.priorityLabel 结构一致）。
  static const Map<String, String> _priorityLabels = {
    'p0': '高',
    'p1': '中',
    'p2': '普通',
    'p3': '低',
  };

  /// 将 [CardoryData] 序列化为 JSON 字符串，仅包含小组件需要的前 [maxItems] 条未完成待办。
  ///
  /// 载荷结构与 Android (`CardoryWidgetProvider.kt`) 和 iOS (`CardoryWidget.swift`)
  /// 原生小组件侧的字段名保持一致。
  String _buildPayload(CardoryData data) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final items = data.todos.where((t) => !t.done).take(maxItems).toList();

    final pendingCount = data.todos.where((t) => !t.done).length;
    final totalCount = data.todos.length;

    final todos = items.map((t) {
      final endDateStr = t.endDate != null
          ? '${t.endDate!.year}-${_pad(t.endDate!.month)}-${_pad(t.endDate!.day)}'
          : null;
      final priorityKey = t.priority.name;
      final dueDate = t.endDate == null
          ? null
          : DateTime(t.endDate!.year, t.endDate!.month, t.endDate!.day);
      final isOverdue = dueDate != null && dueDate.isBefore(today);
      final isDueSoon =
          dueDate != null && !isOverdue && dueDate.difference(today).inDays <= 1;
      return {
        'id': t.id,
        'title': t.title,
        'priority': priorityKey,
        'priorityLabel': _priorityLabels[priorityKey] ?? '普通',
        'projectTitle': t.projectTitle,
        'endDate': endDateStr,
        'subTodoCount': t.subTodos.length,
        'subTodoDoneCount': t.subTodos.where((s) => s.done).length,
        'isOverdue': isOverdue,
        'isDueSoon': isDueSoon,
      };
    }).toList();

    return jsonEncode({
      'todos': todos,
      'pendingCount': pendingCount,
      'totalCount': totalCount,
    });
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
