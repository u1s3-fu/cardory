# iOS 桌面小组件配置指南

## 前置条件
- macOS 14+（需要 Xcode 16+ 进行 WidgetKit 开发）
- iOS 14+ 设备或模拟器

## 配置步骤

### 1. 在 Xcode 中添加 Widget Extension 目标

1. 用 Xcode 打开 `ios/Runner.xcworkspace`
2. 菜单栏选择 **File → New → Target...**
3. 选择 **Widget Extension**，点击 Next
4. **Product Name** 填入 `CardoryWidget`
5. 确保 **Embed in Application** 选择 `Runner`
6. 点击 **Finish**，当提示 "Activate scheme" 时点 **Activate**
7. 删除 Xcode 自动生成的 Swift 文件（它们将被我们的源文件替换）

### 2. 将源文件加入编译目标

在 Xcode 项目导航器中：
1. 展开 `ios/CardoryWidget/` 目录
2. 将以下文件加入 `CardoryWidget` target（选中文件 → 右侧 File Inspector → Target Membership → 勾选 CardoryWidget）：
   - `CardoryWidget.swift`
   - `CardoryWidgetBundle.swift`
   - `Info.plist`

### 3. 配置 App Group（共享数据）

1. 选择 **Runner** target → **Signing & Capabilities** → **+ Capability** → 添加 **App Groups**
2. 添加一个 App Group，例如：`group.com.cardoryapp.widget`
3. 选择 **CardoryWidget** target → **Signing & Capabilities** → **+ Capability** → 添加 **App Groups**
4. 添加**相同的** App Group：`group.com.cardoryapp.widget`

### 4. 更新 Bundle Identifier

确保 `CardoryWidget` extension 的 Bundle Identifier 格式为：
`<Runner的Bundle ID>.CardoryWidget`

例如：如果你的 Runner bundle ID 是 `com.yourcompany.cardory`，则 Widget 的应为 `com.yourcompany.cardory.CardoryWidget`

### 5. 验证 App Group 在代码中的使用

`CardoryWidget.swift` 中使用了 `UserDefaults(suiteName: "group.com.cardoryapp.widget")`，
确保与第 3 步中添加的 App Group 名称一致。如果不一致，请修改代码中的字符串匹配。

### 6. 构建并运行

1. 选择 **Runner** scheme（不是 CardoryWidget）
2. 选择目标设备（iOS 14+ 真机或模拟器）
3. **Product → Run**（⌘R）
4. 应用启动后，添加一些待办事项，然后关闭应用
5. 长按主屏幕 → 添加小组件 → 搜索 "Cardory" → 添加待办小组件
6. 小组件应显示待办列表

### 故障排除

**小组件显示"暂无数据"**：
- 确保 App Group 名称在代码和 Xcode 配置中一致
- 确保两个 target 都启用了相同的 App Group
- 尝试先打开主应用触发一次数据保存，再查看小组件

**小组件不更新**：
- 小组件每 30 分钟自动刷新一次
- 打开主应用进行任何待办操作（新增/编辑/删除）都会立即触发更新

**编译错误**：
- 确保 iOS Deployment Target ≥ 14.0（WidgetKit 要求）
- 确保 Swift 文件已正确加入 CardoryWidget target
