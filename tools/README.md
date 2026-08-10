# 开发工具脚本

本目录存放 Cardory 开发过程中使用的辅助脚本。

- `gen_win_icon.ps1`：PowerShell 脚本，将 `assets/branding/app_icon_source.png` 裁剪并缩放为 16/24/32/48/64/128/256 多尺寸 PNG，最终组装成 `windows/runner/resources/app_icon.ico`。

运行方式（项目根目录）：

```powershell
powershell -ExecutionPolicy Bypass -File tools/gen_win_icon.ps1
```
