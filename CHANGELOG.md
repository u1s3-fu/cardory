# Changelog

Cardory 版本更新日志。遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 格式。

## [Unreleased]

### 变更（Changed）

- 同步冲突流程重构：`SyncStatus` 新增 `SyncConflictKind`（`firstSync` 首次同步发现本地数据 / `concurrent` 自上次同步后双向修改），冲突状态携带场景信息并纳入序列化与状态比较，界面据此呈现差异化提示（`lib/domain/sync_status.dart`）。
- 同步协调器把「首次同步发现本地数据」与「双向修改」两条冲突路径收敛为统一挂起方法 `_suspendForConflict`：同一套「远端快照留底 → 只读解析对比 → 记录冲突上下文 → 进入冲突状态」流程，冲突消息携带本地数据项数 / 差异条目数；内容冲突不再以异常作为控制流上抛，`synchronize` 全部以状态与返回值表达结果。
- 冲突解决（`resolveConflict`）加固：选择「使用远端」前先把当前本地库自动备份到冲突快照目录，成功提示附备份路径，首次同步误选覆盖也能找回本地数据；覆盖执行前云端修订号再变时保留冲突列表与场景信息提示用户重新选择（不再退回无内容的冲突框）；取消冲突处理时状态干净复位、清除冲突上下文。
- 同步冲突对话框升级（`sync_conflict_dialogs.dart`）：按 `SyncConflictKind` 区分「首次同步：本地与云端数据并存」与「检测到同步冲突」头部与说明；差异清单分别统计本地侧 / 仅远端条目数；逐项列出「各选项的影响」（保留本地、使用远端、手动合并、取消）；首次同步下「使用远端」按钮以错误色警示，选择后弹二次确认框，明确本地从未上云的数据将被替换且操作前自动备份。
- 设置面板同步状态配色区分语义：`conflict` 阶段改用警示色（橙色），`failure` 仍为错误色（红色）。
- 云端数据快照无法解密（文件损坏，或由使用不同保险库密码的设备上传）不再只是一句无从措手的失败：`inspectContainer`/`importContainer` 改抛专用 `CardorySnapshotUndecryptableException`，同步协调器在各下载/首次同步/冲突路径识别后把本地库原样保留、云端原文件自动留底，并挂起为新场景 `SyncConflictKind.unreadableRemote`；界面弹出专用手动选择框，提供「用本地数据覆盖云端」（覆盖前强制把云端原文件备份到冲突快照目录，备份失败即拒绝覆盖以免销毁可能仍被另一台设备使用的数据；二次确认并提示密码不同的设备此后将无法读取新快照）与「跳过本次」（云端/本地均保持原样）；协调器层同时拒绝该场景下的「使用远端 / 手动合并」调用，不依赖界面是否隐藏按钮。

### 修复（Fixed）

- 同步时上传/删除若被云端抢先（provider 层 HTTP 409/412），此前会被误判为「本地与远端内容冲突」并弹出选项全部失效的冲突框；现如实提示失败原因（如「WebDAV 文件已被其他设备修改」），用户再次点击同步会自动重新比对并进入正确的下载或冲突流程。
- 冲突解决选「使用远端」时与下载分支保持一致的回滚保护：云端快照导入或附件准备中途失败（如附件下载中断）会整体回滚到冲突发生前的本地库，不再留下「本地已被远端库整体替换但附件/设置未完成」的半完成状态；覆盖前本地库快照仍保留可人工找回。
- 云端附件清单发布改为尽力而为：清单写入失败仅记录同步日志，不再把已成功完成的下载/推送同步翻转成失败，也不丢弃 `requiresReload`（此前磁盘数据已更新而界面因状态翻转停留在旧数据、需再次同步才重载）。
- 读取云端附件清单失败时补充同步日志（此前静默按「云端无清单」处理，瞬断或异常难以排查）。

### 变更（Changed）

- 冲突/覆盖前快照目录（`Cardory/conflicts`）新增保留上限（最近 8 份），每次写入后自动清理最旧快照，避免逐次累积整库密文副本长期占用磁盘；清理为尽力而为，失败不影响快照保存。

### 测试（Tests）

- `sync_models_test`：`SyncStatus.conflictKind` 序列化往返与旧数据缺失字段回退 null 用例。
- `sync_coordinator_test`：首次同步冲突断言 `conflictKind == firstSync`，双向修改冲突断言 `conflictKind == concurrent`。
- `sync_coordinator_test`：新增「keepRemote 附件同步失败回滚到冲突前本地库（数据/锚点不受污染、冲突上下文保留）」与「manifest 发布失败不翻转已成功下载（保持 success 与 requiresReload）」两条用例。
- `sync_coordinator_test`：新增「云端快照无法解密」四类用例——下载路径挂起为 `unreadableRemote` 且本地/锚点不变、协调器拒绝该场景的「手动合并/使用远端」、显式选择覆盖后用本地数据重写云端并提示已备份、首次同步（本地有数据）遇到无法解密快照时挂起且「跳过」不改变任何一侧。

## [0.1.0-beta.1] - 2026-09-08

> ⚠️ **破坏性数据不兼容（本版本对应 0.1.0-beta.1）**
>
> 本版本把数据运行时从 AES-256-GCM `.cardory` 加密容器 + JSON 切换为 **SQLCipher 整库加密的 SQLite 数据库**（`Cardory/cardory-runtime-v1.db`），属于**不可自动升级**的数据不兼容版本：
>
> - 旧版本（≤ 0.0.7）的 `cardory-current-data.cardory` 数据文件与 `cardory-current-settings.json` **不会被读取、覆盖或自动迁移**；如需保留旧数据，请先在旧版本中自行备份；
> - 云同步对象更换为加密数据库快照 `cardory-snapshot-v2.db` 与配置 `cardory-config-v2.json`，云端旧 `.cardory` 对象不再读取；
> - 升级前请导出/备份旧版本数据与附件，以免卸载旧版本后无法找回。

### 变更（Changed）

- 数据保险库整包快照写入改为行级增量对齐（`DatabaseSnapshotApplier`）：UI 每次保存不再“物理全删 + 全量重插”，只写入与快照期望不一致的行并对消失的可见行做 tombstone，新增/变更/删除均在同一事务内追加完整 payload 的 `sync_changes` 审计；`createdAt` 得以保留、未变化的行不再刷新 `updatedAt`，快照之外的表（计时/番茄钟/依赖/同步日志）不再被触碰；对“同 id 先 tombstone 后又回到快照”（如远端带回此前本地删除的实体）的写入会自动清除 `deletedAt` 复活并按 update 记账，不再因主键冲突失败。
- `WorkspaceController` 去双事实源：内存 `_data`/`_settings` 降级为“数据库投影缓存”，不再承担独立事实源——每次 UI 写入口提交 `repository.save()`（单事务行级对齐）成功后都会从数据库回读（`repository.load()`）刷新投影再通知 UI；保存失败仍原子回滚到上一个已提交投影，回读失败则保留与已提交内容一致的快照、不误回滚。
- 附件同步引入云端附件清单（`attachments/manifest.json`，`AttachmentManifest`）：每次成功同步（推送/拉取/无变化收敛/冲突解决）后按当前快照附件集合幂等重写，云端始终保有「该快照引用附件」的权威枚举，供新设备/云端恢复逐文件抓取与完整性校验；清单读取为尽力而为（缺失/老版本云端返回 null 跳过校验），读取到清单时把它作为附件缺失判定的 fail-closed 校验——远端快照引用清单之外的附件会中止同步（导入侧沿用原有原子回滚），不再把远端不一致的附件引用静默导入为本地残缺数据；附件云端 key 生成收敛到 `attachmentFileKey`。
- 云端恢复（WebDAV / S3 向导）在数据库快照恢复完成后，按快照引用附件集合把云端附件密文拉取到本地附件目录：`installEncrypted` 逐一做完整性校验（摘要/长度不符即失败）；云端附件清单读取为尽力而为，读到清单时以其为权威做缺失判定，缺失附件 fail-closed 报「云端缺少附件…恢复不完整」，提示重试或进入应用后触发一次同步补齐（数据库已切换，重试幂等）。`CloudRestoreService` 支持注入附件仓库工厂与同步提供者工厂（测试可控），vault 门禁「从云端恢复」入口已接线；新增 `test/cloud_restore_service_test.dart` 覆盖本地已存在跳过、远端下载安装、双端缺失 fail-closed、清单外引用提示四类路径。
- 旧 LegacyJson 迁移适配器仅存的 DB→领域聚合读映射收编为 `SqlCipherDataMapper`（`lib/data/runtime/sqlcipher_data_mapper.dart`），LegacyJson 迁移写入口/服务随模块整体删除；保险库 `unlockWithPassword` / `restoreFromBackup` 把 SQLCipher 打开失败统一包装为 `CardoryStorageException`（「密码不正确或数据文件已损坏」文案），门禁据此清除已保存的自动解锁凭据并回落到手动输入界面，不再依赖旧容器异常类型。
- 云上同步文档 key 更名以彻底隔离旧协议：数据快照改用 `cardory-snapshot-v2.db`、配置改用 `cardory-config-v2.json`（同步协调器、S3 provider、WebDAV/目录同步与云端恢复入口同步更新）；破坏性版本下云端旧 `.cardory` 文档不再读取，避免把旧容器字节误当新快照尝试解密。
- vault 门禁「新建保险库」界面检测到旧版本 `.cardory` 数据文件（`cardory-current-data.cardory` / `cardory-current-settings.json`）时显示一次性提示条：说明本版本使用新的加密数据库格式，不会读取、覆盖或自动迁移旧文件，确认无用可自行删除。
- 工作台迁入受保护业务路由：解锁成功后由 `/vault` 切换到受保护路由 `/today` 渲染工作台；`/calendar`、`/time`、`/gantt`、`/assets` 注册为受保护占位页（含返回工作台入口）；`go_router` redirect 依据保险库解锁状态生效并配合 `refreshListenable`，锁定/未解锁时一切业务路径回落 `/vault`；保险库页在锁定后通过递增 `vault-epoch` key 强制重建。新增 `test/routing/app_router_test.dart` 门禁用例。
- 保险库会话/锁定/自动锁定/退出清理逻辑从 vault 门禁页上移到应用层（`CardoryApp`）：锁定按 fail-closed 顺序执行（停止会话 → 删除已保存密码凭据 → 清除小组件摘要 → 弹出导航栈并回 `/vault`）；`WidgetDataService` 新增 `clearWidgetData`，原生侧以 `HomeWidget.saveWidgetData(key, null)` 清空小组件缓存。新增 `test/routing/vault_session_lock_test.dart` 覆盖「自动解锁→暂停锁定→凭据与摘要被清除」与「重新解锁回到工作台」两条路径。
- `VaultGate` 收敛为纯门禁页：移除其内置的自动锁定控制器、锁定逻辑与工作台内联渲染，解锁成功改为经 `onUnlocked` 回调交由应用层接管会话与跳转。
- 破坏性版本号与发布材料更新：版本 bump 至 `0.1.0-beta.1+1`（tag 为 `v0.1.0-beta.1`，GitHub Release 自动标记 prerelease）；README 全面翻新为 SQLCipher 数据库架构（数据文件、加密方案、密钥生命周期、同步对象、依赖表与路由门禁），并置顶数据不兼容警告；GitHub Actions Release 流程新增 `quality-gate`（format + `flutter analyze --fatal-infos` + `flutter test`），构建依赖该门禁，版本号含 `-` 时自动标记 prerelease，Windows 安装程序版本参数改为仅取数字前缀；`docs/CARDORY_PHASE1_MIGRATION.md` 原渐进草案冲突章节改写为历史/实施说明口径，以实际破坏性实施为准。
- 全仓库按当前 dart_style（Dart 3.12 / dart_style 3.1.9）做一次性格式化归一（65 个文件机械改写，无行为变化），使新增 CI 格式门禁与 README 发布检查可自洽通过。

### 移除（Removed）

- 移除附件旧迁移运行时路径：`AttachmentRepository.migrateLegacy` 接口与 `AttachmentStore.migrateLegacy` 实现、`WorkspaceController.applyLoadResult` 中的 `legacyFileBytes` 迁移分支及其测试——破坏性版本下附件一律以加密文件落盘并登记 `storageKey`，数据库不再产生 base64 内嵌附件，无需“打开即迁移”。
- 移除旧容器运行时：`lib/data/cardory_store.dart`、`lib/data/cardory_container_codec.dart`、`lib/domain/cardory_container.dart`（CardoryStore 运行时、容器编解码器、容器模型与异常类型）及其测试 `test/cardory_store_test.dart`、`test/cardory_container_codec_test.dart`；`vault_gate` 等界面不再引用旧容器凭据错误类型。
- 整体删除 LegacyJson 迁移模块 `lib/data/migration/`（legacy 导入 / 导出 / 迁移服务 / 迁移数据库接口 / 迁移模型 / `AppDatabaseLegacyMigrationAdapter`），并删除 `test/migration/legacy_migration_export_test.dart` 与 `test/app_database_legacy_migration_test.dart`。
- 移除「恢复数据」旧 `.cardory` 本地文件导入入口：`SettingsPanel.onRestoreBackup` 与按钮、`HomePage._restoreBackupFromSettings`、`BackupPasswordDialog`、`WorkspaceController.restoreBackup`。云端恢复统一走保险库门禁的 WebDAV / S3 向导，不再提供本地容器文件导入。

### 修复（Fixed）

- 修复项目进度记录新增方法中 `recordedAt` 被当作可空写入导致类型不匹配、以及进度流查询误用未导入的 `drift.` 前缀导致的编译错误。

## [0.0.7] - 2026-09-07

### 修复（Fixed）

- 修复移动端项目详情页「项目资产」「项目附件」面板头部在窄屏横向溢出的问题：新增响应式面板头部，窄屏下主操作按钮与标题同行、次要操作（图标按钮、视图切换）换到下一行。
- 修复项目详情页数据不随工作区刷新的问题：停留在详情页时新增/删除的资产与待办现在立即反映到列表，无需退出重进。

## [0.0.6] - 2026-09-06

### 修复（Fixed）

- 修复 Android release 包启动即闪退的问题：R8 混淆移除了 WorkManager（经 home_widget 传递引入）反射实例化所需的 Room 数据库实现类，新增 ProGuard keep 规则保留 `RoomDatabase` 实现类构造函数。
- 修复 Android 桌面小组件一直显示「打开应用以同步待办」的问题：原生小组件读取的 SharedPreferences 名称（`FlutterHomeWidget`）与 home_widget 插件实际写入的名称（`HomeWidgetPreferences`）不一致，已统一。

### 变更（Changed）

- 升级 file_picker 至 12.2.0、home_widget 至 0.9.4、package_info_plus 至 10.2.1，减少与 AGP 9 Built-in Kotlin 不兼容的插件数量（home_widget 因 Flutter 3.44 工具链限制仍需过渡开关，已在 gradle.properties 注释说明）。
- 适配 file_picker 12 新 API：备份恢复改用 `FilePicker.pickFile` + `PlatformFile.readAsBytes`，附件导出改为先解密到内存再交由系统保存对话框写入，附件仓库新增 `readAttachmentBytes` 方法。

## [0.0.5] - 2026-08-22

### 新增（Added）

- 新增 Windows Inno Setup 安装程序，支持用户级安装、开始菜单/桌面快捷方式、覆盖升级和卸载。
- 新增「关于」对话框，展示应用名称、版本、功能简介、GPL-3.0 许可证和 GitHub 仓库链接。
- 新增 GitHub Releases 检查更新，支持启动静默检查、手动检查、版本比较、更新说明和平台安装包下载。
- 新增资产标签、附件分类、批量分配、批量导出、批量删除和批量重命名能力。
- 新增 S3 兼容同步后端、配置云同步、同步冲突手动合并和云端恢复能力。
- 新增全局动效系统、统一页面转场、项目卡片悬停反馈和加载状态主题。
- 新增 GPL-3.0 `LICENSE` 文件，项目采用 GPL-3.0 开源许可与商业授权双许可模式。

### 变更（Changed）

- Windows 原有 ZIP 改名为便携版（`cardory-windows-x64-版本-portable.zip`）并继续发布；更新资产默认优先安装程序。
- 设置入口重组：「检查更新」移入「关于」对话框，「本地数据」并入「数据与同步」分区。
- 界面整体扁平化和视觉减重，减少渐变、阴影和彩色装饰，统一卡片、看板、顶部栏和面板样式。
- 桌面端隐藏滚动条，同时保留滚轮、键盘和触控板滚动。
- 统一动画时长、缓动曲线、页面转场、悬停反馈和减少动态效果行为。
- 「上传附件时重命名」与「重命名时保留文件扩展名」改为可独立配置。
- 资产、附件、待办和看板列表改用懒加载，并优化标签、分类查询和看板分组计算。
- 拆分首页、设置页、项目页、附件面板、任务对话框、领域模型和同步模块，收敛各层依赖方向。
- 同步连接测试改为优先使用当前表单凭据，已保存凭据仅作为回退。
- 完善 WCAG 对比度、触控目标、Tooltip、读屏标签和状态语义。

### 修复（Fixed）

- 修复项目详情页缺少 `Scaffold` 导致附件 `Chip` 操作时报「No Material widget found」的问题。
- 修复详情页 SnackBar 无法正确显示及附件错误提示重复、排队的问题。
- 修复分类、标签重命名对话框异步关闭后仍调用 `setState` 的潜在崩溃。
- 修复保险库解锁或初始化流程页面销毁后仍调用 `setState` 的潜在崩溃。
- 修复同步连接测试未使用当前表单输入密码或密钥的问题。
- 修复同步冲突手动合并后资产标签被清空的问题，合并现按 id 并集保留两侧标签。
- 修复无待处理冲突时执行冲突解决会把用户设置重置为默认值的问题。
- 修复本地版本号读取失败时启动更新检查误报「发现新版本」的问题，现静默跳过并在手动检查时提示。
- 修复列表筛选、折叠和重排时 Flutter 按位置复用状态导致的显示错乱。
- 修复多处文字、图标、状态色和错误提示颜色对比度不足的问题。

### 删除（Removed）

- 删除旧首页巨型文件 `lib/presentation/pages/dashboard.dart`，改由独立页面组件组成。
- 删除旧任务对话框巨型文件 `lib/presentation/pages/task_dialogs.dart`，改由独立对话框组件组成。
- 删除无引用的 `lib/services/widget_data_service.dart` 冗余转发文件。
- 删除 `WorkspaceController.updateProject` 冗余别名，统一使用 `editProject`。
- 删除旧渐变背景、常显滚动条、重复对话框实现和无引用死代码。

## [0.0.4] - 2026-08-21

### 新增（Added）

- 移动端待办桌面小组件：Android AppWidget + iOS WidgetKit，主屏幕显示未完成待办列表
- `WidgetDataService`（`lib/services/`）：导出待办摘要到共享存储供原生小组件读取
- Android `CardoryWidgetProvider`：基于 RemoteViews 的桌面小组件实现
- iOS `CardoryWidget` SwiftUI 小组件（支持 Small/Medium/Large 三种尺寸）
- `home_widget` Flutter 依赖：Flutter ↔ 原生小组件数据桥接
- 项目附件功能：`AttachmentData` 提供图片、文档、压缩包和其他四类明确类型，并记录创建日期
- `ProjectData` 持有附件元数据，项目详情支持上传、备注、删除和导出；资产不持有附件
- 桌面端数据路径展示：侧边栏新增“本地数据”卡片 + 设置对话框新增“本地数据文件存储路径”只读字段（仅桌面平台可见，移动端不展示）
- 新增 S3 兼容同步后端：支持自定义 Endpoint、Region、Bucket 和对象前缀，可连接 AWS S3、MinIO、Cloudflare R2 等服务
- 新增配置云同步：应用设置（主题、行为偏好及 WebDAV/S3 同步配置等非敏感项）会随数据一并双向同步到云端，后续任何配置变更在同步时都会同步到云端，本地与云端配置保持一致；密码、密钥等敏感凭据仍仅保存在本地，不上传云端
- 首次打开应用时新增“从云端恢复”功能：可选用 WebDAV 或 S3 兼容存储作为数据源，引导用户填写连接配置、验证凭据、查看可恢复的备份，确认后输入数据密码执行恢复，恢复成功自动保存数据密码与云存储凭据（WebDAV 密码 / S3 密钥），并把云存储连接配置一并保存到设置中，确保后续使用中云同步功能可直接正常运作
- 云端恢复流程包含完整异常处理：网络不可用、连接超时、凭据无效、云端无可用备份、密码错误或恢复中断等场景均会给出明确错误提示，并提供重试/重新连接选项
- 项目资产支持自定义标签：可手动创建、重命名和删除标签，删除标签时同步清理资产上的标签标记
- 每项软件/硬件资产可关联多个标签，标签互不影响；新增/编辑资产对话框支持直接选择标签，详情对话框展示标签
- 资产面板支持按标签筛选与按标签折叠分组浏览，未打标签资产归入“未打标签”组
- 资产支持批量操作：勾选多项后可为选中资产统一分配或移除标签
- `AssetData` 新增 `tagIds` 字段、`CardoryData` 新增 `assetTags` 字段，旧数据缺失时按空列表兼容加载
- 设置新增“上传附件时重命名”开关，可控制导入附件后是否弹出重命名对话框
- 设置新增“重命名时保留文件扩展名”开关：开启后重命名仅修改文件名主体，原扩展名保持不变（对批量上传重命名与单个重命名均生效）
- 项目附件支持自定义分类：可手动创建、重命名和删除分类，删除分类时同步清理附件上的分类标记
- 附件可分配一个或多个分类，面板支持按分类筛选和按分类折叠分组展示，未分类附件归入“未分类”组
- 附件批量操作：支持勾选多个附件后批量导出（选择目录）、批量分配分类和批量删除
- 上传附件支持批量重命名：一次导入多个文件后可直接在对话框内逐个修改文件名，单个附件也支持随时重命名
- `AttachmentData` 新增 `categoryIds` 字段、`ProjectData` 新增 `categories` 字段，旧数据缺失时按空列表兼容加载
- 同步前增加本地与远端差异对比，展示具体项目、待办和资产冲突项，避免直接覆盖下载远端数据
- 新增“保留本地”“使用远端”和“手动合并”三种冲突处理方式；手动合并支持逐项选择数据来源，并继续执行远端 revision 并发校验
- 同步完成后展示本地保留、远端采用、手动合并和跳过项目的结果摘要

### 变更（Changed）

- 修正 README 文档与实现不符之处：Android 最低版本更正为 Android 7.0（API 24）、Dart SDK 徽章与开发环境版本更新为 3.12.2、预设主题色数量更正为 7 种、项目阶段流转名称由“推进中”更正为“进行中”
- 首次启动从云端恢复时，除数据外还会读取并应用云端配置，并把用户在恢复过程中填写的云存储连接信息（服务器地址、账号、Bucket、Prefix 等）自动填充到配置项，恢复后即可直接继续同步
- 启用云同步（WebDAV、S3 兼容存储等）后，设置中不再显示“本地数据”选项，避免云同步模式下本地路径概念造成误导；本地目录同步与未启用同步时仍正常显示
- 统一样式：为开关、选择按钮（SegmentedButton）和筛选标签（FilterChip）新增全局主题样式，界面控件更统一、现代
- 开关控件统一为白底细描边 + 品牌色选中轨道；选择按钮选中态改为品牌色实底 + 白色文字/图标，禁用态降为灰色；筛选标签选中态使用柔和品牌底色与品牌色对勾，InputChip 删除图标统一为灰色
- 复选框补齐禁用态与悬停反馈（淡品牌色蒙层），与开关/按钮交互反馈一致
- 收敛品牌视觉中的“AI 生成感”：深色头图由三色渐变收敛为品牌双色渐变，侧边栏与统计卡中的粉色元素改为品牌色系，卡片/菜单阴影由彩色投影改为中性投影，整体更接近人工精心设计的软件产品
- 仪表盘阶段卡去除彩色阴影与彩色发光：投影与圆点光晕改为中性黑，卡片渐变浓度下调，观感更克制
- 首页背景渐变由浅紫尾色收敛为中性灰双色渐变，去除彩色背景带来的“AI 生成感”
- 资产标签以纯文本名称直接展示在资产行与详情中（如“标签：生产环境、数据库”），不使用颜色块或颜色标注
- 将同步冲突改为弹出选择：支持使用云端覆盖本地、使用本地覆盖云端或取消，避免双方数据变化时默认报告同步成功
- 增加冲突解决期间的云端 revision 并发校验，并优化同步完成提示，普通同步不再强制刷新界面
- 缩小密码输入框的显示/隐藏密码按钮及图标尺寸，减少控件视觉占用
- 统一代码注释与说明文字为中文：同步层、应用层、领域/数据层与表现层的 Dart 注释，以及 `pubspec.yaml`、`analysis_options.yaml` 中的说明性注释均改为中文书写，专有名词与术语（如 S3、WebDAV、Cardory 等）保留原文
- 备份恢复改为使用备份加密密码：恢复数据时输入创建备份时使用的密码即可解密并重新加盐加密存储，不再需要恢复码与重设密码两段式流程
- 降低模块耦合性：`CardoryStore` 不再依赖 `AppSettings` 解析文件路径
- 同步协调器改为注入 `SyncProviderFactory`，Provider 工厂提取到独立注册表
- 提取 `AppSection` 枚举和 UI 组件（sidebar、section nav、badges）到独立文件，精简 `main.dart`
- 升级 Android 工具链：AGP 9.2.0、Kotlin 2.3.20、Gradle 9.7、Java 21
- CI Release 工作流改用自定义 release body 输出多平台产物链接
- 侧边栏展开/收起切换增加平滑动画（`AnimatedContainer` + `AnimatedOpacity`），折叠态间距微调
- `SettingsPanel` 新增 `dataPath` 参数
- `SettingsDialog` 新增 `currentDataPath` 参数 + 本地数据分区
- `SettingsCategoryType` 枚举新增 `localData`

### 修复（Fixed）

- 修复“待办”和“项目”标签页无法新增项目/待办的问题：两个面板标题栏新增“新建项目”“添加待办”入口按钮，空列表时显示对应的快捷新增按钮，行为与首页新增操作一致
- 修复侧边栏切换标签时原标签也会播放取消选中动画的问题：现在仅新选中的标签触发高亮提示动画，取消选中的标签直接复位、不播放动画
- 修复密码按钮默认点击目标导致左侧布局空间仍超出输入框的问题
- 将密码可见性控件改为固定尺寸手势区域，避免 Material 按钮默认外层尺寸继续撑开布局
- 修复首次同步时远端已有 Cardory 数据会被直接判定为冲突、无法下载的问题；首次同步现在会安全拉取远端数据并记录同步 revision 与哈希
- 修复 widget 测试未注入内存保险库凭据存储，导致主页及响应式布局测试停留在保险库入口的问题
- 清理保险库页面和同步提供者注册表中的静态分析问题，修正 WebDAV 与工作区同步接口的 `override` 标注
- 统一注释风格（`///` → `//`），消除 IDE 误触发文档生成

### 删除（Removed）

- 移除恢复码机制：仅采用密码保存与密码加盐加密存储方案，数据加密、解锁、改密与备份恢复解密都只需认证加密密码，不再生成、展示、导入或导出恢复码
- 简化密钥槽模型：加密容器仅保留密码密钥槽，移除恢复密钥槽、恢复码轮换与恢复码格式校验等代码路径
- 移动端移除 `dataPath` 持久化字段，不再使用本地数据路径

## [0.0.3] - 2026-08-11

### 修复（Fixed）

- 修复解锁页面顶部 logo 被横向拉伸变形的问题（改用 `BoxFit.contain` + `AspectRatio`）

### 变更（Changed）

- 移除 README 依赖版本号中的 `^` 前缀，改为精确版本

### 删除（Removed）

- 移除 CI 工作流（`.github/workflows/ci.yml`），保留 Tag 触发的 Release 构建

## [0.0.2] - 2026-08-11

### 新增（Added）

- README.md 全面重写，新增软件作用、架构设计、运行环境等详细章节
- CI 工作流：每次 push 到 main 自动运行 `flutter analyze` 和 `flutter test`

### 变更（Changed）

- 完善多平台发布工作流，统一产物命名规范（平台-架构-版本号）
- Android APK 仅构建 arm64 架构

### 修复（Fixed）

- 修复 GitHub Actions 密钥检查逻辑，从 `if` 条件移至 `run` 块内

## [0.0.1] - 2026-08-10

### 新增（Added）

- 首个发布版本，包含核心功能：
  - 项目看板（创建、编辑、删除、阶段与优先级管理）
  - 进度时间线（关键节点记录与自动归档）
  - 待办管理（主待办与子待办、优先级提醒）
  - 资产台账（资产维护、登录信息与变动记录）
  - 自定义主题（预设色板与深色自动暗色模式）
  - AES-256-GCM 加密保险库（密码 + 恢复码双密钥槽）
  - 三种同步后端（目录 / WebDAV / 自建服务）
  - 多平台支持（Windows / Android / iOS / macOS）
