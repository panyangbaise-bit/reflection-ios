# 构建与部署

这份说明只描述通用流程；实际 Bundle ID、签名团队、服务器地址和发布渠道由使用者自行配置，仓库中不包含这些私有信息。

## 1. 准备配置

1. 在 Xcode 中打开 `PortfolioAgent.xcodeproj`。
2. 在 Target → Signing & Capabilities 选择自己的开发团队，并保持自动签名。
3. 在 Build Settings 中设置 `API_ORIGIN` 为自己的 HTTPS 服务地址。
4. 如使用推送，确认 `Config/PortfolioAgent.entitlements` 中的 `aps-environment` 与构建配置一致。
5. 如需修改 Bundle ID，同时更新服务端允许的客户端标识。

`API_ORIGIN` 会被写入 Info.plist 的 `APIOrigin`。未设置时使用占位地址 `https://api.example.com`，App 不会连接真实服务。

## 2. 模拟器构建

```sh
xcodebuild -project PortfolioAgent.xcodeproj -scheme PortfolioAgent \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData build
```

请使用正常签名（模拟器可用 ad-hoc）。完全关闭签名会导致钥匙串访问失败，无法验证登录流程。

## 3. 归档与分发

1. 选择真机目标或 `Any iOS Device (arm64)`。
2. Product → Archive。
3. 在 Organizer 中选择分发方式：内部测试使用 TestFlight，公开分发使用 App Store Connect。
4. 每次上传前递增 `CURRENT_PROJECT_VERSION`，不要重复使用已处理的构建号。
5. 按实际数据收集行为填写隐私声明与出口合规信息。

## 4. 发布前检查

- `API_ORIGIN` 为 HTTPS，且不包含占位域名或本机地址。
- 服务端已部署与客户端版本匹配的 `/api/mobile/v1` 接口。
- 登录、刷新、退出和账户删除在真实网络上验证通过。
- 未在仓库、构建配置或提交历史中留下密钥、真实账号或个人部署信息。
- `swift test --package-path .` 全部通过（真实服务用例可跳过）。

## 5. 本地开发

仅 Debug 构建允许 loopback HTTP：

```sh
xcodebuild -project PortfolioAgent.xcodeproj -scheme PortfolioAgent \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath DerivedData \
  API_ORIGIN=http://127.0.0.1:8000 build
```

Release 构建会拒绝任何 HTTP 地址。
