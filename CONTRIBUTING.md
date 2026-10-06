# 开发文档（CONTRIBUTING）

本文档面向参与开发或想了解内部实现的开发者，收录开发环境、架构设计与代码组织说明。产品功能、安全机制与下载安装见 [README.md](README.md)。

## 开发环境

| 组件 | 版本 |
|------|------|
| **Flutter SDK** | `3.47.4`（stable，CI 已固定该版本） |
| **Dart SDK** | `3.13.3`（约束 `3.12.0`） |
| **Java / Kotlin** | JVM 21（Android） |
| **Swift** | 5.x（iOS/macOS） |

环境搭建与构建命令见下文「快速开始」与「发布检查」。

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

## 应用图标

应用图标源文件位于 `assets/branding/app_icon_source.png`（1024×1024），通过 `flutter_launcher_icons` 自动生成各平台图标。Windows 图标由 `tools/gen_win_icon.ps1` 脚本生成多尺寸标准 ICO 文件。
