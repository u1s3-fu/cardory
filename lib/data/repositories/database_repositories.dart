// 数据库 Repository 聚合入口。
//
// 破坏性改造后 Repository 按实体拆分到独立文件，本文件仅负责 re-export，
// 以兼容既有 `import '.../database_repositories.dart'` 的调用方。
export 'repository_support.dart'
    show Clock, nowUtcMillis, repositoryUuid, recordSyncChange, rowPayload;
export 'project_repository.dart';
export 'task_repository.dart';
export 'asset_repository.dart';
export 'attachment_repositories.dart';
export 'time_repositories.dart';
export 'dependency_repository.dart';
export 'settings_repository.dart';
export 'sync_change_repository.dart';
