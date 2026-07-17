# Ownlight 运维手册

这份 runbook 覆盖 iOS app 的本地运行/验证，以及 legacy Mac server、Admin UI、archive/recovery path 的维护和排障。当前日常产品路径是 iPhone 本地 SQLite + 可选 iCloud/CloudKit；legacy server/admin 不再是普通用户使用或 App Store 首发的前置条件。

## 环境要求

- 安装 Xcode 的 macOS。
- Node.js `>=22`。
- `npm`。
- `xcodegen`，用于重新生成 `ios/PrivateMoments.xcodeproj`。
- iCloud 同步需要 Apple Developer 侧 container/entitlement/provisioning 正确配置，但不需要 Server URL。
- 只有维护 legacy server 或 local gateway 时，真实 iPhone 才需要一个能访问对应服务的 URL。可以使用 LAN、Tailscale/私有 VPN、Cloudflare Tunnel 或其他受保护 HTTPS endpoint；项目本身不绑定具体供应商。
- 已配对的 iPhone 需要解锁，并信任当前 Mac，才能通过命令行安装。
- `restic`，用于 Mac Admin 的 Archive backup/restore 功能。可通过 `brew install restic` 安装。

## 环境变量

| Variable | Default | Purpose |
|---|---|---|
| `HOST` | `127.0.0.1` | Server bind address。真实 iPhone 通过 LAN、私有 VPN 或 tunnel 访问时通常使用 `0.0.0.0`。 |
| `PORT` | `3210` | Server port。 |
| `LOG_LEVEL` | `info` | Fastify log level。 |
| `PRIVATE_MOMENTS_INITIAL_PASSWORD` | unset | 数据库没有 user 时，用于创建第一个本地用户。 |
| `PRIVATE_MOMENTS_DATA_DIR` | `~/Library/Application Support/PrivateMoments` | Runtime data directory。开发时常用 `./server/data`。 |
| `DATABASE_URL` | `file:<dataDir>/app.sqlite` | Prisma SQLite database URL。`server/.env.example` 里的 `file:./dev.db` 是相对 `server/prisma/schema.prisma`。 |
| `PRIVATE_MOMENTS_SERVER_URL` | `http://127.0.0.1:3210` | Simulator script server URL。 |
| `PRIVATE_MOMENTS_SIM_NAME` | `Private Moments iPhone 13 Pro` | Simulator display name。 |
| `PRIVATE_MOMENTS_DEVICE_TYPE` | `com.apple.CoreSimulator.SimDeviceType.iPhone-13-Pro` | Simulator device type。 |
| `PRIVATE_MOMENTS_DEVICE_NAME` | `Your iPhone` | `devicectl` 使用的真实 iPhone 名称。 |
| `PRIVATE_MOMENTS_DEVICE_SERVER_URL` | auto-detected | 真实设备 server URL override。 |
| `PRIVATE_MOMENTS_FALLBACK_SERVER_URL` | unset | 可选 bundled fallback URL。可以是受保护 Cloudflare Tunnel、Tailscale HTTPS 或其他 endpoint。 |
| `PRIVATE_MOMENTS_DEVELOPMENT_TEAM` | unset | 本地 Apple Developer Team ID，通过 `.env.local` 或 `ios/Config/Local.xcconfig` 覆盖。 |
| `PRIVATE_MOMENTS_IOS_BUNDLE_ID` | `dev.privatemoments.app` | 主 App bundle id。已安装真实设备后要保持稳定，避免丢失 app container 连续性。 |
| `PRIVATE_MOMENTS_IOS_SHARE_BUNDLE_ID` | `dev.privatemoments.app.share` | Share Extension bundle id。 |
| `PRIVATE_MOMENTS_IOS_APP_GROUP` | `group.dev.privatemoments.app` | 主 App 和 Share Extension 共享的 App Group。 |
| `PRIVATE_MOMENTS_PREFLIGHT_STRICT` | unset | 设为 `1` 时，`ios:preflight` 会把 warnings 也视为失败。 |
| `PRIVATE_MOMENTS_LAUNCHD_LABEL` | `com.private-moments.server` | launchd label。 |
| `PRIVATE_MOMENTS_ENABLE_LEGACY_REVIEW_SCHEDULER` | unset | 默认不启动 Mac/server Weekly Review 自动生成。只有显式设为 `1`、`true`、`yes` 或 `on` 时才恢复旧 `ReviewScheduler`。 |

下面的 `AI_SUMMARY_*` / `AI_TRANSCRIPTION_*` 变量只用于 legacy Mac/server-side AI routes、历史诊断和兼容路径。当前默认产品路径在 iPhone Settings > AI & Analysis 配置 provider，API key 保存在 iPhone Keychain，不通过 Mac server 环境变量同步或保存。

| Variable | Default | Purpose |
|---|---|---|
| `AI_SUMMARY_PROVIDER` | `openai` | AI summary provider label。当前实现使用 OpenAI-compatible Chat Completions API。 |
| `AI_SUMMARY_BASE_URL` | `https://api.openai.com/v1` | 外部 AI provider base URL。 |
| `AI_SUMMARY_API_KEY` | unset | 外部 AI API key。只放在 Mac server 环境里，不写入 iOS 或文档。 |
| `AI_SUMMARY_MODEL` | `gpt-4o-mini` | AI summary model。 |
| `AI_SUMMARY_PRIMARY_HEALTH_URL` | unset | primary provider health probe URL；配置 fallback 时建议指向 localhost gateway 的 `/health`。 |
| `AI_SUMMARY_PRIMARY_HEALTHY_INTERVAL_MS` | `60000` | primary healthy 时的后台探测间隔。 |
| `AI_SUMMARY_PRIMARY_DOWN_INTERVAL_MS` | `15000` | primary down 时的后台探测间隔；恢复后会自动切回 primary。 |
| `AI_SUMMARY_PRIMARY_HEALTH_TIMEOUT_MS` | `1000` | unknown/stale 状态 quick probe 超时，避免请求入口长时间卡住。 |
| `AI_SUMMARY_PRIMARY_HEALTH_STALE_MS` | `120000` | primary health 状态超过该时间未刷新时，请求入口会做一次 quick probe。 |
| `AI_SUMMARY_FALLBACK_PROVIDER` | `deepseek` | fallback provider label。只有配置 `AI_SUMMARY_FALLBACK_API_KEY` 时启用。 |
| `AI_SUMMARY_FALLBACK_BASE_URL` | `https://api.deepseek.com` | fallback provider base URL。 |
| `AI_SUMMARY_FALLBACK_FAST_MODEL` | `deepseek-v4-flash` | fallback 短内容/标签建议模型。 |
| `AI_SUMMARY_FALLBACK_PRO_MODEL` | `deepseek-v4-pro` | fallback 长内容/Weekly Review 模型。 |
| `AI_SUMMARY_FALLBACK_API_KEY` | unset | fallback API key。只放在 ignored `server/.env` 或 launchd 环境里，不写入 tracked 文件。 |
| `AI_SUMMARY_LONG_CONTENT_THRESHOLD_CHARS` | `8000` | 超过该输入字符数时 fallback 使用 pro model。Weekly Review 始终使用 pro。 |
| `AI_TRANSCRIPTION_PROVIDER` | `local` | 语音/视频转写 provider。默认用 Mac 本地 `mlx-whisper`，只把生成后的 transcript 交给 summary API。 |
| `AI_TRANSCRIPTION_MODEL` | `gpt-4o-mini-transcribe` | OpenAI-compatible transcription model。仅在 `AI_TRANSCRIPTION_PROVIDER=openai` 时使用。 |
| `AI_LOCAL_TRANSCRIPTION_PYTHON` | `./.venv/bin/python` | 本地转写 Python 路径，相对 `server/` 运行目录。 |
| `AI_LOCAL_TRANSCRIPTION_SCRIPT` | `./scripts/local-transcribe.py` | 本地转写脚本路径。 |
| `AI_LOCAL_TRANSCRIPTION_MODEL` | `mlx-community/whisper-turbo` | `mlx-whisper` 模型。 |
| `AI_LOCAL_TRANSCRIPTION_TIMEOUT_MS` | `600000` | 本地转写超时。长语音可调大。 |
| `AI_SUMMARY_TIMEOUT_MS` | `60000` | AI summary provider request timeout。 |

独立 `transcription-gateway` 是 iPhone Advanced Transcription 使用的 Mac 本地转写 helper，不是 Mac server AI job path。它有自己的端口、进程、日志和 token；不读取 Mac server 的 AI provider key，也不写 iPhone/Server SQLite。

| Variable | Default | Purpose |
|---|---|---|
| `TRANSCRIPTION_GATEWAY_HOST` | `127.0.0.1` | Gateway bind host。先保持 localhost；需要真机访问时再通过 LAN/Tailscale/Cloudflare 暴露受保护入口。 |
| `TRANSCRIPTION_GATEWAY_PORT` | `3322` | Gateway port。 |
| `TRANSCRIPTION_GATEWAY_TOKEN` | unset | 必填 Bearer token。放在 ignored env/local config，不写入 tracked docs/code。iPhone 端同一个 token 保存在 Keychain。 |
| `TRANSCRIPTION_GATEWAY_MODEL` | `mlx-community/whisper-large-v3-turbo` | 默认 MLX Whisper model；可在 iPhone Settings 中针对请求覆盖 model 字段。 |
| `TRANSCRIPTION_GATEWAY_PYTHON` | `server/.venv/bin/python` | Python runtime，默认复用 existing server venv。 |
| `TRANSCRIPTION_GATEWAY_SCRIPT` | `server/scripts/local-transcribe.py` | MLX Whisper wrapper script。 |
| `TRANSCRIPTION_GATEWAY_TIMEOUT_MS` | `600000` | 单次转写超时。 |
| `TRANSCRIPTION_GATEWAY_MAX_FILE_BYTES` | `52428800` | multipart audio file size limit。 |

## Runtime Truth Check

每次 server schema、API route 或 Admin UI 改完后，不只看 build 成功，还要确认 3210 上的实际进程已经加载当前 build：

```bash
npm run server:prisma:deploy
npm run server:build
launchctl kickstart -k "gui/$(id -u)/${PRIVATE_MOMENTS_LAUNCHD_LABEL:-com.private-moments.server}"
curl -fsS http://127.0.0.1:3210/api/v1/health
```

`/api/v1/health` 的 `schemaVersion` 必须和 `server/src/config/app-config.ts` 中的 `SCHEMA_VERSION` 一致。若 build 通过但 health 仍返回旧 schema，说明 LaunchAgent 或当前 server 进程仍在运行旧代码，先重启服务再继续验证。

## Local Transcription Gateway

gateway 第一版使用已有 `server/.venv` 和 `mlx_whisper`。如果还没有准备本地 AI venv，可以先运行：

```bash
npm run setup:local -- --with-ai
```

本地开发启动：

```bash
TRANSCRIPTION_GATEWAY_TOKEN="<choose-a-local-token>" npm run gateway:dev
```

常驻运行时，推荐把这些变量放在 ignored `transcription-gateway/.env.local`，LaunchAgent 只 source 这个文件后启动 gateway。不要把真实 token 放进 tracked docs/code，也不要把 token 写在 LaunchAgent `ProgramArguments` 里，否则 `ps` 之类的进程列表会暴露它。

健康检查：

```bash
curl -fsS \
  -H "Authorization: Bearer <choose-a-local-token>" \
  http://127.0.0.1:3322/health
```

返回应包含 `service=private-moments-transcription-gateway`、`provider=local-gateway`、`engine=mlx-whisper`、`status=ready` 和当前 model。未带 token 或 token 错误应返回 `401`。

iPhone 端配置路径：

1. 打开 Settings > AI & Analysis > Advanced Transcription。
2. 选择 `OpenAI-compatible Endpoint`。
3. 进入 provider 设置页，填写 Base URL、API Key 和 Model。
4. 点 `Test Connection`。它会用当前表单里的 Base URL、API Key 和 Model 调用 `/v1/models`，不会上传音频；连接成功后会自动保存这组配置。失败时不会覆盖上一组已保存配置。

使用本机 Local Gateway 时，Base URL 推荐填写服务根地址，例如 `http://<mac-host>:3322`。如果旧配置仍是 `http://<mac-host>:3322/health`，iOS 会在 `/v1/models` 和 `/v1/audio/transcriptions` 调用中把 trailing `/health` 当作 service root 兼容处理。其他 OpenAI-compatible transcription endpoint 可以填写服务根地址或已经带 `/v1` 的 base URL；真实转录请求最终会落到 `/v1/audio/transcriptions`。

如果 `Test Connection` 返回 Cloudflare `502` / HTML 错误页，而本机 `127.0.0.1:3322` 能返回 `401` 或正常 JSON，优先检查 iPhone 填写的 Base URL 是否走到了正确的 gateway tunnel hostname，以及 Cloudflare ingress 是否把 `/v1/models` 和 `/v1/audio/transcriptions` 转发到 gateway 端口。旧的通用 API hostname 可能仍指向其他本地服务端口，端口无人监听时会表现为 Cloudflare 502。

默认 gateway 只监听 `127.0.0.1:3322`，真实 iPhone 不能直接访问 Mac 的 localhost。需要真机 UAT 时，可以使用 LAN、Tailscale/private VPN 或 Cloudflare Tunnel 暴露这个端口。不要把个人 Cloudflare URL、tunnel id、tailnet 名称或 Bearer token 写入 tracked 文件。即使外层有 Cloudflare Access/Tailscale，也保留 gateway 自己的 Bearer token，避免裸露音频转录接口。

Cloudflare/Tailscale 只是传输层。Local Gateway 只返回 transcript，不读写 iPhone SQLite，不生成 summary，不 enqueue sync/server AI job，也不是 Mac data replication layer。它现在只是 `OpenAI-compatible Endpoint` 的一个可填示例，而不是 iOS Settings 里的独立 provider 类型。

## iCloud / CloudKit UAT

iCloud 是当前 App Store v1 方向的可选跨设备复制层。默认 source of truth 仍是 iPhone 本地 SQLite；没有 iCloud、没有网络或同步失败时，记录和浏览仍应在本机可用。

当前 Settings 路径：

1. 打开 Settings > Data Storage > iCloud。
2. 确认 iCloud account 状态可用。
3. 打开 `iCloud Sync`。首次开启会提示当前本地资料库会排入 private iCloud sync。
4. 使用 `Sync Now` 作为低频诊断入口；普通本地变更会在后台 debounce 后自动同步。

重要边界：

- `Run CloudKit Smoke Test` 只创建或复用一条显式测试 Moment，并上传这一条测试记录。它用于验证账号、container、zone 和写入权限，不代表完整资料库上传。
- 普通 `iCloud Sync` 首次同步会运行 `cloudkit_initial_upload_v1` 本地库准备，把允许范围内的已有本地内容排入 CloudKit pending queue，再通过现有 small-batch runner 逐步上传。
- 首次库准备包含：active non-sample Timeline posts、moment media metadata/assets、comments、AI summaries、topic tags/aliases/assignments、check-ins/media/assets/summaries、非 deleted Weekly Reviews、允许同步的 app preference singleton、composer/edit draft metadata。
- 首次库准备排除：Welcome/sample data、AI provider profiles、API keys、raw transcript text、diagnostics、sync runtime/cache、legacy server state 和本机临时文件路径。
- 首次库准备前，app 会用 nil cursor 探测 CloudKit private zone。若远端已有真实用户 archive 且当前设备也有真实本地用户内容，sync 会记录 `cloudkit_initial_upload_conflict` 并阻止开启，Settings 会把 `iCloud Sync` 开关打回关闭；若当前设备为空库或只有 welcome sample，则跳过本地初始上传准备，先 pull 远端 archive。CloudKit smoke-test Moment 会被该探测忽略，不会让一台空设备误判成“已有用户 archive”。
- 首次库准备之后，新 comment create/delete、Timeline AI summary ready/delete、AI topic tag、post-tag assignment 和 AI title insert 会在 `iCloud Sync` 开启时作为普通 CloudKit 派生内容入队。它们不再只停留在本机 SQLite 或 legacy outbox。
- `cloudkit_derived_content_backfill_v1` 会在普通 sync 前运行一次，用于补传旧版本已经生成但缺少 CloudKit upload state 的本地派生记录：comments、Timeline AI summaries、tags、tag aliases 和 post-tag assignments。它会跳过从 CloudKit 下载而来但尚未由本机上传过的记录，避免第二台设备把已下载的派生记录反向重新上传。
- Composer / Edit Moment draft 的 text、occurredAt、updatedAt metadata 会在 `iCloud Sync` 开启时随 save/clear 自动 enqueue `.draft` upsert/delete。连续输入会复用已有 pending upsert，避免每个 keystroke 都排一条变更；如果已经排了 delete 后用户继续输入，会追加新的 upsert，保证恢复草稿不会被旧 delete 吞掉。Draft v1 不同步临时媒体文件、临时本机路径或 draft-only media bytes。
- Preference sync 只包含 `CloudKitPreferenceSnapshot` 明确 allowlist 的用户可见偏好。AI provider profile、API key、Base URL、model、fallback/cooldown state、diagnostics 和 runtime/cache 仍保持本机私有，不进入 CloudKit。
- 如果真实设备曾经参与 CloudKit sync，但因为旧版本或迁移状态缺少显式 `iCloudSyncEnabled` preference key，app 启动时会在确认本机已有 CloudKit 历史后恢复 opt-in，并运行 `icloud_opt_in_recovery`：补传缺失的本地记录，同时重新排入当前 preference/draft singleton 快照。该恢复不会把一个从未使用过 CloudKit 的设备自动打开 iCloud，也不会覆盖用户明确关闭 `iCloud Sync` 的选择。
- 普通 sync 成功后，app 会用独立 `cloudkit_full_reconcile_v1` sync state scope 做一次完整 private-zone pull。这个 pass 不重置普通 `PrivateMomentsV1` cursor，也不上传本机数据；它只用于恢复旧版本、历史 cursor 已前进或派生记录曾被跳过后，第二台设备缺少的可选派生内容，例如早期 Timeline AI summaries、tag aliases 或 post-tag assignments。如果该 pass 被 batch 上限、deferred record 或失败打断，会记录 `cloudkit_full_reconcile_incomplete`，后续 sync 再重试。
- 如果一轮 sync 结束后还有 pending CloudKit work，app 会继续调度 follow-up pass；大库上传可能需要等待多轮，不要求用户一直点 `Sync Now`。
- 自动同步节奏：app bootstrap、回到前台、开启 `iCloud Sync` 会立即 sync；普通内容和媒体变更用约 5 秒 debounce；已同步 Settings preference 变更用约 1 秒 debounce；前台设备约每 15 秒低频 poll。当前不是 CloudKit push/realtime subscription，因此第二台设备通常需要保持前台等待一轮 poll，或手动点 `Sync Now` 做诊断。
- `Sync Now` 显示 `0 uploaded, 0 downloaded, 0 deleted` 只代表这一轮没有成功处理新的上传/下载/删除工作；它不是“云端和所有设备已经完整”的证明。如果第二台设备仍缺内容，先检查 `local_cloudkit_sync_state.lastErrorCode` / `lastErrorMessage`、pending queue 和两端实体数量。
- 手动 `Sync Now` 现在会连续 drain 多个 upload/pull batch，直到本地 batch 结束、远端没有更多 changes、出现失败或出现 deferred 记录。它仍是低频诊断 fallback，普通使用应依赖自动 foreground/background sync。
- `Sync Now` 或开启 iCloud Sync 失败时，普通 Settings UI 应显示可理解的分类提示，而不是 CloudKit 原始诊断全文。当前分类包括：未登录 iCloud、网络离线、iCloud storage/quota 满、iCloud 暂时不可用、账号/系统限制、非空第二设备保护，以及通用可重试失败。原始 `CKErrorDomain`、record id、operation id 等细节只适合开发者日志或 container 诊断，不应重新出现在普通用户 alert 里。
- 如果 text/audio Moment 和 media 已同步，但评论或 AI summary 没有出现，优先检查源设备是否存在 `.comment` / `.ai_summary` / `.tag` / `.post_tag` pending changes；在源设备点一次 `Sync Now` 等待 drain，再到目标设备 foreground 或点 `Sync Now`。如果仍缺失，再复制两端 app container 检查 pending queue、record state 和相关父级 `moment/media/tag` 是否存在。
- 如果第二台设备只拉到一小段历史，例如 `Sync Now` 显示约十几条后不再继续，先复制两台设备 app container 并检查 CloudKit sync state / pending queue。已知阻塞包括：远端 bool 字段以 `0/1` 形式返回导致 tag apply 失败、旧同步被中断后留下 stale `running` pending changes、首次库上传重复入队时远端已有同名 media/asset record 导致 `serverRecordChanged`、子记录先于父记录到达导致 `missingParent`、旧 draft record 使用 `edit_...` 但缺少 `postId`，以及旧/派生 AI summary 或 tag assignment 引用已经不存在或无法应用的父 media/tag。当前实现会兼容 numeric bool、10 分钟后重新 claim stale running、在同 record 已存在时基于 server record 更新重试、为可解析子记录先 fetch/apply missing parent、从 sanitized edit draft record id 恢复 post identity，并且对可选派生记录的不可恢复父级只忽略该派生记录，不阻断整个 pull。
- 如果 `Sync Now` 只剩 `1 failed` 且 pending queue 指向 `PMCheckInAISummary` / `checkin_ai_summary`，优先检查 `lastErrorMessage` 是否包含 `cannot use an empty list to initialize a new field` 和 `keyPoints`。当前实现会在上传时清除/省略空 string list，并在拉取 AI summary 时把缺失 `keyPoints` 当作空数组；如果失败来自旧 build，安装新 build 后再点一次 `Sync Now` 让该 pending change 重试。若错误指向 `PMDraft / pm.draft.edit_...` 和 `UNIQUE(zoneName, recordName)`，确认 build 已包含 draft record name canonicalization 和 record-state by-record-name merge。若错误指向 `PMDraft / pm.draft.composer` 和 `missingField("existingMediaIds")`，安装包含 draft missing-empty-list 兼容的新 build；composer draft 的空 `existingMediaIds` 在 CloudKit 远端可以表现为字段缺失，当前实现会按空数组应用。

M017 第一阶段 `UAT-M017-CLOUDKIT-CROSS-DEVICE` 已关闭。后续如果修改 CloudKit record schema、pending queue、local apply、media asset、draft/preference、delete/tombstone 或 initial upload 逻辑，至少需要用同一 Apple ID 的两台真实设备重新抽测：

- iPhone 保持 `iCloud Sync` 开启，触发首次本地库上传。
- iPad 空库或可控库打开 app 后能 pull 到完整 Moments，包括文字、评论、tags、check-ins、reviews 和媒体 asset。
- 新建/编辑/删除 text 和 audio Moment 能自动传播；comment、AI summary、draft metadata 和 synced preferences 能跨设备落地；`Sync Now` 只作为 fallback diagnostic。
- 非空第二设备保护不会静默合并或覆盖；AI provider profile、API key、Base URL、model、private transcript text 和 diagnostics 不进入 CloudKit。
- App Store 提交前仍需单独复核真实 quota/网络失败提示、最终隐私文案、App Privacy label、screenshots 和 App Review copy。

## 统一验证入口

常规 checkpoint 优先运行：

```bash
npm run verify:all
```

它会串联 server typecheck/test/build、Admin build、generic iOS build、UAT gate 检查、`git diff --check`，并在本机 `3210` 已有 server 响应时附带一次 live health check。它不会安装到真实 iPhone，也不会替代人工 UAT。

按范围拆开运行：

```bash
npm run verify:server
npm run verify:ios:generic
npm run verify:uat-gates
npm run smoke:admin
```

`npm run verify:uat-gates` 只报告 `docs/UAT-GATES.md` 里还打开的真实设备/人工门禁。准备 release candidate 时再运行严格门禁：

```bash
npm run verify:release-gates
```

只要还有 open UAT gate，`verify:release-gates` 就会失败，这是预期行为。关闭 gate 需要真实 iPhone、Mac Archive 或用户确认的证据，不能只用 build/simulator 结果代替。

`npm run smoke:admin` 默认只检查 live health。如果设置 `PRIVATE_MOMENTS_SMOKE_PASSWORD`，脚本会登录本机 server，并只读检查 Admin status、Archive maintenance state/job list、Archive repository、Review settings 和 Review list。认证模式会创建或复用一个名为 `Admin Smoke` 的 Mac device row；不要把真实 password 写入脚本或文档。

## 维护 Doctor 入口

`verify:*` 负责构建、测试和 gate；`doctor:*` 负责当前机器的运行态、数据和发布边界。目录迁移、LaunchAgent 重装、网络 endpoint 调整、Archive 演练、AI prompt 调整或开源前检查后，优先跑对应 doctor。

```bash
npm run doctor:runtime
PRIVATE_MOMENTS_SMOKE_PASSWORD="<read-from-server-env>" npm run doctor:sync
npm run doctor:archive
npm run doctor:ai
npm run doctor:release
PRIVATE_MOMENTS_SMOKE_PASSWORD="<read-from-server-env>" npm run doctor:all
```

- `doctor:runtime` 检查 `server/.env`、live health、LaunchAgent plist/state、3210 listener cwd/fd、Prisma client、server `.venv` shebang、SQLite `quick_check`，以及本地配置的 remote/private-network endpoint health。它用于确认当前服务没有继续指向旧目录或旧 build。
- `doctor:sync` 检查 server change cursor、device 表、pending/rejected sync operations、media 队列、AI summary 队列和 maintenance jobs。设置 `PRIVATE_MOMENTS_SMOKE_PASSWORD` 时，它会登录 Admin status 做只读交叉验证；不设置时会跳过认证检查。
- `doctor:archive` 对 live SQLite 做临时复制和 `quick_check`，统计 posts/media/check-ins/server changes，确认未删除 media 引用有文件，检查 archive config、`restic` 可用性和 pending promote 文件；若存在 `pending-promote.json`，还会给出和 Admin readiness drill 对齐的非破坏性准入判断。它只写 `.tmp/archive-drills/<timestamp>/report.json`，不改 live archive。
- `doctor:ai` 对 live DB 做启发式质量检查：ready summary title 长度、prompt version、document body、recent one-liner、Weekly Review prompt/version/anchors，以及 `ai_usage_events` 记账。旧历史数据可能产生 warning，但不应阻塞运行态修复。
- `doctor:release` 做当前工作区开源边界扫描：license、tracked API key 形态、个人 Cloudflare/Tailscale 配置、ignore 边界、公开 docs 和 `.planning` / legacy archive release 策略。真正公开前仍必须额外做 Git history secret scan。

重复出现的 `Cloudflare Tunnel` / `530` / `1033` / `pending` 事故，统一记录在 [CLOUDFLARE-TUNNEL-INCIDENTS.md](CLOUDFLARE-TUNNEL-INCIDENTS.md)。下次先看这个台账，再决定是否要继续往 app sync 逻辑里挖。

doctor 输出按 `PASS / WARN / FAIL` 聚合。`FAIL` 表示当前 checkpoint 不应继续发布或迁移；`WARN` 表示存在需要记录的历史数据、发布准备或人工判断项。

## Worktree 开发和数据安全

`main` 工作目录只作为固定版本的集成线。功能开发、测试、构建、打包和真实设备 UAT 默认在独立 worktree 中完成。

创建功能 worktree：

```bash
git worktree list
mkdir -p ../private-moments-worktrees
git worktree add -b codex/<topic> ../private-moments-worktrees/<topic> main
```

在 Codex App 中，一个 thread 固定使用一个 worktree。不要在同一个工作目录中反复切换 `main` 和功能分支。功能完成后，先在功能 worktree 中提交 checkpoint 并完成对应验证，再回到 `main` 工作目录合并。

合并后清理：

```bash
git worktree remove ../private-moments-worktrees/<topic>
git branch -d codex/<topic>
git worktree list
```

### Worktree server 数据隔离

Worktree 隔离的是代码目录，不自动隔离 runtime data。临时功能分支启动 server 时，默认使用独立端口和独立 data directory，不要直接写当前 live archive：

```bash
mkdir -p server/data-worktree
PORT=3310 \
PRIVATE_MOMENTS_DATA_DIR="$PWD/server/data-worktree" \
DATABASE_URL="file:$PWD/server/data-worktree/app.sqlite" \
npm run server:dev
```

如果需要对临时 data directory 初始化 schema，先在同一组环境变量下运行 Prisma deploy 或 `setup:local`。不要删除或重建已有真实 SQLite 文件来解决迁移问题。

只有在准备最终集成验证时，才允许让当前代码指向 live data。这样做前必须确认：

- 当前分支就是准备合入 `main` 的版本。
- 已经有可恢复的 archive backup、export artifact，或其他等价恢复点。
- 没有另一个 3210 server 进程仍在运行旧代码。
- `/api/v1/health` 返回的 schemaVersion 与当前代码一致。

### Worktree iOS 安装数据安全

真实 iPhone 上的 `Ownlight` 使用固定 bundle id。无论 app 是从 `main` 还是 feature worktree 打包安装，只要 bundle id 不变，iOS 都会继续使用同一个 app container。这是保留用户数据的基础，但也意味着临时分支的代码会直接运行在现有本地数据上。

从 feature worktree 安装到真实 iPhone 前，必须确认：

- 分支基于当前 `main`，不是旧分支或旧 schema 回退。
- 没有改变 bundle id、App Group id、local database 文件位置或 media cache 路径。
- 没有删除 app、清空 app container、重置 SQLite、清空 outbox 或清理 media cache 的调试代码。
- Sync Health 没有显示必须保留的未同步 outbox、local-only draft 或 media upload 队列；如果有，先完成 Sync Now，或复制 app container 后再安装。
- 涉及 SQLite、sync cursor、outbox、media recovery、backup/restore、auth 或真实设备恢复的变更，已经按 milestone/slice planning 准备验证和恢复方案。

如果需要验证高风险 iOS 变更，优先用 low-impact generic build、focused tests、或隔离数据做第一轮；只有视觉/UAT 需要时才开 Simulator。真实 iPhone 安装前，优先确认 iPhone 本机资料库和 iCloud pending 状态；如果 iPhone 可能还有未同步本地数据，必须用 `xcrun devicectl` copy app container，保留安装前的本地数据库和媒体 cache 证据。Legacy Mac archive backup 只保护已经进入旧 archive 路径的数据，不能单独当作当前 iPhone-first build 的恢复点。

## Archive / Backup / Restore

Archive 功能用于自用灾难恢复，入口在 Mac Admin 的 `Archive` tab。日常备份/恢复不需要直接运行 restic 命令，但 Mac 上必须安装 restic：

```bash
brew install restic
restic version
```

### 备份仓库和 key 文件

在 Admin `Archive > Backup Repository` 中填写 repository path。它可以是普通本机目录，也可以是用户自己明确选择的 iCloud Drive 目录，例如：

```text
/Users/<you>/Library/Mobile Documents/com~apple~CloudDocs/PrivateMomentsBackup
```

保存路径后，项目会在 repository 目录旁边创建或复用：

```text
.private-moments-restic-key
```

这个 key 文件就是 restic repository 的密码来源。用户不需要记一个额外的备份密码，但要理解安全语义：谁同时拿到 repository 内容和 `.private-moments-restic-key`，谁就可以恢复这个 archive。这是面向本人长期使用的恢复工具，不是额外的加密保险箱。

### 初始化和备份

常规流程：

1. 打开 `http://127.0.0.1:3210/admin/` 并登录。
2. 进入 `Archive` tab。
3. 填写 `Repository path`，点 `Save path`。
4. 点 `Initialize` 初始化 restic repository。
5. 点 `Backup now` 立即创建快照。
6. 在 `Snapshots` 和 `Recent Jobs` 区域确认结果。

手动备份会创建一个受控 snapshot source，而不是直接 zip 当前运行中的目录。当前 snapshot 包含：

- `app.sqlite`
- `manifest.json`
- `media/`
- `backup-manifest.json`

运行时依赖和临时文件，例如 `node_modules`、`.venv`、build output、media temp 文件，不作为恢复数据源。

### 每日定时备份

在 `Daily Backup` 中打开 `Enable daily backup` 并设置时间。server 进程每分钟检查一次 schedule；到点时如果没有其他 maintenance job 正在运行，就创建 `backup_create` job。如果当时已有 job 在跑，本次 scheduled backup 会跳过并写安全日志。

### Snapshot check

点 `Check repository` 会运行 restic repository check，并把结果记录为 `backup_check` maintenance job。建议在首次设置、换 repository 位置、或者怀疑 iCloud Drive 同步不完整时运行一次。

### Restore 到新目录

在 `Snapshots` 中选择某个 snapshot 点 `Restore`。restore job 会把 snapshot 恢复到：

```text
<dataDir>/archive/restores/<timestamp>-<snapshot>
```

恢复完成后，job metadata 和 `artifactPath` 会显示恢复出的数据目录。server 会自动做基本验证：

- `app.sqlite` 存在且可读。
- `manifest.json` 存在。
- `media/` 目录存在。
- 未删除 media 的文件引用仍在恢复目录内，且文件存在。

验证通过时，job stage 会进入 `completed`，metadata 里的 `verification.ok` 为 `true`，`missingMediaFiles` 应为 `0`。

### Promote preparation

当前 v0.1 不在运行中直接替换 live SQLite database。原因是 server 的 Prisma 连接已经打开，热替换数据目录风险比收益大。

Promote 的正确流程是：

1. 先完成 restore，并确认 Recent Jobs 里的 restore `artifactPath`。
2. 在 `Promote Restore` 填入 `Restored data directory`。
3. 在 `Confirmation` 中输入：

```text
PROMOTE <restored-folder-name>
```

4. 点 `Prepare promote`。

Admin 会在 `Promote Restore` 区块直接显示当前 `pending-promote.json` 的 handoff truth，包括 instruction file、restored/current data dir、pre-promote snapshot 和需要切换的 env；不需要再手动去 Finder 里找这个文件，除非你要做更低层的排障。

如果 Admin 把这份 handoff 标成 stale 或 malformed，先不要继续 promote。典型原因包括：restore 目录已经不再通过验证、live data dir 已经切到目标目录、或者这份 JSON 来自旧的一次演练。当前流程允许只在 stale/malformed 时通过 Admin 清掉它，避免旧指令文件挡住下一次 restore/promote 演练。

同一区块现在还会显示 `Readiness drill`。这不是实际切换，而是一次 restart-safe 准入检查：它会确认 handoff 文件存在、不是 stale、pre-promote backup metadata 还在、restore 目录仍可验证，以及 `requiredEnv` 仍然和 restore 目录匹配。只有这里显示 ready，才值得继续做真正的 stop / update env / restart。

Promote preparation 会：

- 进入 maintenance mode，暂停普通 sync/media/AI/admin destructive writes。
- 重新验证 restored data directory。
- 为当前数据创建一份 `pre-promote` backup。
- 写入：

```text
<dataDir>/archive/pending-promote.json
```

这个文件包含恢复目录、当前目录、pre-promote backup metadata，以及需要切换的 env：

```text
PRIVATE_MOMENTS_DATA_DIR=<restored-data-dir>
DATABASE_URL=file:<restored-data-dir>/app.sqlite
```

真正切换时，停止 server，按 `pending-promote.json` 更新 `server/.env` 或 launchd 环境，再重新启动 server。不要在 server 仍运行时手动替换当前 `app.sqlite` 或整个 data directory。

### Maintenance jobs

Archive 操作会写入 `maintenance_jobs`，Admin `Recent Jobs` 显示最近 job。可通过 API 排查：

```bash
curl -fsS http://127.0.0.1:3210/api/v1/admin/maintenance/jobs \
  -H "Authorization: Bearer $TOKEN"
```

job metadata 只允许保存路径、状态、计数、错误码等安全信息；不要把 post 正文、comment、transcript、summary 正文或媒体内容写进 job metadata 或日志。

### Export / Import 迁移包

Export/import 是迁移和恢复辅助路径，不替代 restic backup。入口同样在 Mac Admin 的 `Archive` tab。

Export 会生成：

- `manifest.json`：包格式、schema/server 版本、导出范围和计数。
- `archive.json`：权威迁移数据，包含 posts、media metadata、comments、tags、tag aliases、post tag assignments 和 AI summaries。
- `media/`：导出范围内引用到的媒体文件。
- `preview.md`：仅供快速阅读预览，不作为导入依据。
- `private-moments-export-<timestamp>.tar.gz`：可移动的导出包。

在 `Exports` 区域点击 `Create export` 时，如果 `From` / `To` 留空就是全量导出；填写日期则按 occurred date 做半开区间导出。导出完成后，在 `Recent Jobs` 查看 `export_create` job 的 `artifactPath`，它就是 `.tar.gz` 包路径。

Import 只会导入到新的 staged data directory：

```text
<dataDir>/archive/imports/<timestamp>-<label>/data
```

导入不会覆盖当前 archive，也不会恢复旧的 device token、session、sync operations 或 maintenance jobs。导入会保留内容 ID、时间戳、tag/AI generated metadata，并重建新的 `server_changes`，方便后续作为一个干净 archive 被新设备同步。导入完成后，`import_restore` job 的 `artifactPath` 是 staged data directory；如果要切换使用，后续仍走 `Promote Restore` 的强确认流程。

## 本地开发启动

推荐一键初始化：

```bash
npm run setup:local
```

这个脚本会：

- 保留已有的 `server/.env`，只在缺失时从 `server/.env.example` 创建。
- 生成 Prisma client。
- 如果 `DATABASE_URL` 指向 SQLite `file:` 且数据库文件还不存在，先创建一个空 SQLite 文件，再使用 `server:prisma:deploy` 应用已有数据库迁移。
- 构建 Admin UI 和 Server。
- 不自动覆盖真实密码、真实数据或媒体文件。

可选参数：

```bash
npm run setup:local -- --with-ai
npm run setup:local -- --with-ios
```

`--with-ai` 会创建或复用 `server/.venv` 并安装 `mlx-whisper`，用于 Mac 本地转写。`--with-ios` 会要求本机已安装 `xcodegen` 并重新生成 Xcode project。

手动初始化 fallback：

```bash
npm install
cp server/.env.example server/.env
npm run server:prisma:generate
npm run server:prisma:deploy
npm run admin:build
npm run server:build
npm run server:dev
```

如果是全新的 SQLite 文件，当前 Prisma SQLite engine 在某些机器上会要求文件先存在。推荐优先用 `npm run setup:local`，它会自动处理这个步骤。手动 fallback 时，如果 `server/.env` 仍使用默认 `DATABASE_URL="file:./dev.db"`，可在 deploy 前执行：

```bash
sqlite3 server/prisma/dev.db 'PRAGMA user_version=0;'
```

如果 `DATABASE_URL` 是绝对路径，例如 `file:/path/to/app.sqlite`，则在对应路径创建空 SQLite 文件即可；不要对已有真实数据库执行删除或重建。

第一次启动前，需要在 `server/.env` 里设置真实的 `PRIVATE_MOMENTS_INITIAL_PASSWORD`。Agent 应使用安全 secret 收集机制处理这个值，不要在聊天或文档中要求用户粘贴密码。

真实 iPhone 测试时，让 server 可以从 LAN、私有 VPN 或受保护 tunnel 路径访问：

```text
HOST=0.0.0.0
PRIVATE_MOMENTS_DATA_DIR="./data"
```

## 构建和安装 iOS

Simulator：

```bash
npm run ios:simulator
```

带可重复 demo 数据的 Simulator，用于 README 截图和 UI review：

```bash
npm run ios:simulator:demo
```

`ios:simulator:demo` 会以 `--private-moments-demo-data --private-moments-demo-data-reset` 启动 app。该入口只写入 `demo-` 前缀的本地 posts、tags、comments、AI summary metadata、media placeholders 和 check-ins；普通 `ios:simulator` 不会写入 demo 数据。

真实 iPhone：

```bash
npm run ios:device
```

隔离的真实 iPhone UAT 包，用于验证首次启动、AI 授权、新手引导和不会影响日常资料库的交互：

```bash
npm run ios:device:uat
```

`ios:device:uat` 会安装一个单独的 `Ownlight UAT`。它使用独立 bundle id、App Group、Keychain access group 和 app container，因此可以和日常使用的 `Ownlight` 同时存在；删除或重装 `Ownlight UAT` 不会删除日常 `Ownlight` 的本机 SQLite、媒体文件或 Keychain 凭据。后续验证 onboarding / first-run 状态时，优先使用这个入口。

如果 UAT 包签名失败，通常是 Apple Developer/Xcode 还没有为 UAT bundle id 或 App Group 生成 provisioning。可以先在 `.env.local` 中固定：

```text
PRIVATE_MOMENTS_UAT_IOS_BUNDLE_ID=your.bundle.id.uat
PRIVATE_MOMENTS_UAT_IOS_SHARE_BUNDLE_ID=your.bundle.id.uat.share
PRIVATE_MOMENTS_UAT_IOS_APP_GROUP=group.your.bundle.id.uat
```

真实设备脚本会：

1. 检查候选 server URLs。
2. 运行 `npm run ios:preflight`，确认 live server 可达、schema 不旧于当前代码、local archive queue/media/backup 状态可见、目标 iPhone 出现在 `devicectl`。
3. 如果可用，用 `xcodegen` 重新生成 Xcode project。
4. 构建 Debug iPhoneOS app。
5. 使用 `xcrun devicectl` 安装。
6. 启动 `dev.privatemoments.app`。

可以单独运行 preflight：

```bash
npm run ios:preflight
npm run ios:preflight -- --server-url http://127.0.0.1:3210 --device "the paired iPhone"
```

Preflight 的 warning 用来提示安装前应注意的环境状态，例如历史 rejected ops、没有最新 backup job、设备暂未出现在列表中。默认只有 server 不可达或 live schema 旧于当前代码会阻止安装；如果要把 warning 也作为阻断，设置：

```bash
PRIVATE_MOMENTS_PREFLIGHT_STRICT=1 npm run ios:preflight
```

如果 iPhone 阻止未信任开发者 app，在手机上信任开发者：

```text
Settings > General > VPN & Device Management > Developer App
```

### Share Extension

iOS app 内嵌 `Save to Ownlight` Share Extension。安装到 iPhone 后，可以在 Photos、Files、Voice Memos、Safari 或其他支持系统 Share Sheet 的 App 中选择 `Save to Ownlight`。

当前 Share Extension 使用 App Group：

```text
group.dev.privatemoments.app
```

真实设备签名时，主 App bundle id `dev.privatemoments.app` 和 extension bundle id `dev.privatemoments.app.share` 都需要在 Apple Developer 账号中启用同一个 App Group capability。若设备构建或安装时报 provisioning / entitlement 相关错误，先在 Apple Developer Portal 或 Xcode Signing & Capabilities 中确认 App Group 已注册并分配给这两个 identifiers。

验证路径：

1. 安装 App 到 iPhone。
2. 打开 Photos，选择 1-9 张图片，点 Share。
3. 选择 `Save to Ownlight`，可补一段文字。
4. 完成后主 App 应打开 New Moment composer，图片和文字进入草稿。
5. 发布后走原有本地保存、sync/upload 和后续 AI summary 流程。

Share Extension 的音频导入仍是单文件入口。多段录音只在主 App 的普通 New Moment Composer 中创建。

## Mac Admin

执行 `npm run admin:build` 后，server 会提供：

```text
http://127.0.0.1:3210/admin/
```

Admin 使用和 iOS login 相同的 password。Admin 会注册为 web device，并使用同一套 Bearer token flow。

## launchd Service

安装：

```bash
server/scripts/install-launchd.sh
```

卸载：

```bash
server/scripts/uninstall-launchd.sh
```

生产数据默认放在：

```text
~/Library/Application Support/PrivateMoments
```

launchd stdout/stderr logs：

```text
~/Library/Logs/private-moments.out.log
~/Library/Logs/private-moments.err.log
```

Application logs：

```text
<dataDir>/logs/app-YYYY-MM-DD.jsonl
```

## Smoke Checks

Server health：

```bash
curl -fsS http://127.0.0.1:3210/api/v1/health
```

从 Mac 检查你配置的 remote endpoint：

```bash
curl -fsS https://your-private-endpoint.example/api/v1/health
```

从 Mac 检查 Tailscale 或其他私有网络 reachability：

```bash
tailscale ip -4
curl -fsS http://<tailscale-ip>:3210/api/v1/health
```

如果临时启用了 Tailscale Serve，可使用 HTTPS 入口，避免 iOS App Transport Security 对明文 HTTP 的限制：

```bash
tailscale serve status
curl -fsS --resolve <tailscale-host>:443:<tailscale-ip> https://<tailscale-host>/api/v1/health
```

真实 iPhone 的 Server URL 可以是 LAN、Tailscale/private VPN、Cloudflare Tunnel 或其他受保护 HTTPS endpoint。Debug app 的 `NSAppTransportSecurity` 当前通过 `NSAllowsArbitraryLoads` 允许开发期明文 HTTP；公开部署仍建议优先使用受保护 HTTPS。

### Remote endpoint 和 fallback URL

Ownlight 不绑定 Cloudflare 或 Tailscale。App 只需要一个 Server URL；`.env.local` 可以给本机 build 注入一个额外 fallback URL。不要把个人域名、tunnel id、tailnet 名称或 DNS 目标提交到仓库。

```bash
PRIVATE_MOMENTS_FALLBACK_SERVER_URL=https://your-private-endpoint.example
```

`npm run ios:device` 和 `npm run ios:simulator` 会读取 `.env.local`，并把 `PRIVATE_MOMENTS_FALLBACK_SERVER_URL` 写入 app bundle 的 `PrivateMomentsFallbackServerURL`。Settings 中的 `Server URL` 仍是主配置。HTTP 401/403 或业务级 404 不会触发 candidate 切换；空 body 404 或 `Route ... not found` 这类路由级 404 会继续尝试下一个 server candidate，避免 stale tunnel allowlist 卡住同步。

如果使用 Cloudflare Tunnel 或其他公网入口，建议只放行 iOS 同步所需 API，避免把完整 Mac Admin UI 暴露到公网：

```text
/api/v1/health
/api/v1/auth/login
/api/v1/sync
/api/v1/media/*
/api/v1/checkin-media/*
/api/v1/ai/media-summary
/api/v1/reviews/*   # legacy/manual review API only; not required for iPhone-direct review settings
/api/v1/admin/status
```

如果仍需通过公网 endpoint 使用 legacy/manual Review API，例如历史客户端调用 `GET /api/v1/reviews` 或运维脚本检查旧 reviews，tunnel allowlist 里才需要包含 `/api/v1/reviews/*`。当前 iPhone-direct Weekly Review 设置和生成路径不依赖这条公网 route。

如果 Cloudflare endpoint 返回 `530` / `error code: 1033`，通常表示 tunnel connector 没有连上 Cloudflare edge。先在 Mac 上确认：

```bash
curl -i https://your-private-endpoint.example/api/v1/health
tail -n 80 ~/Library/Logs/cloudflared.err.log
dig +short region1.v2.argotunnel.com A
```

健康状态应看到 `/api/v1/health` 返回 `200`，`cloudflared` 日志出现 registered tunnel connection，`cloudflared tunnel info <tunnel-id>` 显示 active connector。如果本机使用代理、TUN 或 fake-IP DNS，优先确认 Cloudflare Tunnel edge 域名没有被错误解析或路由到不可用路径。不同网络环境的正确代理策略不同，不要把个人代理规则写入公开配置。

修改 Clash 或 plist 后重载 LaunchAgent，再用连续 health check 验证：

```bash
for i in {1..30}; do
  date '+%H:%M:%S'
  curl -sS -o /dev/null -w '%{http_code} %{time_total}\n' --max-time 12 \
    https://your-private-endpoint.example/api/v1/health
  sleep 10
done
```

Cloudflare `530` / `1033` 表示没有 active connector；`502` 且本机 health 正常时，通常表示 edge 连接刚掉线或 connector 卡在假活状态。先用 `cloudflared tunnel info <tunnel-id>` 确认控制面是否仍显示 active connector；如果没有，重启 LaunchAgent，并检查 plist 是否误带 `HTTP_PROXY` / `HTTPS_PROXY` 或 Clash 规则是否把 Tunnel 域名误设为不稳定路径。

Admin build 和 server typecheck：

```bash
npm run admin:build
npm run server:typecheck
```

Admin storage diagnostics。登录后把 device token 设置到 `TOKEN`：

```bash
curl -fsS http://127.0.0.1:3210/api/v1/admin/status \
  -H "Authorization: Bearer $TOKEN"
```

响应应包含 `counts`，以及 `storage.totalBytes`、`storage.databaseBytes`、`storage.mediaBytes`、`storage.logsBytes`、`storage.availableBytes`、`sync.latestServerChangeVersion`、`aiSummaries` 和 `aiUsage`。`aiSummaries` 只暴露计数、状态、错误码、duration、transcript length、卡住时长和排查提示，不暴露 transcript 或 summary 正文。`aiUsage` 只暴露 token/request/error 聚合，不暴露 prompt、transcript、review input 或 summary/review 正文。

Sync Health 还应包含 server-side `pendingOperations`、`rejectedOperations`、`failedMediaUploads`、`aiNonReady`、`lastServerChangeAt`、`lastSyncOperationAt`、`lastSuccessfulSyncAt` 和 `lastRejectedSyncAt`。iOS Settings > Storage & Diagnostics 会把这些 Mac 侧计数和本机 cursor、outbox、pending upload、failed upload、missing media download 状态合并展示。`Diagnostics > Sync Doctor` 是优先查看的诊断向导，会把这些原始信号分类成未登录、Mac 不可达、cursor lag、pending outbox、failed uploads、missing media、active server rejected ops、server failed media 和 AI non-ready 等状态，并把首要问题提炼成一个 `Next safe step`，再决定是否给出安全的显式动作：`Sync Now`、`Pull Server Changes`、`Retry Uploads`、`Re-download Missing Media`。`rejectedOperations` 是 Mac 侧原始历史计数；只有本机仍有 pending outbox 且最新 rejected timestamp 晚于最近 successful sync 时，Sync Doctor 才把它视为当前阻塞。原始计数和 timestamps 仍保留在 `Sync Health` 子页。

### Pending Sync 固定排查流程

遇到 iPhone 显示 pending、partial、Waiting、Retrying 或 Sync Health 数字长期不归零时，按同一个顺序排查，不要先从 UI 文案猜原因：

1. 确认 Mac 当前服务真实运行态：

```bash
PRIVATE_MOMENTS_SMOKE_PASSWORD="<read-from-server-env>" npm run doctor:runtime
PRIVATE_MOMENTS_SMOKE_PASSWORD="<read-from-server-env>" npm run doctor:sync
curl -fsS http://127.0.0.1:3210/api/v1/health
```

`doctor:runtime` 应证明 live server、LaunchAgent、3210 listener、SQLite 和本机配置的 remote/private-network health 都指向当前 checkout。`doctor:sync` 应证明 server cursor、server pending/rejected operations、media queue、AI queue 和 maintenance jobs 没有 Mac 侧阻塞。

2. 分开检查 iPhone 到 Mac 的主要 Server URL 和备用私有网络路径：

```bash
tailscale status
tailscale ip -4
curl -fsS --max-time 5 "http://$(tailscale ip -4):3210/api/v1/health"
curl -fsS -i --max-time 10 https://your-private-endpoint.example/api/v1/health
```

如果主要 endpoint 返回 Cloudflare `530` / `1033`，说明 tunnel connector 没有 active connection；先修 tunnel，再让 iPhone 重试。如果使用 Tailscale/private VPN，iPhone 在对应客户端里是 offline 时，不应把问题误判为 sync protocol 失败。

3. 复制真实 iPhone container，看本机 queue 的事实：

```bash
rm -rf .tmp/device-app-library-sync-check
mkdir -p .tmp/device-app-library-sync-check
xcrun devicectl device copy from \
  --device "the paired iPhone" \
  --domain-type appDataContainer \
  --domain-identifier dev.privatemoments.app \
  --source Library \
  --destination .tmp/device-app-library-sync-check \
  --timeout 60
```

读取 Settings 和 SQLite 时优先使用只读快照 URL，避免 live copy 的 lock 误导：

```bash
plutil -p .tmp/device-app-library-sync-check/Preferences/dev.privatemoments.app.plist \
  | rg "server|Server|Sync|sync|device|Device|cursor|Cursor|reachable|Reachable"

DB=".tmp/device-app-library-sync-check/Application Support/PrivateMoments/private-moments.sqlite"
sqlite3 "file:$DB?mode=ro&immutable=1" \
  "SELECT status, type, COUNT(*) FROM outbox_operations GROUP BY status, type ORDER BY status, type;"
sqlite3 "file:$DB?mode=ro&immutable=1" \
  "SELECT uploadStatus, kind, COUNT(*) FROM local_media WHERE deletedAt IS NULL GROUP BY uploadStatus, kind ORDER BY uploadStatus, kind;"
sqlite3 "file:$DB?mode=ro&immutable=1" \
  "SELECT uploadStatus, COUNT(*) FROM local_checkin_media WHERE deletedAt IS NULL GROUP BY uploadStatus ORDER BY uploadStatus;"
sqlite3 "file:$DB?mode=ro&immutable=1" \
  "SELECT (SELECT COUNT(*) FROM outbox_operations WHERE status IN ('pending','failed')) AS app_pending_changes,
          (SELECT COUNT(*) FROM local_media m JOIN local_posts p ON p.id=m.postId
             WHERE m.uploadStatus IN ('pending','failed') AND m.deletedAt IS NULL AND p.deletedAt IS NULL)
        + (SELECT COUNT(*) FROM local_checkin_media m
             JOIN local_checkin_entries e ON e.id=m.entryId
             JOIN local_checkin_items i ON i.id=e.itemId
             WHERE m.uploadStatus IN ('pending','failed')
               AND m.deletedAt IS NULL AND e.deletedAt IS NULL AND i.deletedAt IS NULL) AS app_pending_uploads;"
```

4. 解释 pending 类型：

- `lastSyncCursor` 低于 Mac `server_changes.MAX(version)`：优先判断为远端变更未拉取，用 `Pull Server Changes` 或 `Sync Now` 验证。
- `outbox_operations` 有 pending/failed：这是本机 metadata 未发送或被拒绝；看 `type`、`attemptCount`、`lastError`，再查 server `sync_operations` 是否收到同一个 `op_id`。
- app 口径 `pending_uploads > 0`：这是活跃 moment 或 check-in 附件未上传；查本机文件是否存在，再看 server upload stage logs。
- raw `local_media` 有 pending 但 app 口径 `pending_uploads = 0`：通常是已删除父 moment 的遗留本地行，不是当前活跃上传阻塞；后续可以用清理迁移或维护脚本收口。
- Mac 端 `doctor:sync` 全绿，但 iPhone 有 pending 且 `attemptCount = 0`：通常是 iPhone 还没有成功连到任何 server candidate，先修当前配置的 Server URL 或 fallback endpoint，不要先改 sync protocol。

iOS 无签名编译检查：

```bash
cd ios
xcodegen generate
xcodebuild -project PrivateMoments.xcodeproj \
  -scheme PrivateMoments \
  -destination generic/platform=iOS \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 真实 iPhone 数据验证

复制 app 的 Library container：

```bash
rm -rf .tmp/device-app-library-check
mkdir -p .tmp/device-app-library-check
xcrun devicectl device copy from \
  --device "the paired iPhone" \
  --domain-type appDataContainer \
  --domain-identifier dev.privatemoments.app \
  --source Library \
  --destination .tmp/device-app-library-check \
  --timeout 60
```

检查 sync state：

```bash
plutil -p .tmp/device-app-library-check/Preferences/dev.privatemoments.app.plist
sqlite3 '.tmp/device-app-library-check/Application Support/PrivateMoments/private-moments.sqlite' \
  'SELECT COUNT(*) FROM local_posts WHERE deletedAt IS NULL;'
sqlite3 '.tmp/device-app-library-check/Application Support/PrivateMoments/private-moments.sqlite' \
  'SELECT COUNT(*) FROM local_comments WHERE deletedAt IS NULL;'
```

如果怀疑 iPhone 没拉到 Mac 上已经生成的 server changes，先在 iPhone 打开 Settings > Storage & Diagnostics 并点右上角 refresh。这个页面只做只读诊断：加载本机状态和 Mac `/api/v1/admin/status`，显示 `This iPhone cursor`、`Mac change version` 和落后数量；它不会隐式启动完整同步。若显示明显落后，再点 `Pull Server Changes` 或 `Sync Now` 明确拉取。Settings 根页的 `Sync Now` 转圈只表示用户手动触发的同步；后台空闲同步不应该让它一直显示 `Syncing`。也可以复制 container 后手动比较两端 cursor：

```bash
plutil -p .tmp/device-app-library-check/Preferences/dev.privatemoments.app.plist | grep lastSyncCursor
sqlite3 server/prisma/dev.db 'SELECT MAX(version) FROM server_changes;'
```

开发时如果 `DATABASE_URL` 或 `PRIVATE_MOMENTS_DATA_DIR` 指向其他 SQLite 文件，第二条命令要改成对应 server database path。健康状态下，iPhone `lastSyncCursor` 应追上 server `MAX(server_changes.version)` 或 `/api/v1/admin/status.sync.latestServerChangeVersion`；如果明显落后，先在 app 里运行 `Pull Server Changes` 或 Settings > Sync > Sync Now，再重新复制 container 检查。

Media recovery 常用检查：

```sql
SELECT COUNT(*) AS missing_visible_media
FROM local_media m
JOIN local_posts p ON p.id = m.postId
WHERE m.uploadStatus='uploaded'
  AND (
    (m.kind='image' AND m.remoteCompressedPath IS NOT NULL AND m.localCompressedPath = '')
    OR (m.kind='video' AND m.remoteThumbnailPath IS NOT NULL AND (m.localThumbnailPath IS NULL OR m.localThumbnailPath = ''))
  )
  AND m.deletedAt IS NULL
  AND p.deletedAt IS NULL;
```

Cache recovery 健康状态下，`missing_visible_media` 应为 `0`。语音和视频完整文件默认按播放需求下载，不纳入这个缺失缩略图/poster 检查。

Legacy audio/video transcription metadata 常用检查：

```sql
SELECT id, kind, transcriptionStatus, length(transcriptionText) AS transcript_length, transcriptionError
FROM local_media
WHERE kind IN ('audio', 'video')
ORDER BY updatedAt DESC
LIMIT 10;
```

这些字段用于旧客户端、历史数据兼容，以及当前 iPhone-direct AI path 的 private local transcript metadata。新 iOS 不会上传 `transcriptionText` 给 Mac server，也不会把 transcript 作为 timeline 或 bottom sheet 的可见回退内容。排查时不要把完整私人转写正文贴进日志或聊天，只记录长度、状态和 media id。

AI summary 常用检查：

```sql
SELECT id, media_id, status, document_title, one_liner, json_array_length(document_blocks_json) AS block_count,
       provider, model, input_transcript_length, error_code, deleted_at
FROM ai_summaries
ORDER BY updated_at DESC
LIMIT 10;
```

本机 iPhone container 侧：

```sql
SELECT id, mediaId, status, documentTitle, oneLiner, provider, model,
       inputTranscriptLength, errorCode, deletedAt
FROM local_ai_summaries
ORDER BY updatedAt DESC
LIMIT 10;
```

排查时只记录 id、状态、document block 数量、provider/model、错误码和 transcript length。不要复制私人 transcript 正文或 AI summary 正文。

Smart Tags 常用检查：

```sql
SELECT id, type, name, is_default, is_archived, ai_usable_as_primary
FROM tags
ORDER BY type, is_default DESC, name;

SELECT tag_id, COUNT(*) AS active_assignments
FROM post_tags
WHERE deleted_at IS NULL
GROUP BY tag_id
ORDER BY active_assignments DESC;

SELECT source, COUNT(*)
FROM post_tags
WHERE deleted_at IS NULL
GROUP BY source;

SELECT p.id AS post_id, m.id AS media_id, s.status,
       p.ai_tag_processed_at,
       COUNT(pt.id) AS active_tags
FROM posts p
JOIN media m ON m.post_id = p.id
LEFT JOIN ai_summaries s ON s.media_id = m.id AND s.deleted_at IS NULL
LEFT JOIN post_tags pt ON pt.post_id = p.id AND pt.deleted_at IS NULL
WHERE m.kind = 'audio' AND p.deleted_at IS NULL
GROUP BY p.id, m.id, s.status, p.ai_tag_processed_at
ORDER BY p.created_at DESC
LIMIT 10;

-- 多段普通 audio moment 应有多条 media，但 ai_summaries 只锚到第一条 audio media。
SELECT p.id AS post_id,
       COUNT(m.id) AS audio_media_count,
       MIN(m.sort_order) AS first_sort_order,
       COUNT(s.id) AS summary_count,
       GROUP_CONCAT(s.status) AS summary_statuses
FROM posts p
JOIN media m ON m.post_id = p.id AND m.kind = 'audio' AND m.deleted_at IS NULL
LEFT JOIN ai_summaries s ON s.media_id = m.id AND s.deleted_at IS NULL
WHERE p.deleted_at IS NULL
GROUP BY p.id
HAVING audio_media_count > 1
ORDER BY p.created_at DESC
LIMIT 10;
```

本机 iPhone container 侧：

```sql
SELECT id, type, name, isDefault, isArchived, aiUsableAsPrimary
FROM local_tags
ORDER BY type, isDefault DESC, name;

SELECT tagId, COUNT(*) AS active_assignments
FROM local_post_tags
WHERE deletedAt IS NULL
GROUP BY tagId
ORDER BY active_assignments DESC;

SELECT COUNT(*) FROM local_tag_aliases WHERE deletedAt IS NULL;
```

默认主标签应至少有 6 条：`日记`、`想法`、`学习整理`、`情绪`、`碎碎念`、`复盘`，并保持 `is_default=1`、`ai_usable_as_primary=1`。AI 自动标签只应出现在新 audio moment 的首次 ready summary 之后；video/image/text 没有 AI 自动标签。短音频/短 transcript 通常只应有 1 个 topic，只有多主题且高置信度时才保留多个。排查时只记录 tag id/name/type/count/source、AI 建议置信度数组、`primarySkippedReason` 和 skipped reason，不复制 post 正文、comment、transcript 或 summary 正文。server 正常日志里的 `ai.tags_processed` 可用于区分 `primary_no_suggestion`、`primary_low_confidence`、`primary_no_matching_tag`、`no_suggestions`、`low_confidence`、`user_edited`、`already_processed`、`force_regenerate`、`non_audio_media` 和已应用标签等路径。Settings > Tags 的 `Edit` 可批量 Archive/Merge Topic，也可批量 Restore/Delete Archived tags。

## Troubleshooting

### Login Fails With App Transport Security

优先检查 Settings 里的 Server URL。公开版不要求固定 Cloudflare 或 Tailscale；只要该 URL 能从 iPhone 到达 Mac server 即可。如果临时切到 `http://<private-ip>:3210`，ATS 报错通常说明请求在 iOS 侧被拦截，尚未到达 Mac server；此时 server logs 和 `devices.last_seen_at` 通常不会变化。

私有网络路径可使用 Tailscale Serve HTTPS：

```bash
tailscale serve status
```

临时把 iOS Server URL 改为输出里的 `https://<tailscale-host>`。当前 Debug app 也通过 `NSAllowsArbitraryLoads` 允许开发期 HTTP fallback；不要同时依赖 `NSAllowsLocalNetworking` 来覆盖 Tailscale `100.x` 地址，因为它不一定被 ATS 判定为 local networking。

### Duplicate Devices

重复登录应该复用 `deviceKey`。如果历史上已经产生 duplicate rows，可以谨慎使用 Mac Admin 的 device cleanup。不要撤销当前活跃 iPhone token，除非你准备重新登录。

### Sync Shows Empty Timeline After Login

检查 app preferences 里的 `lastSyncCursor`。iOS recovery 会在本地数据库为空或一次性 recovery flag 尚未应用时，把 cursor 重置为 `0`。sync 完成后，`lastSyncCursor` 应该匹配 server 最新的 `server_changes.version`。

### Images Do Not Load

检查 server logs 里的 `media.batch_download`。iOS 现在用 batch thumbnail JSON 做 remote cache recovery。手机数据库中 `missing_visible_media` 应为 `0`。

### Uploads Stay Pending

iOS 会逐个上传 media，并在上传前压缩图片。如果大文件上传失败或 Tailscale 连接中断，item 会留在本地 queue，并由 sync retry 调度器按 backoff 延迟重试。上传队列优先处理 `pending`，再处理 `failed`，避免一个旧失败项挡住新语音。iOS 上传 audio/video/document 时会先写临时 multipart 文件，再用 file upload 交给 `URLSession`，避免把完整大文件 body 常驻内存。普通 New Moment 的多段 audio 会作为同一 post 下多条 `audio` media 顺序上传，每段 `compressed` 上传会带 `audioGroupCount`；iPhone-direct AI summary 不依赖 server 等齐后排队。`document` 当前只支持 PDF，上传为 `kind=document`、`mimeType=application/pdf`，不生成 thumbnail，也不触发 OCR/AI summary。Check-in 图片和语音走独立 `/api/v1/checkin-media/upload`，但同样计入 iOS Sync Health 的 pending/failed upload 诊断；当前支持 image 和 audio。Check-in audio 的默认 summary 生成在 iPhone 本地 AI path 完成；legacy Mac check-in AI jobs 只用于旧 artifact 和兼容诊断。

先看 Settings > Storage & Diagnostics > Sync Health 里的 pending 或 failed counts。`Retry Uploads` 会把本机 failed media 重新排为 pending，并立即触发一次同步；`Sync Now` 也会处理当前 pending/failed media。然后检查 server logs 里的分阶段上传日志：

- `media.upload_started`: server 已收到 multipart request，并记录 `mediaId`、`postId`、`kind`、`variant` 和预期 body size。
- `media.upload_received`: server 已完整写入临时文件，并完成 size/checksum 统计。
- `media.upload_completed`: server 已把临时文件原子 rename 到最终 media path，并写入 SQLite media record。
- `media.upload_failed`: 上传中断或超时。常见 `errorCode` 是 `client_premature_close` 或 `upload_timeout`。
- `checkin_media.upload_started` / `checkin_media.upload_completed` / `checkin_media.upload_failed`: check-in 照片上传路径，对应字段是 `mediaId`、`entryId`、`kind` 和 `variant`。
- `checkin_ai.summary_started` / `checkin_ai.summary_stage` / `checkin_ai.summary_ready` / `checkin_ai.summary_failed`: legacy check-in audio summary 后台任务，对应字段是 `summaryId`、`entryId`、`mediaId` 和 `errorCode`。当前 iPhone-direct 路径不依赖这些 Mac server jobs；`checkin_ai.summary_skipped_not_configured` 只表示 legacy Mac path 没配 AI provider。

Server 会先写入同目录隐藏 `.tmp` 文件，只有完整收完后才原子 rename 成最终 media 文件；失败时只删除 `.tmp`，不把半截文件当成已上传内容。如果日志里反复出现 `client_premature_close`，通常是 iPhone/Tailscale 连接中断或旧 server 进程卡着上传流。可以重启 Mac server，打开 iPhone app，或在 Settings > Storage & Diagnostics 使用 `Retry Uploads` 让本地 queue 重新上传。

### Comments Do Not Appear After Sync

评论通过 `create_comment` / `delete_comment` 走 `/api/v1/sync`，不走 media upload。先检查 Settings > Advanced Sync 的 Outbox operation counts；这里只应该显示 operation type/count，不显示评论正文。再检查 server `sync_operation` 是否有 rejected `create_comment`，常见原因是父 post 不存在或已删除。iOS 应用远端 comment change 时如果缺父 post，会保留原 cursor 并让本轮 sync 失败，避免静默丢评论。

### Audio Or Video Summary Is Missing

新 iOS 客户端不会生成可见转写结果，也不会把 transcript 上传给 Mac server。当前默认路径是 iPhone 本机对 audio/video 做 on-device transcription，得到 private local transcript 后调用 Settings > AI & Analysis 中配置的 text-analysis provider。普通 New Moment 多段语音会按 `sortOrder` 逐段转写并合并成一份 summary，`local_ai_summaries.mediaId` 使用第一条 audio media。没有 ready summary 时，主时间线不显示 `Summary` 入口、transcript 回退、处理中状态或失败状态。需要排查进度时，优先检查 iPhone Settings > AI & Analysis 的 provider 状态、Keychain API key、fallback cooldown 和 generated artifact 状态；Storage & Diagnostics 里的 legacy Mac/server 区域只用于旧 server-side AI 和同步/存储诊断。

Legacy Mac server-side AI 首次配置本地转写：

```bash
cd server
python3 -m venv .venv
.venv/bin/pip install mlx-whisper
```

排查顺序：

- 确认 iPhone Settings > AI & Analysis 已开启，至少有一个 configured provider profile，且 API key 已写入 Keychain。
- 如果 Settings 显示 `Needs setup` 但 profile 明明存在且 `Test Connection` 成功，优先检查 provider fallback state。当前版本会在读取设置时自动清理旧版本因 `unsupportedResponse` / artifact response unreadable 遗留的误标记 `needs_attention`；再次成功 `Test Connection` 或保存该 profile 仍可作为手动恢复路径。真正缺 key、URL 错误、权限、余额或 model 问题不应被自动清理。
- 确认目标 audio/video 本地文件仍可读；如果完整媒体只在 Mac archive，先按需下载或重新打开本地缓存。
- 检查 provider fallback state：timeout、network、429、5xx、temporarily unavailable 可进入 cooldown 并尝试下一个 provider；401、invalid key、model not found、余额/权限类错误应标记 `needs_attention`，不要无限重试。
- 检查 `local_media.transcriptionStatus`、`transcriptionError` 和 transcript length；排查时只记录长度、状态和 media id，不复制 private transcript。
- 检查 `local_ai_summaries` 的 `status`、`errorCode`、`provider`、`model`、`inputTranscriptLength` 和 document block 数量，不复制 summary 正文。
- 如果 provider `Test Connection` 成功、音频已经 transcribed、transcript length 很短，但 summary 仍报 `ai_provider_response_unreadable` / `The AI provider returned a response Ownlight could not read`，优先判断为 provider artifact JSON shape 问题，而不是 Key/Base URL 问题。当前 iOS decoder 已兼容 `keyPoints`、`documentBlocks.items`、`suggestedTags.topics/tags` 中的 `{text|label|name|title|value}` object-style list items；旧 failed summary 需要显式 Retry/Regenerate 或新建 audio Moment 才会重新生成。若仍失败，只记录 provider/model/errorCode/input length 和结构计数，不复制 provider raw response、private transcript 或 summary 正文。
- Legacy Mac-generated summary 仍可通过 server `ai_summaries`、server logs 和 `ai_summary_updated` sync change 排查；这些路径只用于旧 artifact 或兼容诊断，不是新 iPhone-direct generation 的默认入口。

### AI Summary Is Missing Or Failed

AI summary 没有单独列表页。timeline 只在 ready summary 存在时显示 `Summary ready`；底部 sheet 只显示 ready AI summary。没有 ready summary、处理中、失败或 provider 未配置时，主时间线保持静默，不显示 transcript、`Needs transcript`、`No speech detected` 或 `Summary failed`。

新 audio moment 还有一个可选的标题写回：Settings > Feature Modules > `AI Title Auto-Insert` 默认打开。若首次 ready summary 有有效 `documentTitle`，且该 audio/post 是开启功能之后新建、当前正文没有行首 `# ` 或 `## ` 标题，iOS 会把 `## <title>` 插入正文顶部；CloudKit 路径按 moment metadata 同步，legacy server path 仍可通过 `insert_ai_title` 兼容旧 archive。这个过程只写标题，不写 summary 正文；如果没有出现标题，优先检查该开关、summary 是否 ready、音频是否是旧内容、`document_title` 是否为空/超过 40 字符、正文是否已有标题，以及对应同步队列是否存在失败项。`media-summary-v4` 会要求可识别非空音频有短标题，并在 iOS 侧从 `one_liner` 做 fallback；如果 `document_title` 仍为空，通常表示该音频被判定为内容为空、无法识别、静音或噪音。v4 还会把 active topic tag/alias 词表发给 provider，并在 iOS 落库前复用现有 topic，排查重复 AI topic tag 时先检查 tags/aliases 是否已经存在可复用项。

先确认目标 audio/video media 的本地文件在 iPhone 上可读。新流程不依赖 `media.transcription_text`，也不依赖 Mac server 本地转写；iOS 会先在本机转写媒体文件，并把 private transcript 交给用户配置的 text-analysis provider。多段 audio 的 ready/failed summary 记录只挂在第一条 audio media 上。ready 记录通常应该有非空 `input_transcript_length`。

如果是 provider 配置问题，检查 iPhone Settings > AI & Analysis 的 provider、base URL、model 和 Keychain API key。`Custom` 只按 OpenAI-compatible Chat Completions 构造请求。可以在 Summary sheet 使用 Retry/Regenerate 对本地 artifact 重新生成；真机新发布媒体会在本地保存后自动触发生成。

如果 provider 已配置且连接测试成功，但 summary 仍提示没有可用 provider，通常是旧 fallback `needs_attention` 状态尚未清除，或当前 build 尚未包含 fallback state 自动清理。当前版本会在读取设置时自动清理 artifact-response 类误标记；也可以重新在该 provider 页面运行一次成功的 `Test Connection`，或保存该 profile，作为手动恢复。若随后仍失败，按新的 `errorCode` 判断是否为 unsupported response、quota、model、network 或权限问题。

如果 provider 已配置且连接测试成功，且新的 `errorCode` 是 `ai_provider_response_unreadable`，先确认当前 build 包含 tolerant artifact decoder，再对失败 summary 执行 Retry/Regenerate。这个错误表示 text-analysis provider 的返回不是 app 可落库的 artifact 形状；它通常不是 CloudKit 同步问题，也不是 on-device transcription 失败，更不应该让该 provider 在 Settings 中显示为未配置或需要重新配置。

如果配置了多个 provider profile，iOS 会按用户排序尝试。只有 timeout、network、429、5xx、temporarily unavailable 这类 transient failure 会 fallback 并设置 cooldown；配置/权限/余额/model 类错误会停在 `needs_attention`。不要把任何 provider key 写进 docs 或 tracked config。

如果是 provider/network 失败，检查 server logs 中的 `ai.summary_failed`，只看 `summaryId`、`mediaId`、`provider`、`model`、`inputTranscriptLength` 和 `errorCode`。正常日志不应包含 transcript 或 summary body。

删除 summary 只会软删除 generated metadata，不会删除 post、media、legacy transcript metadata 或 comments。重新生成会覆盖同一个 media 当前 summary record。

新生成的 `media-summary-v4` ready 记录应有 `document_title` / `one_liner` 或非空 `document_blocks_json`。如果旧 summary 没有这些字段但仍有 `overview` / `key_points_json` / `sections_json`，iOS 会走 legacy 渲染；只有重新生成后才会变成 v4 document blocks。

### Legacy Mac Server Section Is Missing

Settings > Storage & Diagnostics 总是显示本机 iPhone usage。只有在 legacy server path 已配置、app 已登录且 `/api/v1/admin/status` 成功时，legacy Mac Server diagnostics section 才会出现。如果 Mac section 被隐藏，检查 server URL、token state 和当前配置的 remote/private-network endpoint reachability；不要把它当作 iCloud 是否可用的判断。

AI Summaries subsection 来自 `/api/v1/admin/status.aiSummaries`，AI Token Usage subsection 来自 `/api/v1/admin/status.aiUsage`，Tags subsection 来自 `/api/v1/admin/status.tags`。Diagnostics > Backup Status 还会读取 maintenance jobs、Archive repository 和 snapshots，用于显示 repository、latest job、latest snapshot、schedule、repository path 和 key file path；备份/恢复/切换执行仍只在 Mac Admin。若 Mac Server 出现但 Backup Status 缺数据，先用 curl 检查 `/api/v1/admin/archive/repository`、`/api/v1/admin/archive/snapshots` 和 `/api/v1/admin/maintenance/jobs` 是否能从当前 server 返回。

### Build Fails With Signing/Profile Errors

打开 Xcode：

```text
Xcode > Settings > Accounts
Target PrivateMoments > Signing & Capabilities
```

选择 personal team，保持 automatic signing，解锁 iPhone，然后重新运行：

```bash
npm run ios:device
```
