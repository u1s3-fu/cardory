# iOS 平台配置

本目录包含 Cardory iOS 应用的平台原生配置与资源。

- `Runner/`：iOS 应用主 Target，包含 `Info.plist`、启动屏 Storyboard、图标资源集和 Swift/Objective-C 入口。
- `CardoryWidget/`：WidgetKit 源码、共享组配置和小组件资源；当前 Widget Extension target 尚未接入 `Runner.xcodeproj`，不会随默认 Runner 构建发布。
- `Runner.xcodeproj/` / `Runner.xcworkspace/`：Xcode 项目与工作区。
- `RunnerTests/`：iOS 原生单元测试。

应用图标、启动图和显示名称通常由 Flutter 构建流程和工具脚本根据 `assets/branding/app_icon_source.png` 同步更新。
