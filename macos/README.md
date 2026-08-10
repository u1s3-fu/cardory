# macOS 平台配置

本目录包含 Cardory macOS 应用的平台原生配置与资源。

- `Runner/`：macOS 应用主 Target，包含 `Info.plist`、菜单配置、图标资源集和入口代码。
- `Runner.xcodeproj/` / `Runner.xcworkspace/`：Xcode 项目与工作区。
- `RunnerTests/`：macOS 原生单元测试。

图标与应用元数据通常由 Flutter 构建流程根据 `assets/branding/app_icon_source.png` 同步更新。
