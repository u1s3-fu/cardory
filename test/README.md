# 测试

本目录存放 Cardory 的 Flutter 测试文件。

当前测试内容：

- `widget_test.dart`：3 个 Widget 测试 — 主页渲染（"板记 Cardory" 文字存在）、
  数据加载失败时显示错误 UI 与重试按钮、快速添加子待办的多行输入正确性。
- `*_test.dart`：对应 `lib/` 各模块的单元/Widget 测试（扩展目录）。

运行方式：

```bash
flutter test
```
