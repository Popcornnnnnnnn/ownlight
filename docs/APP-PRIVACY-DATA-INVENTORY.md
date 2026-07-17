# App Privacy Data Inventory

Last updated: 2026-06-08

本文档用于管理 Ownlight 的 App Store App Privacy 数据盘点。它不是法律意见，也不是最终 App Store Connect 填表结果；它的作用是把当前 iOS build 的数据类型、存储位置、传出路径、接收方、用途和待确认项放在一个地方。提交 TestFlight 或 App Store 前，必须按最终 archive build 再复核一次。

## 官方依据

- [Apple App privacy details](https://developer.apple.com/app-store/app-privacy-details/)：App Store Connect 需要说明 app 和第三方 partner 的数据实践；只要数据从设备传出并允许开发者或第三方 partner 在实时请求所需时间之外访问，就属于 Apple 问卷语境中的 `collect`。即使用途只是 App Functionality，也需要判断是否披露。
- [App Store Connect: Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)：iOS app 必须提供 Privacy Policy URL；User Privacy Choices URL 可选；App Privacy 问卷回答要覆盖所有平台和实际数据实践，并保持最新。
- [App Store Connect: App privacy reference](https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy)：Privacy Policy URL 必填，User Privacy Choices URL 是公开可访问的隐私选择说明页。
- [App Review Guidelines 5.1.1 / 5.1.2](https://developer.apple.com/app-store/review/guidelines/)：隐私政策需要说明收集、用途、第三方共享、保留/删除和撤回同意；将个人数据分享给第三方，包括第三方 AI 前，需要清楚披露并取得明确许可。
- [Privacy manifest required reason APIs](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)：使用 required reason API 时，需要在 `PrivacyInfo.xcprivacy` 中声明 API category 和 approved reason。
- [Third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/)：如果提交包包含 Apple 列表内常用第三方 SDK，需要处理对应 SDK privacy manifest 和签名要求。

## 当前 v1 假设

- 第一版无账号、无注册、无登录、无订阅、无 IAP、无广告、无第三方 analytics。
- Public App Store build 不应内置 owner/private fallback endpoint 或其他开发者运营的默认同步 endpoint。该 fallback 只适合 owner/private build，除非后续明确改为开发者托管服务。
- AI 是可选能力，走用户自选 provider 或自托管 endpoint。API key / bearer token 保存在 iPhone Keychain；Base URL、model 和 provider profile 保存在本机设置。
- CloudKit private sync 正在第一阶段 UAT。当前 build 已有 iCloud/CloudKit entitlement、container config、账号状态检查和默认关闭的 `iCloud Sync` 开关；用户开启后会把允许范围内的 Timeline 内容、media metadata/assets、comments、tags、check-ins、AI/review artifacts、部分 app preferences 和 draft metadata 写入用户的 CloudKit private database。提交 TestFlight/App Store 前必须按最终能力重新复核 Privacy Policy、App Privacy Label、Review Notes 和截图文案。
- Mac/self-hosted server 路径仍可作为高级或历史兼容路径存在，但 App Store v1 的默认产品心智是 `This iPhone` local-first。
- Support email 和公开网站用于用户主动联系和阅读政策，不等同于 app 自动收集数据。

## 当前结论

| 项目 | 当前判断 | 说明 |
| --- | --- | --- |
| Tracking | 初步可填 `No tracking` | 当前未发现 App Tracking Transparency、AdSupport、广告 SDK 或跨 app/website tracking 代码。 |
| 第三方 analytics / crash SDK | 当前未发现 | iOS target 未看到 Firebase、Sentry、Amplitude、Mixpanel、PostHog、Crashlytics 等接入。最终 archive 前仍需重新扫。 |
| `NSPrivacyCollectedDataTypes` 空数组 | 有条件成立 | 只有在 public build 无开发者托管 endpoint、无 analytics/crash/upload feedback、AI 仍是用户自选 endpoint 且 App Store Connect 口径不把该 provider 视为开发者第三方 partner 时才成立。 |
| AI provider 数据披露 | 第一刀已实现，提交前复核 | App 内已增加 AI external processing consent gate：首次开启 AI 或旧安装 AI 已开启但未授权时，会说明数据类型和接收方；底层 text AI 和外部 transcription 请求也会在未授权时阻断。最终 App Privacy Label 仍按 archive build 复核。 |
| CloudKit | P0 复核项 | 当前实现已可在用户开启 `iCloud Sync` 后写入 CloudKit private database；如果 CloudKit 进入提交 build，必须用最终 archive 重新更新本 inventory、Privacy Policy、App Privacy Label、App Review Notes 和截图文案。 |
| Privacy manifest | source preflight 通过，最终 archive 仍需复核 | 当前声明 File Timestamp `C617.1` 和 UserDefaults `CA92.1`，未声明 collected data 或 tracking。`npm run doctor:app-store` 未发现 iOS required disk-space API 或明显 user-granted file metadata drift。 |

## 数据盘点

| 数据 / 示例 | 来源 | 本地存储 | 是否离开 iPhone | 接收方 | 用途 | App Privacy Label 初步判断 | 状态 / 行动 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Moment text / title / Markdown | 用户输入、Share Sheet、导入 | SQLite `local_posts`，composer draft 可能短暂在 UserDefaults | 默认不离开；可选同步、导出、AI 生成时离开 | 用户自选 server、Apple CloudKit private database、用户自选 AI provider、用户选择的导出位置 | Timeline、Calendar、search、review、AI summary/review | 若只本地保存，不算开发者 collected；若发到开发者运营服务则可能是 `User Content / Other User Content` | Public build 需避免默认开发者 server；AI 需 explicit consent；CloudKit 最终标签需复核 |
| Comments | 用户输入 | SQLite `local_comments` | 默认不离开；可选同步、导出、AI review 输入时离开 | 用户自选 server、Apple CloudKit private database、用户自选 AI provider、导出位置 | 私密评论、回顾上下文、搜索 | 同上，通常属于 `Other User Content` | 复核 AI review 是否包含 comments；CloudKit 提交前复核 |
| Photos / images / thumbnails | 用户从 Photos、Camera、Share Sheet、Files 添加 | App container media files，SQLite media metadata | 默认不离开；可选 server sync、CloudKit sync、导出时离开；当前 iPhone-direct AI 不把图片视觉内容发给 AI provider | 用户自选 server、Apple CloudKit private database、导出位置 | Timeline media、preview、export/restore | 若上传给开发者或 partner，可能是 `User Content / Photos or Videos` | 保持 AI 不默认分析图片，若未来加入视觉 AI 需重审；CloudKit 提交前复核 |
| Videos / posters / durations | 用户从 Photos、Files、Share Sheet 添加 | App container media files、poster、SQLite media metadata | 默认不离开；可选 server sync、CloudKit sync、导出时离开；转录/摘要只处理音轨或 transcript 路径 | 用户自选 server、Apple CloudKit private database、用户自选 transcription/text provider、导出位置 | Timeline playback、AI summary、archive | 媒体文件上传可能是 `Photos or Videos`；音频转录可能涉及 `Audio Data` | 需在 AI consent 文案中说明音视频摘要可能发送音频或 transcript |
| Audio recordings / durations | 用户录音、Share Sheet、Files | App container M4A、SQLite media metadata | 默认不离开；可选 server sync、CloudKit sync、导出、外部转录/AI 时离开 | 用户自选 server、Apple CloudKit private database、用户自选 transcription/text provider、导出位置 | 播放、转录、AI summary、archive | 外发时可能是 `Audio Data` 和 `Other User Content` | P0: AI/transcription provider disclosure；CloudKit 提交前复核 |
| Local transcripts / original text | iPhone Speech 或用户配置的 transcription endpoint 生成 | 生成流程内存/本地 artifact；导出文档说明不包含 private transcript text | 可能发送给用户自选 text AI provider；当前导出不包含 private transcript text | 用户自选 text AI provider；如启用外部转录，transcription provider 也会收到音频并返回 transcript | 生成 summary、title、topics、review | 可能属于 `Other User Content` 或 `Audio Data` 派生内容 | 明确不要进入 CloudKit / export；最终代码复核 |
| AI summaries / titles / topics / weekly reviews | AI provider 输出、本机生成 | SQLite、本地 review artifacts | 可选同步、CloudKit sync、导出时离开；生成时输入发给用户 provider | 用户自选 server、Apple CloudKit private database、导出位置、用户自选 AI provider | 回顾、整理、搜索、topic tag | 输出本身是 `Other User Content` 或 app-generated content；若开发者不访问则不一定是 collected | 与 AI provider 输入/输出保留边界一起披露 |
| AI provider config | 用户设置 Base URL、model、profile 名称 | UserDefaults / local settings | 不应离开 iPhone；导出包不包含 API key | 无；API 请求时 Base URL 被用于连接 provider | 调用用户选择的 AI provider | 通常不作为 App Privacy data type | 确保不写入 CloudKit / export |
| AI API key / bearer token | 用户输入 | iPhone Keychain | 请求 provider 时作为 Authorization header 发送到对应 provider；不进入 export/CloudKit | 用户选择的 provider endpoint | 鉴权 | Sensitive credential，不应由开发者收集 | P0: final archive/code recheck，确认不进入 CloudKit/export/log |
| Tag / area / alias metadata | 用户编辑、AI 建议、cleanup | SQLite | 可选同步、CloudKit sync、导出时离开；AI topic prompt 可能带 active vocabulary | 用户自选 server、Apple CloudKit private database、导出位置、用户自选 AI provider | 筛选、整理、AI 复用 topic | 通常是 `Other User Content` 或 metadata | 保持不含 primary tag 主流程；AI prompt 词表需在 disclosure 里概括 |
| Check-ins | 用户创建、媒体附件、AI summary | SQLite、media files | 默认不离开；可选同步、CloudKit sync、导出、AI review 时离开 | 用户自选 server、Apple CloudKit private database、导出位置、用户自选 AI provider | 打卡记录、Calendar、review | 可能是 `Other User Content`，若含健康运动内容也不要宣称医疗用途 | 避免 Health/Medical 定位和文案 |
| Calendar / search / filter state | 用户浏览、筛选、搜索 | UserDefaults / in-memory / SQLite metadata | 默认不离开；不做 analytics | 无 | 本机 UI 状态 | 不 collected | 保持不记录搜索 telemetry |
| Device id / device key / device token | 本机生成或 self-hosted sync 登录返回 | UserDefaults + Keychain | 仅在用户配置 sync endpoint 时发送给该 endpoint | 用户自选 server endpoint；owner private build 可能是个人 tunnel | Sync 身份、幂等、授权 | 若开发者托管服务启用，可能是 identifiers；当前 public v1 不应默认启用开发者服务 | Public build fallback 必须复核 |
| Sync cursor / outbox / upload status | 本机同步状态 | SQLite / UserDefaults | 与 Apple Cloud 或 legacy sync endpoint 交互时发送必要操作和 cursor | Apple CloudKit private database、legacy 用户自选 server | 离线优先同步、重试、恢复 | 不作 analytics；若开发者托管服务启用则需披露 | 保持 Settings 低频诊断，不做行为分析 |
| Legacy Server URL / last reachable URL | 用户设置或 private build fallback | UserDefaults / Info.plist build setting | 连接对应 endpoint 时使用 | legacy 用户自选 server；owner private build fallback | Optional legacy sync/diagnostics | 通常不 collected | Public build 不应含个人 fallback，除非明确声明 |
| Local archive export/import package | 用户手动导出/导入 | 临时文件、用户选择保存位置 | 用户手动分享/保存时离开 App container | 用户选择的 Files、iCloud Drive、AirDrop 等目的地 | 本机备份、迁移、验证恢复 | 用户主动导出，不是开发者 collected | 保持导出警告：包内可能有私密内容，未加密 |
| Share Extension import inbox | Share Sheet 导入的 text/url/media | App Group import inbox，随后主 App 消费 | 默认不离开；发布后按 moment 规则处理 | 无，除非用户同步/AI/导出 | 把外部内容保存成 moment | 不 collected | App Group 是本机同组进程共享 |
| Support email content | 用户主动发邮件 | 不在 app 本机持久化，进入邮箱系统 | 是，用户主动发送 | `support@popcornnn.xyz` 转发邮箱 | 支持、反馈 | 通常不是 app 自动 collected；如果改成 in-app feedback upload 需重审 | P1: 如加内置反馈/日志上传，新增 inventory row |
| Public privacy/support website access logs | 用户打开网页 | Cloudflare/网站层面 | 是，浏览器访问网站 | Cloudflare Pages / domain provider | 提供政策和支持页面 | 网站隐私实践，不是 App 自动收集；仍应在网页政策内保持一致 | 提交前检查页面可访问和文案 |
| CloudKit private sync | 用户开启 iCloud Sync 后产生 | CloudKit private database、iPhone SQLite | 是 | Apple iCloud / CloudKit private database | 多设备同步、恢复 | 可能涉及 `User Content`，但由 Apple iCloud 承载；最终 App Privacy 需按 Apple 问卷口径复核 | 第一阶段实现中；当前可写入允许范围内的 Timeline、media assets、comments、tags、check-ins、AI/review artifacts、preferences 和 draft metadata，提交前必须按最终能力复核 |

## 权限盘点

| 权限 / Capability | 当前用途 | Info.plist 文案状态 | App Privacy 影响 | 行动 |
| --- | --- | --- | --- | --- |
| Camera | 拍摄图片 moment | `Ownlight uses the camera to capture images for posts.` | 用户主动拍摄内容，本地保存；不代表收集 | 可保留，提交前做文案自然度复核 |
| Photo Library read | 选择图片/视频加入 moment | `Ownlight uses your photo library to attach images to posts.` | 只应访问用户选择内容，避免全库扫描 | 推荐优先使用 picker 路径；最终 UAT 权限拒绝路径 |
| Photo Library add | 用户选择保存 moment 图片到相册 | `Ownlight saves selected moment images to your photo library when you choose Save.` | 用户主动写入相册 | 可保留 |
| Microphone | 录制音频 moment | `Ownlight uses the microphone to record audio moments.` | 录音是敏感 user content；默认本地 | AI/transcription consent 必须覆盖音频外发 |
| Speech Recognition | iPhone on-device transcription | `Ownlight uses on-device speech recognition to create private local transcripts for AI summaries.` | transcript 是敏感派生内容 | 文案强调 on-device；如 fallback 外部转录需单独 disclosure |
| Local Network | 连接用户配置的 private endpoint | `Moments connects to your configured private endpoint for optional sync and diagnostics.` | 只在用户配置/legacy optional sync 语境下使用 | Public v1 需确认不让 Mac server 成为必填 |
| App Group | Share Extension inbox | Entitlements 仅 App Group | 本机同组共享，不是外发 | 保持 import inbox 清理与导出边界 |
| Background audio | v1 不声明后台音频；语音 Moment / check-in 录音和播放都是前台工作流 | 不设置 `UIBackgroundModes = audio` | 不等于数据收集 | 2026-06-24 App Review 2.5.4 follow-up：移除后台 audio entitlement，不用 screen recording 证明持久后台音频 |
| CloudKit | Opt-in `iCloud Sync` uses the user's private CloudKit database for allowed timeline, media, organization, check-in, review, preference, and draft sync | Settings 已有默认关闭的用户可见同步开关 | CloudKit data sync requires final App Privacy / policy / review-note update before submission | Re-run this inventory on the final archive and keep CloudKit copy aligned with the completed UAT gates |

## 网络与接收方盘点

| 路径 | 当前 build 行为 | 是否默认 | 接收方 | 隐私判断 | 行动 |
| --- | --- | --- | --- | --- | --- |
| Legacy 用户配置 Server URL | `APIClient` 向配置 endpoint 发 health/login/sync/media/admin/status 等请求 | Public v1 不应依赖；owner build 可配置 fallback | 用户自托管 Mac/server 或用户选择的受保护 endpoint | 如果不是开发者运营服务，通常不是开发者 collected；但仍是 user content 离开设备 | App Review Notes 说明核心本地可用；public build fallback 复核 |
| Owner private fallback endpoint | 当前本机 ignored config 可能用于 owner build | 不应进入 public App Store build | 用户自己的 private tunnel / Mac server | 个人 build 方便调试；public build 若内置会改变隐私标签 | P0: Archive 前检查 Info.plist fallback |
| Text AI provider | `AITextAnalysisClient` 调用用户保存的 OpenAI-compatible 或 Anthropic-style endpoint | AI 默认关闭，需用户配置，需 AI external processing consent | 用户选择的 AI provider | 第三方 AI 共享需明确 disclosure 和 consent | 已加 App 内 consent/UI gate；最终决定 App Privacy conservative answer |
| Transcription endpoint | `LocalTranscriptionGatewayClient` 调用用户配置的 `/v1/audio/transcriptions` | 可选高级路径，需 AI external processing consent | 用户选择的 provider/gateway | 音频会发出，敏感度高 | 已在 consent 文案中说明音频或 transcript 会发送；最终 build 复核 |
| Public website | Settings 打开 Privacy/Support URL | 用户主动点击 | Cloudflare Pages / domain | 网站访问不是 app 内容同步；仍有 web log 可能 | 保持页面公开 HTTPS |
| Support email | 用户主动发邮件 | 非默认 | 邮件服务与转发邮箱 | 用户主动联系 | 页面说明联系方式 |
| CloudKit private sync | `iCloud Sync` 开启后把允许范围内的 timeline content/media、comments、tags、check-ins、AI/review artifacts、preferences 和 draft metadata 写入用户 private CloudKit database | Opt-in，默认关闭 | Apple iCloud private database | 私密内容离开 iPhone 到用户 iCloud | 进入提交 build 前必须完成 UAT 并同步更新 Privacy Policy、App Privacy Label、Review Notes 和截图文案 |

## PrivacyInfo.xcprivacy 审计

当前文件：[ios/PrivateMoments/PrivacyInfo.xcprivacy](../ios/PrivateMoments/PrivacyInfo.xcprivacy)

| Key | 当前值 | 证据 / 判断 | 状态 |
| --- | --- | --- | --- |
| `NSPrivacyTracking` | `false` | 未发现 tracking/ads/ATT/AdSupport 路径 | 可保留，最终 archive 复核 |
| `NSPrivacyTrackingDomains` | 空 | 未发现 tracking domain | 可保留 |
| `NSPrivacyCollectedDataTypes` | 空 | 仅在 public v1 无开发者收集数据时成立 | P0: 根据 AI/CloudKit/fallback 最终口径复核 |
| File Timestamp | `NSPrivacyAccessedAPICategoryFileTimestamp` + `C617.1` | 代码读取 app/app group container 内文件 metadata，如 import inbox、archive/media/storage stats | 当前 reason 合理；最终 archive 前需确认是否有 user-granted Files URL metadata 读取需要 `3B52.1` |
| UserDefaults | `NSPrivacyAccessedAPICategoryUserDefaults` + `CA92.1` | 代码用 UserDefaults 保存 app 自身设置和 UI 状态 | 当前 reason 合理 |
| Disk Space | 未声明 | 未发现 iOS 使用 Apple required disk-space API，如 `volumeAvailableCapacity*`、`systemFreeSize`、`statfs` | 当前不需要；如果 Storage 页面改为读系统可用空间，需要新增 |
| 第三方 SDK manifest | 未发现 iOS 第三方 SDK | 当前 iOS target 未看到常见第三方 analytics/crash/ad SDK | 最终 archive 复核 |

## App Privacy Label 草案

完整可填表草案集中维护在 [APP-STORE-SUBMISSION-DRAFT.md](APP-STORE-SUBMISSION-DRAFT.md)。

### 推荐主口径，前提是最终 build 满足所有条件

- `Do you or your third-party partners collect data from this app?`：倾向 `No, we do not collect data from this app`。
- `Tracking`：`No`。
- 前提条件：
  - Public App Store build 不内置开发者运营的同步 server fallback。
  - 不接入 analytics、crash reporting、ads、tracking、in-app feedback log upload。
  - AI 仍是用户自选 provider，且 App Store Connect/法律口径认为这不是开发者或第三方 partner 替用户收集数据。
  - CloudKit private sync 已完成 M017 第一阶段真实设备 UAT；提交前仍需按 App Store Connect 问卷复核 Apple CloudKit private database 是否影响 `collect` 判断。

### 保守备选口径，适用于 AI provider 被视作第三方数据接收方时

如果最终决定把用户自选 AI provider 也作为 App Privacy Label 的数据接收方披露，建议至少考虑：

- `User Content / Other User Content`：moment text、comments、transcripts、review input、AI prompt context。
- `User Content / Audio Data`：外部 transcription endpoint 或音频摘要路径会发送原始音频时。
- `User Content / Photos or Videos`：仅在未来做视觉 AI、默认上传媒体到开发者服务，或将照片/视频内容发给第三方时选择；当前 iPhone-direct AI 不默认发送图片视觉内容。
- Purpose：`App Functionality`。
- Linked to user：需要按 provider/account/API key 口径判断；如果 provider 由用户自己选择和持有账号，Ownlight 开发者通常无法把数据 linked 到开发者侧用户身份，但 Apple 审核口径仍需保守确认。
- Tracking：仍应是 `No`，除非接入跨 app/website tracking 或广告用途。

## P0 上架前动作

| Done | Gate | 说明 |
| --- | --- | --- |
| [x] | Final archive fallback proof | 2026-06-11 已导出并复核 App Store IPA：主 App bundle id、Share Extension bundle id、App Group、Production CloudKit container 和 `get-task-allow=false` 正常；未使用开发者托管 fallback endpoint。 |
| [x] | AI explicit consent | 2026-06-02 已新增 `AI Privacy Permission` sheet、Settings > AI & Analysis > `Privacy Permission` 状态入口，以及底层 text AI / external transcription consent guard。提交前仍需在最终 archive 上复核文案、App Privacy Label 和截图是否一致。 |
| [x] | App Privacy Label draft | 2026-06-08 已在 `docs/APP-STORE-SUBMISSION-DRAFT.md` 写入主口径和 AI provider 保守备选。最终填写仍需以 archive privacy report 和 App Store Connect UI 为准。 |
| [x] | App Privacy Label final answer | 2026-06-11 已在 App Store Connect 发布主口径 `Data Not Collected`。若未来加入开发者托管 AI、analytics/crash upload、账号、反馈上传或默认开发者服务，必须重新填写。 |
| [x] | Source build fallback 复核 | `npm run doctor:app-store` 检查 tracked `Public.xcconfig` 和 `ios/project.yml` 默认 fallback 均为空；ignored owner `.env.local` 已清空 fallback，并重新生成 `ios/Config/Local.xcconfig`。最终 archive 前仍可重跑同一命令。 |
| [x] | PrivacyInfo source preflight | `npm run doctor:app-store` 检查当前 source manifest：tracking=false、tracking domains 空、collected data 空、FileTimestamp `C617.1` 和 UserDefaults `CA92.1` 存在。上传前仍应看 archive privacy report / App Store Connect feedback。 |
| [x] | User-granted file metadata source check | `npm run doctor:app-store` 未发现明显外部 import/share 路径在复制进 app container 前读取 file size / creation date / attributesOfItem；当前 Share Import 的 `contentModificationDateKey` 读取发生在 App Group inbox，继续由 `C617.1` 覆盖。 |
| [x] | Permission copy source review | `npm run doctor:app-store` 检查 Camera、Photos、Microphone、Speech、Local Network purpose strings 非空且非 placeholder；真实拒绝路径仍属最终 UAT。 |
| [x] | CloudKit source re-inventory | 当前 inventory 已覆盖 `iCloud Sync` 可选写入 CloudKit private database 的内容范围；最终 App Privacy Label、Review Notes 和截图仍需按提交 archive 复核。 |
| [x] | No SDK drift source scan | `npm run doctor:app-store` 未发现 known analytics/crash/ad/tracking SDK package dependency 或 iOS import。最终 archive 前重跑。 |

## P1 维护规则

- 如果新增 in-app feedback、自动 crash report、diagnostic upload、analytics、push notification、Sign in with Apple、IAP、developer-hosted AI、default cloud sync、location、contacts、HealthKit 或视觉 AI，必须先更新本 inventory。
- 如果新增任何第三方 SDK，必须先检查 Apple third-party SDK requirements、SDK privacy manifest 和 App Privacy Label 影响。
- 如果 `Storage & Export` 开始读取系统可用磁盘空间，而不是只统计 app container 文件大小，需要补充 Disk Space required reason。
- 如果导出包加入 encryption、password、E2EE 或第三方 crypto library，需要同步 export compliance 和隐私/安全文案。
