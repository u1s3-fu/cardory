# Changelog

Cardory 版本更新日志。遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/) 格式。

## [0.0.4] - 2026-08-11

### Changed

- 降低模块耦合性：`CardoryStore` 不再依赖 `AppSettings` 解析文件路径
- 同步协调器改为注入 `SyncProviderFactory`，Provider 工厂提取到独立注册表
- 提取 `AppSection` 枚举和 UI 组件（sidebar、section nav、badges）到独立文件，精简 `main.dart`
- 升级 Android 工具链：AGP 9.2.0、Kotlin 2.3.20、Gradle 9.7、Java 21
- CI Release 工作流改用自定义 release body 输出多平台产物链接

### Removed

- 移动端移除 `dataPath` 持久化字段，不再使用本地数据路径

### Fixed

- 统一注释风格（`///` → `//`），消除 IDE 误触发文档生成

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

[0.0.4]: https://github.com/u1s3-fu/cardory/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/u1s3-fu/cardory/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/u1s3-fu/cardory/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/u1s3-fu/cardory/releases/tag/v0.0.1
