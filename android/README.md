# Android 平台配置

本目录包含 Cardory Android 应用的平台原生配置与资源。

- `app/`：应用模块，包含 `build.gradle.kts`、签名配置、Java/Kotlin 入口和图标资源。
- `gradle/`：Gradle Wrapper 文件。
- `build.gradle.kts` / `settings.gradle.kts`：项目级 Gradle 构建脚本。
- `key.properties`：发布签名密钥别名与路径配置（本地文件，不上传）。

图标与启动配置通常由 `flutter_launcher_icons` 等工具根据 `assets/branding/app_icon_source.png` 自动生成。
