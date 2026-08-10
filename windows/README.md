# Windows 平台配置

本目录包含 Cardory Windows 应用的平台原生配置与资源。

- `runner/`：Windows 应用主目录，包含 C++ 入口、资源文件（`app_icon.ico`、应用清单）和窗口配置。
- `CMakeLists.txt`：Windows 构建配置。
- `flutter/`：Flutter 引擎嵌入相关代码。

`tools/gen_win_icon.ps1` 脚本用于根据 `assets/branding/app_icon_source.png` 生成多尺寸 `app_icon.ico`。
