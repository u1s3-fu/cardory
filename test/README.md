# 测试

本目录存放 Cardory 的 Flutter 测试文件。

当前测试内容：

- `widget_test.dart`：覆盖主页渲染、加载失败恢复、响应式布局、设置、资产、密码、同步操作等多个 Widget 场景。
- 其他 `*_test.dart`：对应 `lib/` 各模块的单元/Widget 测试，包括加密容器、数据存储、附件、同步提供者、同步协调器和工作区控制器。

运行方式：

```bash
flutter test
```
