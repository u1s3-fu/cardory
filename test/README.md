# 测试

本目录存放 Cardory 的单元测试、Widget 测试和同步集成测试。

测试结构：

- `*_test.dart`：对应 `lib/` 下各模块的单元/集成测试。
- `widget_test.dart`：Flutter Widget 测试示例。

运行方式：

```bash
flutter test
```

测试覆盖范围包括：领域模型序列化、加密容器编解码、本地存储、目录/WebDAV/自建服务同步以及自动锁定控制器。
