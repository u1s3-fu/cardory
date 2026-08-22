// 通用分组折叠列表。

import 'package:flutter/material.dart';

import '../cardory_theme.dart';

/// 按分组键渲染的折叠列表。
///
/// 将「分组聚合 + 折叠状态管理 + ExpansionTile 渲染」的复杂度收敛在组件
/// 内部；调用方只需提供分组键映射、分组顺序与行构建器。
///
/// 一个条目可同时属于多个分组（[groupKeysOf] 返回多个键），且会出现在
/// 未分组区之外的所有命中分组中；没有任何分组键的条目归入「未分组」尾部。
class GroupedExpansionList<T> extends StatefulWidget {
  const GroupedExpansionList({
    super.key,
    required this.items,
    required this.groupKeysOf,
    required this.groupOrder,
    required this.groupTitleOf,
    required this.rowBuilder,
    this.uncategorizedTitle = '未分组',
    this.countLabel = '项',
    this.groupIcon = Icons.label_outline_rounded,
    this.uncategorizedIcon = Icons.folder_off_outlined,
    this.rowSeparator = const SizedBox.shrink(),
  });

  /// 待分组的完整条目列表（通常已按过滤器过滤）。
  final List<T> items;

  /// 条目 -> 分组键集合（元素为 null 时忽略，空集合表示未分组）。
  final Iterable<String?> Function(T item) groupKeysOf;

  /// 分组渲染顺序（不含未分组区，未分组区始终在末尾）。
  final List<String> groupOrder;

  /// 分组键 -> 组标题。
  final String Function(String key) groupTitleOf;

  /// 渲染单个条目。
  final Widget Function(BuildContext context, T item) rowBuilder;

  /// 未分组区标题。
  final String uncategorizedTitle;

  /// 组副标题的计数单位，如「3 个文件」「5 项」。
  final String countLabel;

  /// 非空组的 leading 图标。
  final IconData groupIcon;

  /// 未分组区的 leading 图标。
  final IconData uncategorizedIcon;

  /// 组内条目之间的分隔元素。
  final Widget rowSeparator;

  @override
  State<GroupedExpansionList<T>> createState() =>
      _GroupedExpansionListState<T>();
}

class _GroupedExpansionListState<T> extends State<GroupedExpansionList<T>> {
  final Set<String> _collapsed = {};
  List<T>? _cachedItems;
  List<String>? _cachedGroupOrder;
  Map<String, List<T>> _grouped = const {};
  List<T> _uncategorized = const [];

  /// 仅当 [GroupedExpansionList.items] 或 [GroupedExpansionList.groupOrder]
  /// 引用变化时重新聚合；折叠/展开等内部 setState 直接复用结果，避免重复计算。
  void _rebuildGroupsIfNeeded() {
    if (identical(_cachedItems, widget.items) &&
        identical(_cachedGroupOrder, widget.groupOrder)) {
      return;
    }
    _cachedItems = widget.items;
    _cachedGroupOrder = widget.groupOrder;
    final grouped = <String, List<T>>{
      for (final key in widget.groupOrder) key: <T>[],
    };
    final uncategorized = <T>[];
    for (final item in widget.items) {
      final keys = widget.groupKeysOf(item).toSet();
      var matched = false;
      for (final key in widget.groupOrder) {
        if (keys.contains(key)) {
          grouped[key]!.add(item);
          matched = true;
        }
      }
      if (!matched) uncategorized.add(item);
    }
    _grouped = grouped;
    _uncategorized = uncategorized;
  }

  @override
  Widget build(BuildContext context) {
    _rebuildGroupsIfNeeded();
    return Column(
      children: [
        for (final key in widget.groupOrder)
          if (_grouped[key]!.isNotEmpty)
            _buildGroupTile(
              key: key,
              title: widget.groupTitleOf(key),
              items: _grouped[key]!,
            ),
        if (_uncategorized.isNotEmpty)
          _buildGroupTile(
            key: null,
            title: widget.uncategorizedTitle,
            items: _uncategorized,
          ),
      ],
    );
  }

  Widget _buildGroupTile({
    required String? key,
    required String title,
    required List<T> items,
  }) {
    // 未分组区使用空字符串作为折叠状态的哨兵键（真实分组键恒非空）。
    final storeKey = key ?? '';
    final expanded = !_collapsed.contains(storeKey);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: expanded,
        onExpansionChanged: (value) => setState(() {
          if (value) {
            _collapsed.remove(storeKey);
          } else {
            _collapsed.add(storeKey);
          }
        }),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          key == null ? widget.uncategorizedIcon : widget.groupIcon,
          color: CardoryColors.primary,
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text('${items.length} ${widget.countLabel}'),
        children: [
          for (var index = 0; index < items.length; index++) ...[
            widget.rowBuilder(context, items[index]),
            if (index < items.length - 1) widget.rowSeparator,
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
