# 板记 Cardory

Cardory 是一个以**项目看板、进度记录和待办管理**为核心的 Flutter 本地优先跨平台应用。保险库正文和附件在写入磁盘前均经过加密：数据运行于 **SQLCipher 整库加密的 SQLite 数据库**，附件按文件独立加密保存。无需联网即可使用。

![Version](https://img.shields.io/badge/version-0.1.0--beta.1-blue) ![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter) ![Dart](https://img.shields.io/badge/Dart-3.12.2-0175C2?logo=dart) ![License](https://img.shields.io/badge/license-GPLv3-blue)

> ⚠️ **破坏性数据不兼容**：`0.1.0-beta.1` 起，数据运行时由 AES `.cardory` 加密容器切换为 SQLCipher 加密数据库。旧版本（≤ 0.0.7）的数据文件**不会被读取或自动迁移**，升级前请先在旧版本中自行备份数据与附件。

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

- **目录同步**：将加密快照文件放置于任意本地目录或网盘同步目录中
- **WebDAV 同步**：连接 WebDAV 服务器（如 NextCloud、群晖 NAS 等）
- **自建服务**：通过 HTTP API 对接私有同步服务
- **S3 兼容存储**：连接 AWS S3、MinIO、Cloudflare R2 等支持 S3 API 的存储服务
- **冲突检测**：数据库快照同步基于 SHA-256 摘要与修订版本（ETag/If-Match）做完整性校验，冲突时保留远端暂存副本并提示手动处理，防止过期快照覆盖新数据

---

## 数据安全

Cardory 将安全放在首位；数据运行时是 SQLCipher 整库加密数据库，附件单独加密保存，应用不保存任何明文业务数据文件。

### 加密方案

- **整库加密**：数据文件使用 **SQLCipher**（SQLite 的 AES-256 全库加密实现）加密，任何时刻数据库中都不存在明文业务表
- **密钥生命周期**：保险库密码即数据库密钥源。应用仅在解锁会话期间于内存中持有打开后的数据库句柄，**锁定/退出即关闭连接并清除内存密钥**，密钥不落盘
- **自动解锁**：密码经平台原生安全存储（iOS Keychain / Android Keystore / Windows DPAPI）保存时，仅用于解锁会话的自动填充；密码错误即清除已保存凭据并回落手动输入
- **凭据隔离**：保险库密码与同步凭据分属不同的安全存储键，应用日志与云端对象不包含任何密码、Token 或敏感列明文

### 数据保护机制

- **自动锁定**：应用切换至后台时可自动锁定保险箱（可配置开关），锁定时按 fail-closed 顺序停止会话、关闭数据库、清除已保存凭据与小组件摘要
- **原子写入**：保险库创建、改密、恢复均以临时文件 + 原子替换完成；每次替换前自动生成 `.bak` 副本，损坏时回退
- **快照导出**：同步与备份使用 `VACUUM INTO` 从当前库生成加密快照临时文件，校验通过后才上传或替换，运行中的数据库文件本身永不上传
- **独立附件加密**：附件按 1 MiB 分块使用 AES-256-GCM 独立加密并登记存储键，主数据库只保存文件元数据
- **流式附件传输**：附件选择、加密、同步和导出均采用流式读写，Cardory 不设置单文件或项目附件总容量上限
- **云端附件清单**：同步成功后重写 `attachments/manifest.json`，记录快照引用附件的权威枚举，供新设备恢复时逐文件校验与补齐

---

## 架构设计

### 模块边界

项目按领域模型、应用用例、持久化、同步与展示模块组织。应用层通过仓储等端口依赖具体实现；`CardoryApp` 是 Flutter 根组件兼组合根，负责创建保险库会话、解锁状态与路由门禁。

```
┌─────────────────────────────────────────────┐
│              Presentation 展示层             │
│  (根组件 / 页面 / 门禁 / 对话框 / Widgets)   │
├─────────────────────────────────────────────┤
│              Application 应用层              │
│  (工作区控制 / 设置 / 同步 / 附件用例)        │
├─────────────────────────────────────────────┤
│               Domain 领域层                  │
│  (ProjectData / TodoData / AssetData 等)     │
├─────────────────────────────────────────────┤
│      Infrastructure 基础设施层               │
│  (SQLCipher 数据库 / Repository / Sync)      │
└─────────────────────────────────────────────┘
```

### 模块说明

| 模块 | 目录 | 职责 |
|------|------|------|
| **入口** | `lib/main.dart` | 调用 `runCardoryApp()` 启动 Flutter 应用 |
| **应用层** | `lib/application/` | 工作区会话、同步与附件用例、设置读写端口 |
| **领域层** | `lib/domain/` | 核心业务模型：`ProjectData`、`TodoData`、`AssetData` 等 |
| **数据层** | `lib/data/` | SQLCipher 数据库（drift）、Repository 族、附件加密存储、运行时保险库服务 |
| **展示层** | `lib/presentation/` | 组合根（`CardoryApp`）、页面、门禁、对话框与复用组件 |
| **状态层** | `lib/providers/` | Riverpod session-scoped Provider 组装与销毁 |
| **路由层** | `lib/routing/` | go_router 业务路由与解锁门禁 redirect |
| **同步层** | `lib/sync/` | `SyncProvider`、协调器与目录、WebDAV、自建 API、S3 后端 |
| **平台服务** | `lib/services/` | 原生桌面小组件、更新检查等平台适配器 |

### 关键设计模式

- **仓储模式**：Repository 族（项目 / 任务 / 资产 / 附件 / 时间记录 / 番茄钟 / 依赖 / 同步变更 / 设置）承载全部数据库写路径，每次业务写入都在同一 drift 事务内完成实体更新 + 时间戳 + tombstone + `sync_changes` 审计
- **策略模式**：`SyncProvider` 抽象接口，目录、WebDAV、自建 HTTP API 与 S3 兼容存储各自实现
- **会话门禁**：数据库会话（`DatabaseSession`）在保险库解锁后建立、锁定/退出时关闭；`go_router` redirect 依据解锁状态控制页面可达性，未解锁仅能访问 `/vault`
- **凭证分离**：`VaultCredentialStore` 与 `SyncCredentialStore` 分离保险库密码与同步凭据的管理与安全存储

### 数据流

```
UI 写入口 → WorkspaceController → Repository 单事务写入 SQLCipher
                ↓ 提交后
        数据库回读 → 投影缓存 → 通知 UI（drift Stream / Provider）
                ↓ 异步
       VACUUM INTO 生成加密快照 + 附件/备份 manifest → 同步后端
```

### 状态管理

应用使用 **Riverpod（flutter_riverpod）+ go_router** 组织运行时状态与导航。数据库会话与 Repository 由 `CardoryApp` 在解锁时建立、以 session-scoped Provider 注入；查询由数据库流驱动，命令只负责事务写入；`WorkspaceController` 保留为工作区投影缓存与既有页面写入口的过渡层，不再承担独立事实源。

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
| **Flutter SDK** | `3.44.9`（stable） |
| **Dart SDK** | `3.12.2`（约束 `3.12.0`） |
| **Java / Kotlin** | JVM 21（Android） |
| **Swift** | 5.x（iOS/macOS） |

### 核心依赖

下表列出 `pubspec.yaml` 中的声明版本约束；实际解析版本以 `pubspec.lock` 为准。

| 依赖 | 版本 | 用途 |
|------|------|------|
| `path_provider` | `^2.1.5` | 获取应用文档目录 |
| `drift` | `^2.34.4` | SQLite 响应式 ORM（表结构 / 查询 / 事务） |
| `sqlite3` | `^3.5.2` | 原生 SQLite 绑定（`hooks` 指向 SQLCipher 源码构建） |
| `flutter_riverpod` | `^3.4.3` | session-scoped 状态管理与依赖注入 |
| `go_router` | `^18.0.1` | 声明式路由与解锁门禁 redirect |
| `uuid` | `^4.6.0` | 跨设备同步 ID 生成 |
| `flutter_secure_storage` | `^10.3.1` | 平台原生安全存储（密码 / Token） |
| `cryptography` | `^2.9.0` | 附件 AES-256-GCM 加密与摘要校验 |
| `http` | `^1.6.0` | HTTP 客户端（自建服务同步） |
| `crypto` | `^3.0.7` | S3 请求摘要与签名辅助 |
| `webdav_client` | `^1.2.2` | WebDAV 兼容性支持 |
| `package_info_plus` | `^10.2.1` | 本地版本读取（更新检查） |
| `url_launcher` | `^6.3.2` | 打开更新页 / 仓库链接 |
| `file_picker` | `^12.2.0` | 系统文件选择（附件导入等） |
| `path` | `^1.9.1` | 路径操作 |
| `home_widget` | `^0.9.4` | Android / iOS 桌面小组件数据桥接 |

### 开发依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `build_runner` | `^2.10.4` | 代码生成驱动 |
| `drift_dev` | `^2.34.4` | drift 表代码生成 |
| `flutter_lints` | `^5.0.0` | 代码规范检查 |
| `flutter_launcher_icons` | `^0.14.4` | 自动生成多平台应用图标 |

---

## 数据文件

默认数据位于系统应用文档目录的 `Cardory/` 下：

- `cardory-runtime-v1.db` —— SQLCipher 加密的运行时数据库（唯一本地事实源），应用设置存入其中 `settings` 表
- `cardory-runtime-v1.db.bak` —— 保险库改密 / 恢复前自动生成的备份副本
- `attachments/v1/` —— 按文件独立加密的附件密文

> 云同步对象与上述本地文件不同：数据同步上传**加密数据库快照** `cardory-snapshot-v2.db`（本地运行库的 `VACUUM INTO` 副本），配置同步对象为 `cardory-config-v2.json`，附件目录对应远端 `attachments/v1/`，并维护 `attachments/manifest.json` 附件清单。运行中的数据库文件（含 WAL 等附属文件）永不直接上传。

> 进行离线整机备份时，请先退出应用再复制 `cardory-runtime-v1.db` 与 `attachments/v1/` 目录；或借助云同步 / 云端恢复链路保留加密快照与附件密文。旧版本 `.cardory` 数据文件不受支持，也不会被读取。

> **注意**：主保险库路径由应用管理；同步目录路径可在设置中配置为个人同步目录（如 OneDrive）。当前**不支持多设备同时编辑**，多个实例同时同步同一快照可能产生冲突，冲突以保留远端暂存副本的方式呈现并需手动解决。

---

## 平台网络权限

同步功能（WebDAV / 自建服务 / S3 兼容存储）与更新检查需要平台出站网络权限：

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
├── application/                           # 应用用例与端口（工作区会话等）
├── data/                                  # SQLCipher 数据库、仓储、附件存储、运行时服务
│   ├── db/                                # drift 表定义与数据库会话（app_database.dart）
│   ├── repositories/                      # Repository 族（单事务写入）
│   └── runtime/                           # 保险库运行服务、快照应用、数据映射
├── domain/                                # 领域模型与端口
├── presentation/                          # Flutter 根组件、页面、门禁、对话框与组件
├── providers/                             # Riverpod session-scoped Provider
├── routing/                               # go_router 业务路由与门禁
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
