# 板记 Cardory

Cardory 是一个以**项目看板、进度记录和待办管理**为核心的 Flutter 本地优先应用。所有数据保存于本机加密保险库，无需联网即可使用。

## 功能特性

- **项目看板**：项目创建、编辑、删除，阶段（计划/推进中/待验收/完成）与优先级管理
- **进度时间线**：记录项目关键节点与阶段变化，随进度自动归档
- **待办管理**：待办与子待办、完成勾选、已完成标签、按优先级提醒
- **资产台账**：资产维护（服务器/网络设备等），支持登录信息与**变动记录**留痕
- **自定义主题**：背景色与强调色自由搭配，预设色板，深色背景自动切换暗色模式
- **加密保险库**：AES-256-GCM 认证加密，密码 / 恢复码双密钥槽保护

## 数据安全

- 数据正文使用 **AES-256-GCM** 认证加密
- 随机 256 位数据密钥分别由**密码密钥**和**恢复密钥**保护
- 密码使用 PBKDF2-HMAC-SHA256 派生，默认迭代 **210000** 次


## 数据文件

默认数据文件位于系统应用文档目录的 `Cardory/cardory-data.cardory`。

- 每次覆盖保存前会生成 `cardory-data.cardory.bak` 自动备份
- 写入过程使用同目录临时文件，完成格式与完整性检查后再替换正式文件
- 密码修改和恢复码轮换走相同的**串行原子写入**流程
- 损坏时自动尝试从备份恢复

> 自定义路径适合个人同步目录，但当前**不支持多设备同时编辑**。多个实例同时修改同一文件可能产生业务冲突。

## 平台支持

- **Windows** / **Android** / **iOS** / **macOS** 工程结构完整
- WebDAV 与自建服务需要平台出站网络权限：
  - Android 主清单已声明 `INTERNET`
  - macOS Debug/Release 沙盒已启用 `com.apple.security.network.client`
  - 生产环境应优先使用 **HTTPS**

## 开发环境

- Flutter stable
- Dart SDK `3.9.2`

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

## 发布检查

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --fatal-infos
flutter test
flutter build windows --release
flutter build appbundle --release
```

> Android 正式发布前必须配置独立 application ID 和 release keystore，不能使用调试签名。

## 目录结构

```
lib/
├─ main.dart                # 应用入口与页面
├─ application/             # 应用层（业务用例）
├─ data/                    # 数据层（持久化）
├─ domain/                  # 领域模型（models / container）
├─ presentation/            # 展示层（主题、颜色）
└─ sync/                    # 同步（WebDAV / 自建服务）
```
