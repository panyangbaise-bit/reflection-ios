# 复盘了（Portfolio Agent）iOS

原生 SwiftUI 投资组合复盘客户端。用户可以记录持仓与交易、查看复盘报告、维护交易纪律，并通过 Ask 面板围绕组合提问。仓库同时包含可离线运行的本地演示和可选的云端账户模式。

本仓库为开源版本：

- 不包含运营商号码认证、短信登录或任何第三方认证 SDK。
- 不包含订阅、内购、付费墙或权益等级；应用内功能均可免费使用。
- 不包含真实服务器地址、账号、密钥或个人部署信息。
- 服务端地址通过构建配置提供，默认是占位地址 `https://api.example.com`。

## 环境

- Xcode 27 或更新版本
- iOS 17 及以上
- Swift 6 工具链；核心模型使用 Swift Package Manager 测试
- 无外部 Swift 包或二进制依赖

## 配置 API 地址

客户端从 Info.plist 的 `APIOrigin` 键读取 API 根地址，该键由 `API_ORIGIN` 构建配置注入。

默认值在 `PortfolioAgent.xcodeproj` 的 Debug / Release 构建配置中：

```text
API_ORIGIN = https://api.example.com
```

接入自己的后端时，任选一种方式：

1. 在 Xcode 的 Target → Build Settings 中修改 `API_ORIGIN`；
2. 在命令行覆盖，例如：

   ```sh
   xcodebuild ... API_ORIGIN=https://api.your-domain.example
   ```

约束：

- 正式环境必须使用 HTTPS，且地址不能包含路径、查询参数或账号信息。
- 仅 Debug 构建允许本机开发地址：`http://127.0.0.1:8000`、`http://localhost:8000` 或 `http://[::1]:8000`。其他端口或主机名会被拒绝。
- 如果配置缺失，客户端回退到编译期占位值 `https://api.example.com`，不会连接任何真实服务。

## 构建

```sh
xcodebuild -project PortfolioAgent.xcodeproj -scheme PortfolioAgent \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData build
```

在 Xcode 中直接运行时请使用正常签名（模拟器可用 ad-hoc）。钥匙串会话需要签名 entitlement；完全关闭代码签名的构建可以编译，但登录状态可能无法保存。

## 测试

```sh
swift test --package-path .
```

核心测试不要求启动模拟器或后端。真实服务联调用例默认跳过；如需运行，将包含 `origin`、`access_token`、`refresh_token` 的 JSON 会话文件路径放入环境变量：

```sh
PA_IOS_TEST_SESSION=/absolute/path/session.json swift test
```

## 功能

- 总览：交易纪律、最新复盘 / 持仓动态、资产与持仓卡片，板块顺序可调整。
- 持仓：搜索标的、创建初始持仓、记录买入 / 卖出、核心仓 / 卫星仓分类、交易记录与历史日线。
- 复盘：日报 / 周报列表、报告快照与依据、报告内追问、新闻动态。
- Ask：独立全屏对话、推荐问题、历史会话恢复、报告上下文追问。
- 设置：账户与数据管理、显示偏好、通知与复盘提醒、AI 授权与隐私、数据导出与账户删除。
- 本地演示：无网络也可体验；数据保存在 App 沙盒的 JSON 文件中。
- 云端模式：手机号 + 密码登录，服务端账本、报告、对话和偏好。

## 代码结构

- `PortfolioAgent/MobileAPI.swift`：API 地址校验、HTTP 客户端、会话与 DTO。
- `PortfolioAgent/CloudStore.swift`：云端状态、钥匙串会话、登录 / 刷新 / 登出。
- `PortfolioAgent/CloudViews.swift`、`CloudProductViews.swift`、`CloudChatView.swift`：云端页面与对话状态机。
- `PortfolioAgent/Models.swift`、`AppStore.swift`：本地模型、账本规则与状态管理。
- `PortfolioAgent/ContentView.swift`、`OverviewViews.swift`、`HoldingsViews.swift`、`ReviewViews.swift`、`SettingsViews.swift`：主要界面。
- `Tests/`：SPM 测试。

云端接入细节见 [CLOUD-INTEGRATION.md](CLOUD-INTEGRATION.md)，部署与签名说明见 [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)。

## 数据与安全

- 云端登录凭据保存在系统钥匙串中，仅限本设备使用。
- 服务端返回的金额使用十进制字符串，客户端使用 `Decimal` 展示，不经过 `Double` 重新记账。
- 行情可能延迟或缺失；复盘与 Ask 回答可能出错，不构成投资建议。
- 本地演示不会自动上传数据。云端账户可在设置中导出或删除。

## 许可证

[MIT](LICENSE)。
