# 板记 Cardory

Cardory 是一个以**项目看板、进度记录和待办管理**为核心的 Flutter 本地优先跨平台应用。保险库正文和附件在写入磁盘前使用 AES-256-GCM 加密；应用设置另存为不含同步密钥的 JSON 文件。无需联网即可使用。

![Version](https://img.shields.io/badge/version-0.0.4-blue) ![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter) ![Dart](https://img.shields.io/badge/Dart-3.12.2-0175C2?logo=dart) ![License](https://img.shields.io/badge/license-GPLv3-blue)

---

## 软件作用

### 项目管理

- **项目看板**：创建、编辑、删除项目，直观总览所有项目及其状态
- **阶段管理**：支持四级阶段流转 —— 计划中 → 进行中 → 待验收 → 已完成
- **优先级划分**：P0（高优先级）/ P1（中）/ P2（普通）/ P3（低），颜色编码一目了然
- **进度追踪**：百分比进度条展示，关键节点可按时间线记录，阶段变更自动归档

### 待办管理

- **多级待办**：支持主待办与子待办（SubTodo），灵活拆分任务
- **完成勾选**：勾选即归档，支持按完成状态筛选查看
- **优先级提醒**：按 P0-P3 优先级排序与高亮显示
- **日期范围**：可设定待办的起止日期，便于跟踪计划执行周期

### 资产台账

- **资产登记**：记录软件/硬件资产（服务器、网络设备、域名等）
- **登录信息**：支持关联账号、密码、IP 地址等凭据信息
- **变动记录**：资产变更历史自动留痕，可追溯每次修改

### 自定义主题

- **自由配色**：背景色与强调色自由搭配，打造个性化工作空间
- **预设色板**：提供 7 种精心设计的预设主题色组合，一键切换
- **自动暗色模式**：当选择深色背景时，文字与控件自动切换为亮色，无需手动配置

### 数据同步

- **目录同步**：将加密数据文件放置于任意本地目录或网盘同步目录中
- **WebDAV 同步**：连接 WebDAV 服务器（如 NextCloud、群晖 NAS 等）
- **自建服务**：通过 HTTP API 对接私有同步服务
- **S3 兼容存储**：连接 AWS S3、MinIO、Cloudflare R2 等支持 S3 API 的存储服务
- **冲突检测**：基于 SHA-256 哈希 + 修订版本号的冲突检测机制，防止数据覆盖

---

## 数据安全

Cardory 将安全放在首位；保险库正文和附件在写入磁盘前均经过加密处理，应用设置文件仅保存非密钥配置。

### 加密方案

- **数据正文**：使用 **AES-256-GCM** 认证加密，同时提供机密性与完整性保护
- **密钥体系**：随机生成 256 位数据密钥（DEK），由密码密钥（KEK）保护
- **密钥派生**：密码通过 **PBKDF2-HMAC-SHA256** 加盐派生加密密钥，默认迭代 **210,000 次**，有效抵御暴力破解
- **密码密钥槽**：仅使用密码加盐加密存储，解锁、改密与备份恢复解密都只需认证加密密码

### 数据保护机制

- **自动锁定**：应用切换至后台时可自动锁定保险箱（可配置开关），防止未经授权访问
- **原子写入**：每次覆盖保存前生成 `.bak` 自动备份；使用临时文件写入，完成完整性校验后再替换正式文件
- **损坏恢复**：数据文件损坏时自动尝试从 `.bak` 备份恢复
- **安全存储**：密码与 Token 使用平台原生安全机制存储（iOS Keychain / Android Keystore / Windows DPAPI）
- **独立附件加密**：附件按 1 MiB 分块使用 AES-256-GCM 独立加密，主保险库只保存文件元数据与密钥
- **流式附件传输**：附件选择、加密、同步和导出均采用流式读写，Cardory 不设置单文件或项目附件总容量上限

---

## 架构设计

### 模块边界

项目按领域模型、应用用例、持久化、同步与展示模块组织。应用层通过仓储、凭据、附件和小组件等端口依赖具体实现；当前 `CardoryApp` 同时是 Flutter 根组件和组合根，负责把 `data/`、`sync/`、`services/` 的实现注入应用层。

```
┌─────────────────────────────────────────────┐
│              Presentation 展示层             │
│  (根组件 / 页面 / 对话框 / 主题 / Widgets)    │
├─────────────────────────────────────────────┤
│              Application 应用层              │
│  (工作区控制 / 设置 / 同步 / 附件用例)         │
├─────────────────────────────────────────────┤
│               Domain 领域层                  │
│  (CardoryData / ProjectData / TodoData 等)   │
├─────────────────────────────────────────────┤
│      Infrastructure 基础设施层               │
│  (Data / Sync / Services / 平台适配器)       │
└─────────────────────────────────────────────┘
```

### 模块说明

| 模块 | 目录 | 职责 |
|------|------|------|
| **入口** | `lib/main.dart` | 调用 `runCardoryApp()` 启动 Flutter 应用 |
| **应用层** | `lib/application/` | 工作区状态、设置、同步、附件和小组件端口 |
| **领域层** | `lib/domain/` | 核心业务模型：`CardoryData`、`ProjectData`、`TodoData`、`AssetData`、`AppSettings` |
| **数据层** | `lib/data/` | AES-256-GCM 加密容器、文件仓储与附件加密存储 |
| **展示层** | `lib/presentation/` | 组合根、页面、对话框、设计系统与复用组件 |
| **同步层** | `lib/sync/` | `SyncProvider`、协调器与目录、WebDAV、自建 API、S3 后端 |
| **平台服务** | `lib/services/` | 原生桌面小组件等平台适配器 |

### 关键设计模式

- **仓储模式**：应用层以按职责拆分的仓储端口访问保险库、工作区与同步数据，`CardoryStore` 提供基于文件的实现
- **策略模式**：`SyncProvider` 抽象接口，目录、WebDAV、自建 HTTP API 与 S3 兼容存储各自实现
- **门面模式**：`CardoryVaultGate` 作为统一入口，管理解锁、密码设置、备份恢复等全生命周期
- **凭证分离**：`VaultCredentialStore` 与 `SyncCredentialStore` 分离保险库凭证与同步凭证的管理

### 数据流

```
用户操作 → WorkspaceController
               ↓
      WorkspaceRepository / SyncRepository
               ↓
   CardoryStore + CardoryContainerCodec + AttachmentStore
               ↓
       加密保险库与附件密文
```

### 状态管理

项目不依赖第三方状态管理库（如 Provider、Riverpod、Bloc 等），使用 Flutter 内置的 **StatefulWidget + setState** 进行状态管理。页面导航通过 `AppSection` 枚举 + `switch` 控制，数据通过构造函数和回调向下传递。设计上保持简洁，适合当前应用规模。

---

## 运行环境

### 平台要求

| 平台 | 最低版本 | 备注 |
|------|----------|------|
| **Windows** | Windows 10+ | 完整支持，推荐使用 |
| **Android** | Android 7.0 (API 24) | 完整支持 |
| **iOS** | iOS 13+ | 基础 Runner 工程；WidgetKit 源码和共享组配置已提供，但 Widget Extension target 尚未接入 Xcode 工程 |
| **macOS** | macOS 10.15+ | 沙盒已启用网络权限 |

### 开发环境

| 组件 | 版本 |
|------|------|
| **Flutter SDK** | stable（最新稳定版） |
| **Dart SDK** | `3.12.2`（约束 `^3.9.2`） |
| **Java / Kotlin** | JVM 21（Android） |
| **Swift** | 5.x（iOS/macOS） |

### 核心依赖

下表列出 `pubspec.yaml` 中的声明版本约束；实际解析版本以 `pubspec.lock` 为准。

| 依赖 | 版本 | 用途 |
|------|------|------|
| `path_provider` | `2.1.5` | 获取应用文档目录 |
| `cryptography` | `2.9.0` | AES-256-GCM 加密与 PBKDF2 密钥派生 |
| `http` | `1.6.0` | HTTP 客户端（同步服务） |
| `crypto` | `3.0.7` | S3 请求摘要与签名辅助 |
| `flutter_secure_storage` | `10.3.1` | 平台原生安全存储 |
| `file_picker` | `10.3.0` | 文件选择（备份导入/导出） |
| `path` | `1.9.1` | 路径操作 |
| `home_widget` | `0.7.0` | Android / iOS 桌面小组件数据桥接 |
| `webdav_client` | `1.2.2` | WebDAV 兼容性支持 |

### 开发依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `flutter_lints` | `5.0.0` | 代码规范检查 |
| `flutter_launcher_icons` | `0.14.4` | 自动生成多平台应用图标 |

---

## 数据文件

默认数据文件位于系统应用文档目录的 `Cardory/cardory-current-data.cardory`。同步设置单独保存在同目录的 `Cardory/cardory-current-settings.json`，该设置文件不保存同步密钥。

附件密文保存在同一应用目录的 `attachments/v1/` 下；同步时对应远端的 `attachments/v1/` 对象目录。实际可用容量由本地磁盘和所选同步服务决定。

> 进行离线整机备份时，需要同时保存 `.cardory` 数据文件和 `attachments/v1/` 目录。仅有 `.cardory` 文件可以恢复附件元数据，但附件正文需要从同步服务或附件密文目录恢复。

- 每次覆盖保存前会生成 `cardory-current-data.cardory.bak` 自动备份
- 写入过程使用同目录临时文件，完成格式与完整性检查后再替换正式文件
- 密码修改走**串行原子写入**流程
- 数据损坏时自动尝试从 `.bak` 备份恢复

> **注意**：主保险库路径由应用管理；同步目录路径可在设置中配置为个人同步目录（如 OneDrive）。当前**不支持多设备同时编辑**，多个实例同时修改同一文件可能产生业务冲突。

---

## 平台网络权限

同步功能（WebDAV / 自建服务 / S3 兼容存储）需要平台出站网络权限：

- **Android**：主清单已声明 `INTERNET` 权限
- **macOS**：Debug / Release 沙盒已启用 `com.apple.security.network.client`
- **生产环境**：建议优先使用 HTTPS 以确保传输安全

---

## 快速开始

```bash
# 安装依赖
flutter pub get

# 静态分析
flutter analyze

# 运行测试
flutter test

# 启动应用（以 Windows 为例）
flutter run -d windows
```

## 发布检查

以下命令用于本地构建检查；GitHub Actions 的自动发布目前仅产出 Android、Windows 和 macOS，iOS 需要在 macOS 上单独构建，且当前不包含 Widget Extension target。

```bash
# 代码格式化检查
dart format --output=none --set-exit-if-changed lib test

# 严格静态分析
flutter analyze --fatal-infos

# 运行全部测试
flutter test

# 构建发布包
flutter build windows --release     # Windows
flutter build appbundle --release   # Android
flutter build ios --release         # iOS（仅 macOS；不含 Widget Extension）
flutter build macos --release       # macOS
```

## 应用图标

应用图标源文件位于 `assets/branding/app_icon_source.png`（1024×1024），通过 `flutter_launcher_icons` 自动生成各平台图标。Windows 图标由 `tools/gen_win_icon.ps1` 脚本生成多尺寸标准 ICO 文件。

## 目录结构

```
lib/
├── main.dart                              # 最小启动入口
├── application/                           # 应用用例与端口
├── data/                                  # 加密容器、文件仓储与附件存储
├── domain/                                # 领域模型与本地设置
├── presentation/                          # Flutter 根组件、页面、对话框与组件
├── services/                              # 平台服务（如桌面小组件）
└── sync/                                  # 同步协调器、凭据与四种同步后端
    ├── directory_sync_provider.dart       # 本地目录同步
    ├── webdav_sync_provider.dart          # WebDAV 同步
    ├── self_hosted_api_sync_provider.dart # 自建 HTTP API 同步
    └── s3_sync_provider.dart              # S3 兼容存储同步
```

## 许可证

Cardory 采用**双许可**（Dual License）模式发布：

- **开源版**：以 [GPL-3.0](LICENSE) 发布。任何人都可以自由使用、修改和分发，但**衍生作品必须同样以 GPL-3.0 开源**（Copyleft）。
- **商业版**：如果你的使用场景无法满足 GPL-3.0 的要求（例如需要在闭源产品中集成、需要商业授权或技术支持），请联系作者获取商业许可。

如有商业授权需求，请在 [GitHub 仓库](https://github.com/u1s3-fu/cardory) 提交 Issue 或直接联系作者。
