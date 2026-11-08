# 云端接入说明

客户端包含两种运行模式：

- 未登录时为本地演示，数据保存在设备沙盒中，不访问网络。
- 登录后切换到云端账户，持仓、交易、复盘、对话、纪律和偏好由服务端保存。

本地演示与云端账户相互独立，不会自动迁移或上传本地数据。

## API 地址

所有请求使用 `APIOrigin` 配置的根地址，接口路径固定为：

```text
/api/mobile/v1/
```

地址来源与校验规则：

- `API_ORIGIN` 构建配置 → Info.plist `APIOrigin` → 客户端 `APIOrigin.configured`。
- 仓库默认占位值：`https://api.example.com`。
- 正式环境必须为 HTTPS，不能包含路径、查询参数、用户信息或 fragment。
- Debug 构建允许本机开发地址 `http://127.0.0.1:8000`、`http://localhost:8000` 或 `http://[::1]:8000`；Release 构建拒绝 HTTP。
- 客户端不会自动跟随重定向。

## 登录与会话

登录方式为手机号 + 密码：

```text
POST /api/mobile/v1/auth/password/login
{ "phone": "...", "password": "...", "agreements_accepted": true }
```

返回 `access_token` 与 `refresh_token`。客户端将会话保存在系统钥匙串中，并在之后的请求中发送 `Authorization: Bearer <access_token>`。

其他认证接口：

- `POST auth/refresh`：刷新令牌。多个并发 401 只触发一次刷新。
- `POST auth/logout`：服务端撤销成功后，客户端才清除本机会话。
- `POST auth/deletion-status`：使用删除回执查询进度。

本仓库不包含短信验证码、运营商号码认证或第三方登录 SDK。服务端如需其他登录方式，应提供独立接口，并保持客户端只处理服务端返回的令牌。

## 主要接口

| 能力 | 接口 |
| --- | --- |
| 当前用户 | `GET me` |
| 首页聚合 | `GET home` |
| 账户 | `GET/POST accounts` |
| 标的搜索 | `GET instruments?query=...` |
| 持仓快照 | `GET portfolio/snapshot` |
| 初始持仓 | `POST opening-positions` |
| 买卖记录 | `POST ledger-events` |
| 交易记录 | `GET ledger-events` |
| 报告列表 / 详情 | `GET feed`、`GET reports/{id}` |
| 报告已读 / 追问 | `POST reports/{id}/read`、`POST reports/{id}/questions` |
| 对话 | `GET/POST conversations`、`GET conversations/{id}/messages` |
| 异步任务 | `GET runs/{id}`、`GET conversations/{id}/active-run` |
| 交易纪律 | `GET/PUT me/discipline` |
| 报告偏好 | `GET/PATCH me/preferences` |
| 总览布局 | `PUT me/layout` |
| 监察表 | `GET/PUT/DELETE watchlist` |
| 历史日线 | `GET instruments/{id}/kline` |
| AI 授权 | `GET me/privacy`、`PUT me/consents/{purpose}` |
| 数据导出 | `GET me/export?section=...` |
| 账户删除 | `POST me/deletion-requests` |
| 设备推送偏好 | `PATCH me/preferences` |

金额、数量、价格和净值在协议中使用十进制字符串。服务端负责估值和账本；客户端不把缺失行情当作 0，也不使用 `Double` 重新计算账本。

## 开发与本机联调

Debug 构建可以使用本机后端：

1. 启动后端并监听 `http://127.0.0.1:8000`。
2. 以 `API_ORIGIN=http://127.0.0.1:8000` 构建，或在 Xcode Build Settings 中临时修改。
3. 使用手机号 + 密码登录。

模拟器还支持导入一次性调试会话（仅 DEBUG）：

- 将包含 `origin`、`tokens.accessToken`、`tokens.refreshToken` 的 JSON 放到 App 容器的 `Library/Application Support/beta-session.json`。
- 使用 `--beta-cloud-only` 启动参数。
- App 导入一次后会删除该文件；会话只允许来自配置的 API 地址或本机 8000 端口。

真实服务联调测试通过环境变量提供会话文件：

```sh
PA_IOS_TEST_SESSION=/absolute/path/session.json swift test
```

未提供时，3 个真实服务测试会跳过；其余测试不依赖后端。

## 安全边界

- 登录凭据仅保存在系统钥匙串，标记为 `ThisDeviceOnly`。
- 服务地址在进入网络层前校验；重定向被禁用。
- 写操作携带幂等键；认证失败重试时复用同一键。
- 刷新失败或结果不确定时清除本地令牌，不重放旧 refresh token。
- 账户删除受理后立即清除本机会话，并使用单独保存的删除回执查询进度。
- 导出文件写入临时目录，离开页面后删除。

## 服务端兼容性

客户端对新增 JSON 字段保持宽容，会忽略不认识的键。服务端移除字段时应先确认客户端版本；`APIHome` 等聚合 DTO 中仍可能包含历史权益字段，客户端不再将其用于界面展示。
