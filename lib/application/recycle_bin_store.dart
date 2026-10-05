// 回收站的应用层契约：软删除条目的查询与恢复。
//
// 与 [RowLevelWorkspaceStore] 同一模式：生产实现由 drift 仓库提供
// （恢复写入与 sync_changes 同事务提交），测试可提供内存实现。

import '../domain/recycle_bin_models.dart';

/// 每次调用返回当前会话的回收站存储；保险库未解锁时返回 null。
typedef RecycleBinStoreBuilder = RecycleBinStore? Function();

abstract interface class RecycleBinStore {
  Future<List<RecycleBinEntry>> loadEntries();

  /// 恢复一条软删除记录；宿主缺失等不可恢复场景抛 [StateError]。
  Future<void> restore(RecycleBinEntityType type, String id);
}
