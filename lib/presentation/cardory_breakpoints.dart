/// 响应式断点与栅格列数推导。
///
/// 此前全库散落 520/560/600/640/680/720/760/960/1000/1080/1100/1200 共 12 个
/// 互不一致的宽度阈值，其中最典型的一处冲突是：Shell 用 720 判断紧凑，
/// 而首页头图用 760 —— 窗口 730px 时同一屏会给出两套相反的布局判断，
/// 分区已切成紧凑内边距，头图却仍按宽松排版。
///
/// 收敛为两级整页档位 + 一级组件档位：
/// * [compact] / [medium]：整页档位，决定侧栏、页面内边距与分区布局；
/// * [tight]：组件局部「排不下就纵向堆叠」。阈值必须小于 [compact]，
///   因为面板可用宽度通常只有页面宽度的几分之一，套用整页档位会让
///   工具栏在还很宽敞时就提前换行。
///
/// 网格列数不要用断点枚举，改用 [cardoryColumns] 按最小列宽连续推导。
abstract final class CardoryBreakpoints {
  /// 紧凑档：收起侧栏、缩小页面内边距（原 720）。
  static const double compact = 720;

  /// 中等档：保留侧栏，内容可铺开多列（原 1100）。
  static const double medium = 1100;

  /// 组件级紧凑：标题栏 / 工具栏在容器内排不下时改为纵向堆叠（原 560–640）。
  static const double tight = 600;

  /// 宽度是否处于紧凑档。
  static bool isCompact(double width) => width < compact;

  /// 宽度是否达到中等档。
  static bool isMedium(double width) => width >= medium;
}

/// 由可用宽度推导网格列数。
///
/// 不同网格的「最小可接受列宽」并不相同（统计卡约 250、看板列约 240、
/// 项目卡约 340），套用同一组断点既会得出互相矛盾的结果，也会在断点
/// 交界处产生列数跳变（例如 519px 一列、520px 两列）。
///
/// [minColumnWidth] 为单列可接受的最小宽度，[max] 为列数上限。
int cardoryColumns(
  double width, {
  required double minColumnWidth,
  required int max,
}) => (width / minColumnWidth).floor().clamp(1, max);
