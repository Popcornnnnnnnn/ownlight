# 网络接入配置

当前 Ownlight 的日常产品路径是 iPhone 本地 SQLite + 可选 iCloud/CloudKit。开启 `iCloud Sync` 不需要用户配置 Server URL、Tailscale、Cloudflare Tunnel 或自建账号；App 使用当前 Apple Account 的 CloudKit private database。

本文件只保留两类网络说明：

- legacy server/admin 的历史兼容和维护路径。
- local transcription gateway 这类用户自管 AI helper 的可选接入路径。

不要把下面的 legacy/private endpoint 配置写成 App Store 首发的前置条件。

## 当前推荐路径

### 1. iOS 本地与 iCloud

日常开发和验证优先使用：

```bash
npm run verify:ios:low-impact
npm run ios:device
```

真机上的 iCloud 同步通过 Settings > Data Storage > iCloud 开关控制。CloudKit account、container、entitlement 和 signing 由 Apple Developer / Xcode 配置，不通过本文件里的 URL 配置。

### 2. 本地转写 Gateway

如果用户选择 Local Gateway 作为 transcription provider，iPhone 需要能访问 gateway endpoint。这个 endpoint 可以来自 LAN、Tailscale/private VPN、Cloudflare Tunnel、反向代理或其他受保护 HTTPS 入口。

公开仓库不会内置任何 tailnet 名称、个人 IP、域名、token 或设备名。个人值应放在 ignored `.env.local` 或本机配置中。

### 3. Legacy Server/Admin

仓库仍保留 `server/` 和 `admin/`，用于历史兼容、API reference、archive/diagnostics 和低频维护。它们不参与当前 iCloud 同步。

本地启动 legacy server：

```bash
cp server/.env.example server/.env
npm run server:prisma:generate
npm run server:prisma:deploy
npm run server:build
npm run server:dev
```

本机地址：

```text
http://127.0.0.1:3210
```

如果维护 legacy iPhone-to-server path，真实 iPhone 不能访问 Mac 的 `127.0.0.1`。你需要给 iPhone 一个能连到 legacy server 的受保护地址：

- 同一局域网：`http://<mac-lan-ip>:3210`
- Tailscale 或其他私有 VPN：`https://<your-private-host>` 或 `http://<private-ip>:3210`
- 其他自管 HTTPS 入口：你自己维护的受保护 endpoint

如果使用明文 HTTP，legacy server 需要监听非 localhost 地址：

```env
HOST=0.0.0.0
PORT=3210
```

真实 iPhone 访问 LAN/Tailscale/Cloudflare endpoint 时应优先使用 HTTPS，避免 legacy device bearer token 明文经过网络。

## Cloudflare Tunnel：Legacy 可选路径

Cloudflare Tunnel 适合想给 legacy server 或 local gateway 一个 HTTPS remote URL、但不想让 Mac 直接暴露公网端口的用户。它不是 Ownlight 当前 iCloud 同步的必需组件。

如果你使用 Cloudflare Tunnel：

- 使用自己的 Cloudflare 账号和域名。
- 给 endpoint 加 Cloudflare Access、allowlist、gateway auth 或其他访问控制。
- local gateway 只放行 gateway 需要的 transcription API。
- legacy server 只放行需要维护的 API。
- 不建议在没有额外保护时暴露完整 Admin UI。

legacy server 最小 API 面：

```text
/api/v1/health
/api/v1/auth/login
/api/v1/sync
/api/v1/media/*
/api/v1/checkin-media/*
/api/v1/ai/media-summary
/api/v1/admin/status
```

`/admin/` 是 legacy Mac-local 运维界面，默认应保留在本机或私有网络里。

## 本地覆盖配置

复制示例文件：

```bash
cp .env.local.example .env.local
```

常用项：

```env
PRIVATE_MOMENTS_DEVICE_NAME="Your iPhone"
PRIVATE_MOMENTS_DEVICE_SERVER_URL=https://your-private-server.example
PRIVATE_MOMENTS_FALLBACK_SERVER_URL=https://your-fallback-server.example
PRIVATE_MOMENTS_DEVELOPMENT_TEAM=YOURTEAMID
PRIVATE_MOMENTS_IOS_BUNDLE_ID=dev.yourname.privatemoments
PRIVATE_MOMENTS_IOS_SHARE_BUNDLE_ID=dev.yourname.privatemoments.share
PRIVATE_MOMENTS_IOS_APP_GROUP=group.dev.yourname.privatemoments
```

`.env.local` 会被 `npm run ios:simulator` 和 `npm run ios:device` 读取。脚本会生成 ignored 的 `ios/Config/Local.xcconfig`，用于覆盖公开默认的 iOS bundle id、App Group、Team ID、CloudKit container 和 legacy fallback URL。

如果你已经在真实 iPhone 上安装过 Ownlight，并希望保留原有 app container 与 App Group 数据，不要随意改变这些值：

- `PRIVATE_MOMENTS_IOS_BUNDLE_ID`
- `PRIVATE_MOMENTS_IOS_SHARE_BUNDLE_ID`
- `PRIVATE_MOMENTS_IOS_APP_GROUP`

## Legacy App 内配置模型

iOS App 的 legacy server path 曾使用下面的配置模型；当前 iCloud 同步不使用它：

1. 用户在 Settings 里配置 `Server URL`。
2. App 先尝试这个 URL。
3. 如果 build 里注入了 `PRIVATE_MOMENTS_FALLBACK_SERVER_URL`，App 会把它作为额外候选。
4. 网络级失败或 route-missing 响应会尝试下一个候选；认证失败和业务错误不会被静默跳过。

这让维护 legacy server 的用户可以自由选择网络层，而不需要修改旧同步协议或 server 代码。
