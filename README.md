# 板记 Cardory

Cardory 是一个以**项目看板、进度记录和待办管理**为核心的 Flutter 本地优先跨平台应用。所有数据保存于本机 AES-256-GCM 加密保险库中，无需联网即可使用。

![Version](https://img.shields.io/badge/version-0.0.2-blue) ![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter) ![Dart](https://img.shields.io/badge/Dart-3.9.2-0175C2?logo=dart) ![License](https://img.shields.io/badge/license-private-red)

---

## 软件作用

### 项目管理

- **项目看板**：创建、编辑、删除项目，直观总览所有项目及其状态
- **阶段管理**：支持四级阶段流转 —— 计划中 → 推进中 → 待验收 → 已完成
- **优先级划分**：P0（紧急）/ P1（高）/ P2（中）/ P3（低），颜色编码一目了然
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
- **预设色板**：提供 6 种精心设计的预设主题色组合，一键切换
- **自动暗色模式**：当选择深色背景时，文字与控件自动切换为亮色，无需手动配置

### 数据同步

- **目录同步**：将加密数据文件放置于任意本地目录或网盘同步目录中
- **WebDAV 同步**：连接 WebDAV 服务器（如 NextCloud、群晖 NAS 等）
- **自建服务**：通过 HTTP API 对接私有同步服务
- **冲突检测**：基于 SHA-256 哈希 + 修订版本号的冲突检测机制，防止数据覆盖

---

## 数据安全

Cardory 将安全放在首位，所有用户数据在写入磁盘前均经过加密处理。

### 加密方案

- **数据正文**：使用 **AES-256-GCM** 认证加密，同时提供机密性与完整性保护
- **密钥体系**：随机生成 256 位数据密钥（DEK），分别由密码密钥（KEK）和恢复密钥保护
- **密钥派生**：密码通过 **PBKDF2-HMAC-SHA256** 派生加密密钥，默认迭代 **210,000 次**，有效抵御暴力破解
- **双密钥槽**：主密码 + 恢复码两套独立加密槽，任一方式均可解锁；忘记密码时可通过恢复码取回数据

### 数据保护机制

- **自动锁定**：应用切换至后台时可自动锁定保险箱（可配置开关），防止未经授权访问
- **原子写入**：每次覆盖保存前生成 `.bak` 自动备份；使用临时文件写入，完成完整性校验后再替换正式文件
- **损坏恢复**：数据文件损坏时自动尝试从 `.bak` 备份恢复
- **安全存储**：密码与 Token 使用平台原生安全机制存储（iOS Keychain / Android Keystore / Windows DPAPI）

---

## 架构设计

### 总体架构：Clean Architecture 分层

项目遵循 Clean Architecture 原则，分为五层，依赖方向从外向内：

```
┌─────────────────────────────────────────────┐
│              Presentation 展示层              │
│  (主题 / 颜色 / Logo 组件)                     │
├─────────────────────────────────────────────┤
│              Application 应用层               │
│  (业务用例：自动锁定等)                         │
├─────────────────────────────────────────────┤
│               Domain 领域层                   │
│  (CardoryData / ProjectData / TodoData 等)    │
├─────────────────────────────────────────────┤
│                Data 数据层                    │
│  (加密容器编解码 / CardoryStore 仓库)            │
├─────────────────────────────────────────────┤
│                Sync 同步层                    │
│  (SyncProvider 抽象 / WebDAV / 目录 / 自建)    │
└─────────────────────────────────────────────┘
```

### 模块说明

| 模块 | 目录 | 职责 |
|------|------|------|
| **入口** | `lib/main.dart` | 应用启动、页面路由、所有 UI 组件 |
| **应用层** | `lib/application/` | 业务用例编排，如保险箱自动锁定控制器 |
| **领域层** | `lib/domain/` | 核心业务模型：`CardoryData`、`ProjectData`、`TodoData`、`AssetData`、`AppSettings` |
| **数据层** | `lib/data/` | AES-256-GCM 加密容器编解码、基于文件的仓库实现 (`CardoryStore`) |
| **展示层** | `lib/presentation/` | 设计系统（CardoryTheme）、品牌 Logo、阶段/优先级颜色映射 |
| **同步层** | `lib/sync/` | 同步提供者抽象接口 (`SyncProvider`) 及三种实现 |

### 关键设计模式

- **仓储模式**：`CardoryRepository` 抽象接口定义 14 个数据操作方法，`CardoryStore` 提供基于文件的实现
- **策略模式**：`SyncProvider` 抽象接口，三种同步后端（目录 / WebDAV / 自建 HTTP API）各自实现
- **门面模式**：`CardoryVaultGate` 作为统一入口，管理解锁、密码设置、恢复码、备份恢复等全生命周期
- **凭证分离**：`VaultCredentialStore` 与 `SyncCredentialStore` 分离保险库凭证与同步凭证的管理

### 数据流

```
用户操作 → StatefulWidget.setState()
               ↓
         CardoryRepository（抽象接口）
               ↓
         CardoryStore（文件实现）
               ↓
         CardoryContainerCodec（AES-256-GCM 编解码）
               ↓
         加密数据文件（.cardory）
```

### 状态管理

项目不依赖第三方状态管理库（如 Provider、Riverpod、Bloc 等），使用 Flutter 内置的 **StatefulWidget + setState** 进行状态管理。页面导航通过 `AppSection` 枚举 + `switch` 控制，数据通过构造函数和回调向下传递。设计上保持简洁，适合当前应用规模。

---

## 运行环境

### 平台要求

| 平台 | 最低版本 | 备注 |
|------|----------|------|
| **Windows** | Windows 10+ | 完整支持，推荐使用 |
| **Android** | Android 5.0 (API 21) | 完整支持 |
| **iOS** | iOS 12+ | 完整工程结构 |
| **macOS** | macOS 10.14+ | 沙盒已启用网络权限 |

### 开发环境

| 组件 | 版本 |
|------|------|
| **Flutter SDK** | stable（最新稳定版） |
| **Dart SDK** | `3.9.2` |
| **Kotlin** | JVM 11（Android） |
| **Swift** | 5.x（iOS/macOS） |

### 核心依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `path_provider` | `2.1.5` | 获取应用文档目录 |
| `cryptography` | `2.9.0` | AES-256-GCM 加密与 PBKDF2 密钥派生 |
| `http` | `1.6.0` | HTTP 客户端（同步服务） |
| `flutter_secure_storage` | `10.3.1` | 平台原生安全存储 |
| `file_picker` | `10.3.0` | 文件选择（备份导入/导出） |
| `path` | `1.9.1` | 路径操作 |

### 开发依赖

| 依赖 | 版本 | 用途 |
|------|------|------|
| `flutter_lints` | `5.0.0` | 代码规范检查 |
| `flutter_launcher_icons` | `0.14.4` | 自动生成多平台应用图标 |

---

## 数据文件

默认数据文件位于系统应用文档目录的 `Cardory/cardory-data.cardory`，支持自定义路径。

- 每次覆盖保存前会生成 `cardory-data.cardory.bak` 自动备份
- 写入过程使用同目录临时文件，完成格式与完整性检查后再替换正式文件
- 密码修改和恢复码轮换走相同的**串行原子写入**流程
- 数据损坏时自动尝试从 `.bak` 备份恢复

> **注意**：自定义路径适合放置于个人同步目录（如 iCloud、OneDrive 等），但当前**不支持多设备同时编辑**。多个实例同时修改同一文件可能产生业务冲突。

---

## 平台网络权限

同步功能（WebDAV / 自建服务）需要平台出站网络权限：

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
flutter build ios --release         # iOS
flutter build macos --release       # macOS
```

## 应用图标

应用图标源文件位于 `assets/branding/app_icon_source.png`（1024×1024），通过 `flutter_launcher_icons` 自动生成各平台图标。Windows 图标由 `tools/gen_win_icon.ps1` 脚本生成多尺寸标准 ICO 文件。

## 目录结构

```
lib/
├── main.dart                              # 应用入口与所有页面 UI
├── application/                           # 应用层（业务用例）
│   └── vault_auto_lock_controller.dart    # 保险箱自动锁定
├── data/                                  # 数据层（持久化）
│   ├── cardory_container_codec.dart       # AES-256-GCM 加密容器编解码
│   └── cardory_store.dart                 # 文件系统仓库实现
├── domain/                                # 领域模型层
│   ├── cardory_container.dart             # 加密容器数据结构
│   └── cardory_models.dart                # 核心业务模型
├── presentation/                          # 展示层
│   ├── cardory_logo.dart                  # 品牌 Logo 组件
│   ├── cardory_theme.dart                 # 设计系统 / 主题
│   └── model_colors.dart                  # 阶段 / 优先级颜色映射
└── sync/                                  # 同步模块
    ├── sync_provider.dart                 # 同步提供者抽象接口
    ├── sync_models.dart                   # 同步状态 / 文档模型
    ├── sync_credentials.dart              # 凭证安全存储
    ├── sync_coordinator.dart              # 同步协调器
    ├── directory_sync_provider.dart        # 本地目录同步
    ├── webdav_sync_provider.dart          # WebDAV 同步
    └── self_hosted_api_sync_provider.dart  # 自建服务同步
```

## 许可证

私有项目，未公开发布。
