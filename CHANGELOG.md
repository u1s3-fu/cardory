# Changelog

Cardory 版本更新日志。遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 格式。

## [Unreleased]

## [0.0.5] - 2026-08-22

### Fixed

- 修复项目详情页无 `Scaffold` 导致附件行 `Chip` 在操作重建时报「No Material widget found」的异常：详情页根补包 `Scaffold`（同时使 SnackBar 能正确显示在详情页）；附件面板错误提示改为先清除排队提示再展示，避免「附件更新失败」等具体错误被父级通用错误提示延迟显示

### Changed

- Windows Release 新增 Inno Setup 安装程序产物（`cardory-windows-x64-版本-setup.exe`），支持用户级安装、开始菜单/桌面快捷方式与覆盖升级；原有 ZIP 改名为便携版（`cardory-windows-x64-版本-portable.zip`）并继续发布，更新资产默认优先安装程序

- 新增「关于」对话框：设置面板新增「关于」入口，展示应用名称、版本号、功能简介、GPL-3.0 许可证与 GitHub 开源仓库链接（点击链接在系统浏览器中打开）；版本号经 `package_info_plus` 实时读取
- 设置入口重组：「检查更新」从设置面板移入「关于」对话框（作为底部操作按钮，先关对话框再执行检查）；「本地数据」选项并入原「同步」分区，分区改名「数据与同步」（设置面板入口卡片与设置对话框分区标题同步更新），本地数据文件路径在同步分区内展示；`SettingsCategoryType.localData` 枚举随之移除
- 项目采用 **GPL-3.0 双许可**（Dual License）模式：新增 `LICENSE` 文件（GPL-3.0 官方全文），开源版衍生作品须保持 GPL-3.0 开源，闭源商用需获取商业授权；README 许可证章节由「私有项目」改为双许可说明，许可证徽章同步更新为 GPLv3
- 新增「检查更新」功能：应用启动后静默检查 GitHub Releases 最新版本，设置面板新增「检查更新」入口可手动检查；发现新版本时弹窗展示当前/最新版本与更新说明，并按当前平台提供安装包直链下载（Windows/Android/macOS），另可一键打开 GitHub Releases 页面；版本比较忽略 `v` 前缀与 `+` 构建号，GitHub 预发布版本自动跳过；新增依赖 `package_info_plus`（读取本地版本）与 `url_launcher`（打开下载链接）
- 界面整体减重（去除"UI 感重"）：Overview 统计卡去除 36×36 彩色图标块与 4 色轮转，改统一灰色小图标；看板列由阶段彩色浅底+彩色边框改为中性白底、标题灰色；项目卡片/待办/提醒/进度条目边框统一淡化（gray100）并全部去除阴影；附件图标统一灰色；HeroHeader 保持克制排版
- 设置页「上传附件时重命名」与「重命名时保留文件扩展名」解除关联：两个选项现相互独立，即使不开启上传时重命名，也能单独配置重命名时保留扩展名（该选项同时作用于附件面板内手动重命名单个附件）
- 前端全面扁平化重新设置（Flat Design）：移除首页背景、看板列与深色 Hero 的全部渐变（`home_page` 背景改纯色 `gray50`、看板列改纯色阶段浅底、`cardoryDarkHero` 改纯色品牌底）；卡片/看板列/顶部栏/面板阴影统一减淡（alpha 0.02–0.06，blur 6–12，偏移 0–4），看板阶段点阴影改细描边；主题文档与风格描述同步更新
- 桌面端滚动条彻底隐藏：新增全局 `CardoryScrollBehavior`（`buildScrollbar` 直接返回子组件），任何平台均不再构建 Scrollbar 组件，保留滚轮/键盘/触控板滚动；`scrollbarTheme` 同步置为不可见，替换此前「常显细胶囊滚动条」设计
- 新增全局动效系统 `lib/presentation/cardory_motion.dart`：统一时长分层（微交互 120ms / 快速 160ms / 基础 220ms / 慢 300ms / 页面 320ms）与缓动曲线约定（进入 easeOutCubic、退出 easeInCubic、往返 easeInOutCubic、轻微回弹 easeOutBack）；`cardoryAnimDuration` 迁入本文件，继续随系统「减弱动态效果」自动归零
- 页面转场统一：`CardoryPageTransitionsBuilder`（新页淡入 + 6% 横移 + 旧页轻微下沉形成层级），全平台一致，替代默认缩放转场
- 微交互增强：项目卡片悬停时阴影与边框柔和增强（160ms easeInOutCubic，无位移、不改变布局），并显式设置手型光标
- 侧栏展开/收起、选中高亮、首页内容切换（`AnimatedSwitcher`）等现有动画统一接入动效系统常量，全应用动画节奏一致
- 加载态一致性：`progressIndicatorTheme` 补充 `circularTrackColor`，线性与圆形加载指示配色统一
- 低优项第二轮收尾：项目详情页标题长文本改为单行省略（`maxLines: 1` + `TextOverflow.ellipsis`），避免标题过长撑高布局；项目页“取消完成/删除待办”两个内联确认 `AlertDialog` 改用公共 `showConfirmDialog`
- 列表项补充稳定 `ValueKey`（资产/附件列表行、子待办卡片、同步合并冲突项），避免筛选/折叠/重排时 Flutter 按位置复用导致状态错乱
- 附件面板“附件更新失败”错误提示去重：原先对话框 + SnackBar 双重提示，现与文件内其他错误处理一致，仅提示一次 SnackBar
- 无障碍：`CountPill` 新增可选读屏语义标签（`semanticLabel`），看板列计数传入“N 个项目”；`Overview` 头像取色对空 label 做兜底（`codeUnitAt(0)` 不再可能越界）
- 修复分类/标签重命名对话框的 `setState` 缺少 `mounted` 检查（异步对话框关闭后重建可能触发 `setState() called after dispose()`）
- 前端全面体检优化：资产/附件/待办/看板列表由全量 `Column` 渲染改为 `ListView.builder` 懒加载；资产标签、附件分类与详情标签的名称查找由逐行线性遍历改为预建 `Map` 查询（O(n×m) → O(n+m)）；看板按阶段分组由每列重复遍历改为一次遍历分组；`GroupedExpansionList` 聚合结果缓存复用，折叠/展开不再重复计算分组
- 无障碍（WCAG）改进：设置页同步错误、保险库解锁错误、修改密码/恢复设置错误、待办与项目对话框错误文字等 7 处错误色文字自动加深至对比度 ≥ 4.5:1；待办完成/未完成状态图标改用 ≥ 3:1 对比度色；资产详情“已创建”图标与其他删除图标风格一致；删除标签/分类确认按钮背景色加深与附件面板保持一致
- 无障碍（WCAG）改进：待办完成切换按钮、待办删除、进度编辑、分类/标签重命名与删除等 6 处图标按钮触控目标提升至 44×44px；侧边栏导航项高度由 38px 提升至 44px，达到最小触控面积要求
- 抽取公共文本输入对话框 `showTextInputDialog`（支持多行、非空校验、输入法动作与标签对齐），替换附件备注/重命名、分类重命名、标签重命名、子待办编辑等 5 处重复的内联 `AlertDialog` 实现；分类/标签删除确认改用公共 `showConfirmDialog`
- 文件大小格式化统一为 `domain/cardory_utils.dart` 的 `formatFileSize`（B/KB/MB/GB，保留 1 位小数），替换 `attachment_row` 与 `cloud_restore_service` 两处行为不一致的实现
- `SyncProviderException` 新增机器可读错误码 `SyncProviderErrorCode`（凭据缺失等），同步配置区错误提示改为按错误码结构化判断，不再依赖中文字面量匹配
- 日期选择器上下界统一为 `domain/cardory_utils.dart` 的 `minPickerDate`/`maxPickerDate` 常量，消除 3 处 `DateTime(2000)`/`DateTime(2100)` 魔法数字
- 资产面板“新增资产”按钮由 `FilledButton.icon` 统一为 `FilledButton.tonalIcon`，与附件面板主操作按钮风格一致
- 架构清理：删除 `WorkspaceController.updateProject` 冗余别名（统一使用 `editProject`）；`AssetDialogResult`/`PasswordChangeResult` 从 `settings_models.dart` 移入各自所属对话框文件，`settings_models.dart` 仅保留设置结果模型；`cardory_app.dart` 的 barrel 导出补充注释说明（作为测试统一入口，勿删）
- 首页共享组件文件 `dashboard.dart` 拆分并删除（约 440 行 → 0）：`AppTopBar`/`HeroHeader`/`Overview`+`OverviewCard`/`ProjectListPanel`/`ProgressTimeline` 六组件分别拆至 `widgets/app_top_bar.dart`/`widgets/hero_header.dart`/`widgets/overview.dart`/`widgets/project_list_panel.dart`/`widgets/progress_timeline.dart`；`home_page`/`project_page` 改为按需 import，`cardory_app.dart` 公开导出同步更新，组件对外行为不变
- 主题文件 `cardory_theme.dart` 拆分（689 行 → 505 行）：新增 `cardory_palette.dart`，搬移调色板/色彩纯函数部分（`CardoryPalette`/`CardoryColors`/`cardoryDefaultPalette`/`paletteFromColors`/`applyCardoryColors`/`brightnessForBackground`/`cardoryContrast`/`cardoryEnsureContrast`/`cardoryEnsureWhiteContrast`/`cardoryTint`/`cardoryShade`），`cardory_theme.dart` 保留 `buildCardoryTheme` 主题构建与装饰；经 `export 'cardory_palette.dart'` 保持原入口兼容，现有引用与行为不变
- 设置对话框 `settings_page.dart` 拆分（约 1120 行 → 约 300 行）：新增 `widgets/color_picker_section.dart`（`ColorPickerSection` 外观颜色编辑区，预设色点 + 三通道滑块 + 十六进制输入，颜色状态自持并实时上报）、`widgets/sync_settings_section.dart`（`SyncSettingsSection` 同步配置区，含各提供者字段与连接测试，表单状态自持，保存时经 `GlobalKey` 一次性收集）、`pages/settings_panel.dart`（工作台设置入口面板 `SettingsPanel` 与 `isCloudSync` 判断独立成文件）；所有测试相关 Key（`theme-color-red-slider`/`test-webdav-connection`/`test-s3-connection`/`home-reminder-priority-field`/`record-subtodo-created-at`/`auto-lock-enabled` 等）与保存行为保持不变，顺手删除无使用者的 `FirstOrNullExtension`；`cardory_app.dart` 补充导出、`home_page.dart` 补充设置面板引用
- 任务对话框 `task_dialogs.dart` 拆分（909 行 → 移除）：拆为 `widgets/project_dialog.dart`（`ProjectDialog` 项目创建/编辑）、`widgets/todo_dialog.dart`（`TodoDialog` 待办创建/编辑）、`widgets/subtodo_dialogs.dart`（`QuickAddSubTodoDialog` 快捷添加子提醒、`SubTodoManagerDialog` 子待办管理，含子提醒日期时间选择器与子待办创建辅助）、`widgets/date_field.dart`（公共日期选择字段 `DateField`，由 `_DateField` 改为公共组件）；`home_page.dart` 与 `cardory_app.dart` barrel 导出同步更新，测试依赖的 Key（`quick-add-subtodo-content`、`quick-add-subtodo-reminder-time`）保持不变
- `home_page.dart` 对话框抽取（831 行 → 698 行）：新增 `widgets/sync_conflict_dialogs.dart`（`showSyncConflictDialog` 同步冲突选择对话框、`showManualMergeDialog` 手动合并对话框）、`widgets/confirm_dialogs.dart`（通用确认对话框 `showConfirmDialog`）；同步冲突流程与项目/待办/资产删除确认改用公共对话框，行为与测试文本保持不变
- `sync_coordinator.dart` 逻辑拆分（826 行 → 619 行）：新增 `sync/sync_config_sync.dart`（`CloudConfigSync` 配置文档双向同步服务，含 `configKey` 常量，`SyncCoordinator.configKey` 保留转发兼容外部引用）、`sync/sync_data_merger.dart`（`buildSyncConflictItems` 冲突项对比、`mergeSyncData` 按选择合并数据两个顶层函数）；同步编排、附件同步与冲突解析逻辑保持不变
- 项目详情页 `project_page.dart` 拆分（约 1105 行 → 约 416 行）：新增 `widgets/project_assets_panel.dart`（`ProjectAssetsPanel` 资产面板，含标签筛选、分组、批量分配标签与标签管理入口）、`widgets/asset_tag_dialogs.dart`（`AssetTagManagerDialog` 标签管理、`AssetTagAssignDialog` 标签分配对话框）；`ProjectDetailPage` 保持受控组件签名（数据与回调由父级注入，含 `onToggleTodo`/`onOpenTodo`/`onAddAsset`/`onUpdateAssetsTags` 等），测试依赖的 Key（`manage-asset-tags-button`、`toggle-asset-batch-button`、`add-project-asset-button`）与附件删除失败回滚行为保持不变
- 附件面板 `project_attachments_panel.dart` 拆分（约 1270 行 → 约 640 行）：新增 `widgets/attachment_row.dart`（`AttachmentRow` 附件行组件与 `AttachmentRowAction` 操作枚举，含文件类型图标与大小格式化）、`widgets/attachment_dialogs.dart`（`CategoryManagerDialog` 分类管理、`CategoryAssignDialog` 分类分配、`BatchRenameDialog` 批量重命名对话框，以及 `stripExtension`/`applyRenameKeepingExtension` 文件名工具）；主面板保留导入、筛选、分组、批量操作与分类管理入口逻辑，测试依赖的 Key（`manage-attachment-categories-button`、`toggle-attachment-batch-button`、`add-project-attachment-button`）与交互行为保持不变
- 依赖方向重构：将 `WorkspaceRepository`、`SyncRepository`、`VaultRepository`、`CardoryRepository`、`VaultSessionRepository`、`AttachmentRepository`、`SyncCredentials`、`SyncStatus`、`WorkspaceSyncService`、`WidgetDataService` 等接口与模型从 `lib/application/` 下沉至 `lib/domain/`，由应用服务层与表现层统一引用 domain 层，消除对基础设施实现细节的反向依赖
- `CloudRestoreService` 从 `lib/application/` 迁移至 `lib/sync/`，应用层不再依赖同步实现；`vault_gate`、`cloud_restore_dialog` 相应改用 `sync/cloud_restore_service.dart` 引用
- 设置页“测试连接”改为依赖注入：`connectionTester` 由 `CardoryApp` 逐层传入（`CardoryVaultGate` → `HomePage` → `SettingsDialog`），默认实现为 `testSyncConnection`，表现层不再直接引用同步提供者注册表
- `VaultCredentialStore`（保险库主密码存储接口）从 `lib/sync/` 下沉至 `lib/domain/`，`settings_page`、`vault_gate`、`home_page`、`cloud_restore_dialog` 的同步凭据类型引用统一改为直接依赖 `domain/sync_credentials.dart`，组合根 `CardoryApp` 仅从 sync 层导入安全存储实现类，表现层对同步实现层的直接依赖进一步收敛
- 删除已无引用的 `lib/services/widget_data_service.dart` 冗余转发文件（`WidgetDataService` 接口统一以 `domain/widget_data_service.dart` 为唯一来源）
- 拆分首页巨文件 `dashboard.dart`（约 1450 行 → 页面骨架约 520 行）：看板（`KanbanBoard`/`KanbanColumn`/`ProjectCard`）拆至 `widgets/kanban_board.dart`，待办（`TodoPanel`/`TodoTile`/`SubTodoTile`）拆至 `widgets/todo_panel.dart`，提醒面板（`ReminderPanel`）拆至 `widgets/reminder_panel.dart`，资产详情（`AssetDetailDialog`）拆至 `widgets/asset_detail_dialog.dart`；`CardoryApp` 的公开导出与 `home_page`/`project_page` 的引用同步更新，组件对外行为不变
- 拆分领域模型巨文件 `cardory_models.dart`（约 850 行 → 约 20 行的聚合入口）：按聚合拆分为 `cardory_enums.dart`（`ProjectStage`/`ProjectPriority`）、`asset_models.dart`（附件/资产/标签/变动记录）、`project_models.dart`（项目/进度记录）、`todo_models.dart`（待办/子待办）、`cardory_data.dart`（聚合根 `CardoryData`）与 `cardory_utils.dart`（`newId`/`formatDate` 等工具函数）；`ProjectPriority` 从 `app_settings.dart` 迁入 `cardory_enums.dart`（原定义位置属于领域模型错放），`app_settings.dart`、`model_labels.dart` 相应改用新入口，原 `cardory_models.dart` 保留为领域模型统一出口，现有引用不受影响
- 抽取通用分组折叠列表组件 `widgets/grouped_expansion_list.dart`（`GroupedExpansionList`，支持条目多分组归属、折叠状态自管理、未分组尾部）与批量操作条组件 `widgets/batch_action_bar.dart`（`BatchActionBar`）：`project_attachments_panel.dart` 的按分类分组视图、`project_page.dart` 资产面板的按标签分组视图及各自的批量操作条统一改用新组件，消除两处约 180 行重复的分组折叠/批量操作实现，折叠状态从页面下沉至组件，行为与界面保持不变
- CI Release 工作流自动从 `CHANGELOG.md` 提取当前版本（如 `[0.0.4]`）的完整更新日志区块（含版本标题）填充 GitHub Release 说明，不附加平台说明等额外内容；找不到对应版本区块时回退为默认模板并给出警告
- 无障碍（WCAG）改进：新增 `cardoryAnimDuration` 工具函数，侧栏展开/收起、选中高亮、页面切换等动画在系统开启「减弱动态效果」时不再播放过渡动画
- 无障碍（WCAG）改进：桌面端所有按钮（填充/描边/文字/图标按钮）统一设置点击光标，hover 时鼠标显示可点击反馈
- 无障碍（WCAG）改进：密码可见性切换按钮触控目标从 28×28 提升至 40×40，图标同步放大，达到最小触控面积要求
- 无障碍（WCAG）改进：侧栏折叠按钮、待办完成切换按钮补充 Tooltip/语义标签，便于读屏与自动化测试识别
- 无障碍（WCAG）改进：次要文字色 `gray400` 默认值加深（`#98A1BA` → `#7C86A3`），动态浅色主题的灰色文字同步加深，提升与背景的对比度
- 无障碍（WCAG）改进：所有以 `gray400`（3.62:1）作正文/元信息文字的地方（待办项目名与日期、子待办计数、提醒面板项目名、看板时间戳、徽章空态、资产变动时间戳、待办“未设置”、项目/附件空态提示、仪表盘时间戳、输入框 hint 文字等）统一改用 `gray500`（4.73:1），达到 WCAG AA 4.5:1 对比度要求；`gray400` 仅保留用于图标与删除线完成态等豁免场景
- 无障碍（WCAG）改进：强调色（primary）在主题构建时自动加深至与白色对比度 ≥ 4.5:1，保证用户自定义浅色强调色时按钮白字与 `onPrimary` 文字始终可读
- 无障碍（WCAG）改进：提升过小字号可读性——待办时间标签从 10.5px 提升至 11px，优先级/阶段徽章从 11px 提升至 11.5px
- 无障碍（WCAG）改进：优先级/阶段徽章（`PriorityBadge`/`StageBadge`）文字色统一加深至与白底对比度 ≥ 4.5:1（P0 2.86→6.33、P1/review 2.07→6.86、P3/planned 3.28→6.69、done 2.48→4.83），并新增 `onDark` 模式——渲染于深色渐变 hero 上时改用「加深实底 + 白字」保证可读（此前 doing 徽章在 hero 亮端仅 1.00:1，几乎不可见）；项目详情页 hero 的描述文字由 `#CBD5E1`（3.19:1）提亮为 `#F8FAFC`（4.52:1）
- 无障碍（WCAG）改进：错误/警告语义色作为小字或图标时自动加深——删除确认按钮背景、同步错误文字、过期提醒日期文字（2.86:1）与"已完成"chip（3.30:1）改用 `cardoryEnsureWhiteContrast` 加深后的颜色，仪表盘统计卡 warning/error 图标与资产详情删除图标加深至 ≥ 3:1（图形对比度要求）
- 代码整洁：删除无引用的 `darkCardDecoration()` 死代码；`settings_panel` 上次同步时间与 `cloud_restore_dialog` 备份时间统一复用 `formatDateTime`，消除重复的日期时间拼接实现；文件名工具 `stripExtension`/`applyRenameKeepingExtension` 从 `widgets/attachment_dialogs.dart` 下沉至 `domain/cardory_utils.dart`（纯领域逻辑不再寄居于对话框组件文件）；通用确认对话框 `showConfirmDialog` 新增可选 `confirmColor`（危险操作红色确认按钮，自动保证白字对比度），附件面板批量删除改用该公共对话框，行为与界面保持不变
- 修复同步连接测试的凭据逻辑缺陷（`sync_settings_section.dart`）：此前"测试连接"只读取系统安全存储中已保存的凭据，表单中本次输入的密码/密钥完全不参与测试，导致首次配置 WebDAV/S3 时测试必然报"WebDAV 密码尚未保存"，且必须"先保存设置 → 重开设置 → 再测试"才能通过；现改为测试凭据"表单本次输入优先、已保存值兜底"（仅用于验证，不持久化任何值），表单与存储均无凭据时给出明确操作引导（"请先输入 WebDAV 密码后再测试连接"），测试成功统一提示"连接成功，可以保存设置。"，底层异常提示去掉 `SyncProviderException:` 前缀；测试用例同步更新为先输入密码再点击测试

### Fixed

- 修复保险库解锁/初始化流程的潜在崩溃：`_inspect` 异步回调的 `else` 分支缺少 `mounted` 检查，页面销毁后 `setState` 可能触发 `setState() called after dispose()`，现已补全检查

## [0.0.4] - 2026-08-21

### Added

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

### Changed

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

### Fixed

- 修复“待办”和“项目”标签页无法新增项目/待办的问题：两个面板标题栏新增“新建项目”“添加待办”入口按钮，空列表时显示对应的快捷新增按钮，行为与首页新增操作一致
- 修复侧边栏切换标签时原标签也会播放取消选中动画的问题：现在仅新选中的标签触发高亮提示动画，取消选中的标签直接复位、不播放动画
- 修复密码按钮默认点击目标导致左侧布局空间仍超出输入框的问题
- 将密码可见性控件改为固定尺寸手势区域，避免 Material 按钮默认外层尺寸继续撑开布局
- 修复首次同步时远端已有 Cardory 数据会被直接判定为冲突、无法下载的问题；首次同步现在会安全拉取远端数据并记录同步 revision 与哈希
- 修复 widget 测试未注入内存保险库凭据存储，导致主页及响应式布局测试停留在保险库入口的问题
- 清理保险库页面和同步提供者注册表中的静态分析问题，修正 WebDAV 与工作区同步接口的 `override` 标注
- 统一注释风格（`///` → `//`），消除 IDE 误触发文档生成

### Removed

- 移除恢复码机制：仅采用密码保存与密码加盐加密存储方案，数据加密、解锁、改密与备份恢复解密都只需认证加密密码，不再生成、展示、导入或导出恢复码
- 简化密钥槽模型：加密容器仅保留密码密钥槽，移除恢复密钥槽、恢复码轮换与恢复码格式校验等代码路径
- 移动端移除 `dataPath` 持久化字段，不再使用本地数据路径

## [0.0.3] - 2026-08-11

### Fixed

- 修复解锁页面顶部 logo 被横向拉伸变形的问题（改用 `BoxFit.contain` + `AspectRatio`）

### Changed

- 移除 README 依赖版本号中的 `^` 前缀，改为精确版本

### Removed

- 移除 CI 工作流（`.github/workflows/ci.yml`），保留 Tag 触发的 Release 构建

## [0.0.2] - 2026-08-11

### Added

- README.md 全面重写，新增软件作用、架构设计、运行环境等详细章节
- CI 工作流：每次 push 到 main 自动运行 `flutter analyze` 和 `flutter test`

### Changed

- 完善多平台发布工作流，统一产物命名规范（平台-架构-版本号）
- Android APK 仅构建 arm64 架构

### Fixed

- 修复 GitHub Actions 密钥检查逻辑，从 `if` 条件移至 `run` 块内

## [0.0.1] - 2026-08-10

### Added

- 首个发布版本，包含核心功能：
  - 项目看板（创建、编辑、删除、阶段与优先级管理）
  - 进度时间线（关键节点记录与自动归档）
  - 待办管理（主待办与子待办、优先级提醒）
  - 资产台账（资产维护、登录信息与变动记录）
  - 自定义主题（预设色板与深色自动暗色模式）
  - AES-256-GCM 加密保险库（密码 + 恢复码双密钥槽）
  - 三种同步后端（目录 / WebDAV / 自建服务）
  - 多平台支持（Windows / Android / iOS / macOS）
