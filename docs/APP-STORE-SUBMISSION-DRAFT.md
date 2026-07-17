# App Store 提交草案

Last updated: 2026-07-17

本文档把 App Store Connect 可填写内容集中成一份草案。正式提交前，仍以最终 archive build、App Store Connect UI 和 Apple 最新官方要求为准。

## 当前提交口径

- 第一版免费，无 IAP、无订阅、无广告。
- 无 Ownlight 账号、无注册、无登录；核心功能首次打开即可本地使用。
- v1 不做 TestFlight 分发；完成最终本机/真机 UAT 后直接提交 App Store，审核通过后手动发布。
- 默认 local-first：内容先保存在 iPhone 本机 SQLite。
- `iCloud Sync` 是用户可选开关，使用同一 Apple Account 的 private CloudKit database。
- AI 默认关闭；用户自行配置 AI provider/Base URL/API key，并在首次外发前确认 AI external processing consent。
- Public App Store build 不内置开发者托管 sync endpoint、analytics、crash SDK、广告 SDK 或 tracking SDK。

## App Privacy Label Draft

推荐主口径：

| App Store Connect 问题 | 草案答案 | 依据 |
| --- | --- | --- |
| Do you or your third-party partners collect data from this app? | No, we do not collect data from this app | 当前 public build 不接入开发者服务器、analytics、crash upload、ads、tracking 或 in-app feedback upload；用户内容默认留在设备；iCloud Sync 写入用户 private iCloud database；AI 是用户自选 provider。 |
| Tracking | No | 未发现 ATT、AdSupport、广告 SDK、tracking SDK 或跨 app/website tracking 路径。 |
| Data linked to user | Not applicable under the no-data-collected answer | 无开发者收集数据时无需逐项回答。 |

保守备选口径：

如果 Apple/App Review 或法律口径要求把用户自选 AI provider 也作为第三方数据接收方披露，则不要使用 `No data collected`。改为选择以下数据类型：

| Data type | When to select | Purpose | Tracking |
| --- | --- | --- | --- |
| User Content / Other User Content | 文本 moment、comments、transcripts、review input 或 AI prompt context 发送到用户配置的 text-analysis provider | App Functionality | No |
| User Content / Audio Data | 外部 transcription endpoint 或音频摘要路径发送原始音频 | App Functionality | No |
| User Content / Photos or Videos | 当前不选；只有未来做视觉 AI、开发者托管媒体上传或把照片/视频内容发给第三方时才选 | App Functionality | No |

当前建议：先按主口径准备；在 App Store Connect 最终填写前，用最终 archive 的 privacy report 和 AI/iCloud 文案再复核一次。

## Export Compliance Draft

当前判断：

- App 使用 HTTPS/TLS、CloudKit、Keychain 和 iOS 系统存储保护等 Apple 操作系统能力。
- iOS app 代码未发现 `CryptoKit`、`CommonCrypto`、自研 AES/RSA/ChaCha、非标准加密或第三方 crypto library。
- Share Extension 不执行网络同步或独立加密；只写 App Group import inbox。
- 当前 archive 口径可使用 exempt encryption answer，并在主 App `Info.plist` 设置 `ITSAppUsesNonExemptEncryption = false`。

App Store Connect 问答草案：

| 问题 | 草案答案 |
| --- | --- |
| Does your app use encryption? | Yes, because it uses Apple OS networking/storage security such as HTTPS/TLS, CloudKit and Keychain. |
| Does your app use non-exempt encryption? | No. Current code only uses Apple operating system encryption/security capabilities and no proprietary or non-standard cryptography. |
| Export compliance documentation upload | Not expected for current build. If App Store Connect asks differently, pause and review before submission. |

如果后续加入端到端加密、自研加密、第三方 crypto library、加密导出包或 password-protected archive，需要重新判断。

## App Information Draft

| Field | Recommended draft | Notes |
| --- | --- | --- |
| App name | Ownlight | App Store 商店名；中英文 metadata 统一使用同一个品牌名。 |
| Home screen display name | Ownlight | iOS 图标下的短名，来自 `PRIVATE_MOMENTS_IOS_DISPLAY_NAME`；和商店名保持一致。 |
| Subtitle zh-Hans | 自己的私密时间线 | 9 个中文字符；解释定位，不把名称写长。 |
| Subtitle en | Your private timeline | 21 chars。 |
| Primary category | Lifestyle | 已确认。 |
| Secondary category | Productivity | 已确认。 |
| Primary language | English | `1.1` 使用 English-first metadata 和 English screenshots；保留 zh-Hans localization，但海外默认商品页以 English 为主。 |
| Territories | Overseas first, China mainland paused | 2026-07-02 已临时移除 China mainland，改为 174 countries or regions 可用；恢复中国大陆前先处理 ICP/上架材料策略。 |
| Marketing URL | Leave blank if App Store Connect allows | 当前使用 Support/Privacy URL 即可。 |
| Privacy Policy URL zh-Hans | https://private-moments.popcornnn.xyz/privacy/zh-Hans | 已部署。 |
| Privacy Policy URL en | https://private-moments.popcornnn.xyz/privacy/en | 已部署。 |
| Support URL | https://private-moments.popcornnn.xyz/support | 已部署且有真实联系邮箱。 |
| SKU | private-moments-ios-v1 | 内部标识，不对用户显示；创建后不可改。 |
| Copyright | 2026 Weizhi Wang | App Store Connect 会自动显示 copyright symbol。 |
| Content Rights | No third-party content included by the app | 用户可自行保存自己的内容；App 本身不内置第三方媒体内容。 |
| Made for Kids | No | 不是儿童类 App。 |
| App Preview | None for v1 | App Preview 是可选项；v1 先用截图，不增加视频制作和本地化成本。 |
| Release mode | Manual release after approval | 不走 TestFlight；审核通过后手动发布，避免自动上线。 |

## Version 1.1 Draft

- Marketing version: `1.1`
- Build: `4`
- Store direction: English-first presentation for the existing overseas availability.
- Source release: `v1.1.0` under MIT; no signed IPA in GitHub Release.

### What's New

```text
Ownlight now has an English-first App Store presentation, with clearer screenshots and descriptions for international users. This release also refreshes setup, privacy, and release documentation while keeping the local-first timeline, optional iCloud sync, and user-configured AI experience unchanged.
```

## App Store Connect Entry Status

2026-07-17 `1.1 (4)` English-first submission checkpoint：

- `Archive / upload`：正式 Release archive 已成功生成并上传；App Store Connect 已识别并绑定 build `1.1 (4)`。
- `Primary language`：App Information 已从 `Chinese (Simplified)` 切换为 `English (U.S.)`；English subtitle 继续使用 `Your private timeline`。
- `English screenshots`：English (U.S.) 的 iPhone `6.5" Display` 已保存 6 张 `1284 x 2778` PNG，顺序为 Timeline、AI summary、Markdown detail、Calendar review、Topic areas、iCloud sync。源文件位于 `docs/assets/screenshots/app-store-en/`。
- `Age Rating`：补答 2026 年新增的 Social Media 问题；Ownlight 不包含 Social Media、公开 UGC 分发或用户间 Messaging，计算结果仍为 `4+`。
- `Review Notes`：已更新为 build `1.1 (4)`，继续明确无账号、无 IAP、AI provider 由用户自行配置、录音与播放仅在前台运行。
- `Submission`：已执行 `Add for Review` 和 `Submit for Review`；截至 2026-07-17，App Store Connect 状态为 `1.1 Waiting for Review`。

2026-06-11 已完成的录入/上传：

- `App Privacy`：已发布 final answer，当前 App Store Connect 显示 `Data Not Collected`，Privacy Policy URL 为 `https://private-moments.popcornnn.xyz/privacy/zh-Hans`。
- `Build`：已用正式 identity 生成 Release archive，导出并上传 App Store Connect build `1.0 (2)`；该 build 于 2026-06-24 因 Guideline 2.5.4 / background audio entitlement 被打回。下一次重提使用 build `1.0 (3)`。
- `Included Assets`：App Store Connect build 区域已显示 `App Icon`，说明图标随上传 build 被识别。
- `Archive/IPA verification`：`1.0 (2)` 曾复核导出 IPA 中主 App、Share Extension、App Group 和 iCloud container 均使用匹配的 owner 专用 identifiers，CloudKit environment 为 `Production`，`get-task-allow=false`，版本号为 `1.0 (2)`。具体 signing identifiers 不进入公开源码快照。`1.0 (3)` 还需重新复核，并确认不含 `UIBackgroundModes = audio`。

2026-06-21 已完成的 App Store Connect live setup：

- `Age Rating`：问卷已保存，App Information 页面显示 global age rating `4+`。
- `Pricing`：已设置为 free / `$0.00`。
- `Availability`：2026-06-21 曾设置为 China mainland only；2026-07-02 因 ICP/中国大陆可见性策略未定，已改为 174 countries or regions 可用、China mainland `Not Available`，页面提示变更最多 24 小时生效。
- `Mac / Vision distribution`：Apple Silicon Mac 和 Apple Vision Pro 可用性已关闭。

2026-06-10 已完成的录入：

- `App Information`：App name 更新为 `Ownlight`；English subtitle 为 `Your private timeline`；primary language 为 `Chinese (Simplified)`；category 为 primary `Lifestyle`、secondary `Productivity`。保存后 App Store Connect 顶部 App 菜单已显示 `Ownlight`。
- `iOS App Version 1.0`：zh-Hans / English description 和 keywords 已按本草案录入；App Review Notes 已替换为 `Ownlight` 口径；release mode 保持 manual release after approval。
- `Support URL` 继续使用现有公开站点 `https://private-moments.popcornnn.xyz/support`。该域名目前仍沿用旧项目路径，但页面内容已使用 `Ownlight` 品牌。

2026-07-02 发布后调整：

- `Availability`：live `1.0 Ready for Distribution` 已从 China mainland-only 改为海外 174 countries/regions，China mainland 取消勾选。
- `English screenshots`：已生成 6 张 `1284 x 2778` PNG，路径为 `.tmp/ui-review/app-store-screenshots/iphone-6-5-en/`。
- `Media Manager`：English (U.S.) 仍显示 `Using Chinese (Simplified) 6.5" Display`，没有上传按钮或 file input；如果要真正替换截图，需要下一版本或 App Store Connect 重新开放可编辑状态。
- `App Information`：live page 仍显示 primary language `Chinese (Simplified)`，English subtitle 未暴露可编辑控件；下一版本再统一 English-first 口径。

提交状态：

- 2026-06-21 22:08 CST 已提交审核。
- 2026-06-24 / 2026-06-25 分别处理 2.5.4 和 3.1.1 rejection。
- 2026-06-28 Apple 批准 build `1.0 (3)`，owner 已手动发布。
- v1 当前 App Store Connect 状态为 `1.0 Ready for Distribution`。
- 2026-07-17 已提交 English-first build `1.1 (4)`；当前状态为 `1.1 Waiting for Review`，release mode 保持 manual release after approval。

## Description Draft zh-Hans

Ownlight 是一个只给自己看的私密时间线。你可以像发布到时间线一样轻松地记录生活片段，但这里没有好友关系、公开评论、互动压力或社交通知。

内容会先保存在这台 iPhone 上。没有网络时，你仍然可以继续记录、浏览和搜索；需要多设备使用时，可以在设置中开启 iCloud Sync，把资料同步到使用同一 Apple Account 的设备。

你可以记录文字、照片、语音、视频和从 Share Sheet 导入的内容，也可以用评论、收藏、置顶、标签、搜索和 Calendar 回顾整理自己的生活片段。

AI 功能默认关闭。只有在你主动配置自己的 AI provider，并确认外部处理说明后，Ownlight 才会发送必要内容用于生成语音/视频摘要、标题和主题标签。API key 保存在 iPhone Keychain 中，不进入 iCloud Sync 或导出包。

Ownlight 不提供账号系统，不做公开社交，不包含广告、订阅或内购。

## Description Draft en

Ownlight is a quiet private timeline for your own life. You can capture everyday moments as easily as posting to a timeline, but there is no audience: no followers, no public comments, no engagement pressure, and no social notifications.

Your moments are saved on this iPhone first. You can keep writing, browsing, and searching even without a network connection. If you choose to, you can turn on iCloud Sync in Settings to sync your private library across devices signed in to the same Apple Account.

You can capture text, photos, audio, videos, and Share Sheet imports, then organize them with comments, favorites, pins, tags, search, and Calendar reviews.

AI is off by default. Ownlight only sends content to an AI provider after you configure your own provider and confirm the external processing notice. API keys stay in the iPhone Keychain and are not included in iCloud Sync or export packages.

Ownlight has no account system, no public social network, no ads, no subscriptions, and no in-app purchases.

## Keywords Draft

zh-Hans, under 100 bytes target:

```text
日记,手账,记录,时间线,私密,生活,语音,相册,回顾,同步
```

English, under 100 bytes target:

```text
journal,diary,timeline,private,notes,memories,audio,photos,review,sync
```

## Age Rating Draft

Current expected answers:

- No gambling, contests, loot boxes, unrestricted web access, user-generated public content, dating, medical treatment, regulated health claims, realistic violence, sexual content, alcohol/tobacco/drug references, or horror content provided by the app.
- App contains user-created private content only.
- Not Made for Kids.
- Not Medical / Health & Fitness positioning.

Final App Store Connect result as of 2026-06-21: global age rating `4+`.

## App Review Notes Draft

```text
Ownlight requires no account, registration, login, subscription, in-app purchase, or demo credentials.

Core test path:
1. Launch the app.
2. Tap Start on the first-launch welcome screen if shown.
3. Create a text moment from the compose button.
4. Add a photo, audio recording, or video moment if device permissions are available.
5. Add a comment, favorite/pin a moment, search the timeline, and open Calendar.
6. Open Settings > iCloud to verify that iCloud Sync is optional and off until the user enables it.
7. Open Settings > AI & Analysis to verify that AI is optional and requires user-provided provider configuration plus explicit external processing consent.
8. Open Settings > Storage & Export to review local export/import.

The app is local-first. User content is stored on the iPhone by default. Optional iCloud Sync uses the user's private CloudKit database for devices signed in to the same Apple Account. Ownlight does not provide a developer-hosted account or social network.

AI features are optional. The app does not provide a developer-hosted default AI service. Users configure their own compatible provider endpoint and API key. API keys stay in the iPhone Keychain and are not included in iCloud Sync or export packages.

Permissions:
- Camera and Photos are used only when the user adds media to a moment.
- Microphone is used to record audio moments.
- Speech Recognition is used for local transcription that supports optional AI summaries.
- Local Network is only for optional user-configured private endpoints / legacy diagnostics, not for a required server.
- Audio recording and playback are foreground-only. The app does not declare persistent background audio.
```

## Screenshot Plan

v1 live version 先上传了 zh-Hans。`1.1` 使用已经准备好的 English localization 图片。

1. Timeline with mixed text/photo/audio moment and simple private feed feel.
2. Compose screen showing text plus media actions.
3. AI summary sheet for an audio/video moment, with provider copy not overemphasized.
4. Calendar / Weekly Review view.
5. Tags or Search filter view showing organization.
6. Settings > iCloud showing optional iCloud Sync.
7. Settings > AI & Analysis showing optional user-configured AI.
8. Storage & Export showing local archive/export.

Current zh-Hans review draft, generated from the simulator screenshot fixture on 2026-06-10:

1. `01-ownlight-timeline-zh.png` - Ownlight Timeline with text, audio summary state, check-in, photo grid, tags, and comments.
2. `02-ai-summary-zh.png` - AI summary sheet for an audio moment.
3. `03-markdown-detail-zh.png` - Markdown-rich Moment detail view.
4. `04-calendar-review-zh.png` - Calendar review and recent activity.
5. `05-topic-areas-zh.png` - Tags organized by fixed topic areas.
6. `06-icloud-sync-zh.png` - Settings > iCloud opt-in sync.

The owner-reviewed 6.1-inch raw screenshots live under `.tmp/ui-review/app-store-screenshots/` at `1170x2532`.

The live App Store Connect iPhone screenshot slot is `6.5" Display`, accepting `1284x2778`. The currently released v1 page still uses the zh-Hans `iphone-6-5-zh` set. For the next editable version, prefer the English `iphone-6-5-en` set below so the overseas listing reads English-first.

Current English review draft, generated from the simulator screenshot fixture on 2026-07-02:

1. `01-ownlight-timeline-en.png` - Ownlight Timeline with text, audio summary state, check-in, photo grid, tags, and comments.
2. `02-ai-summary-en.png` - AI summary sheet for an audio moment, using iCloud/local-first copy.
3. `03-markdown-detail-en.png` - Markdown-rich Moment detail view.
4. `04-calendar-review-en.png` - Calendar review and activity overview.
5. `05-topic-areas-en.png` - Tags organized by fixed topic areas.
6. `06-icloud-sync-en.png` - Settings > iCloud opt-in sync.

The English 6.5-inch candidates live under `.tmp/ui-review/app-store-screenshots/iphone-6-5-en/` at `1284x2778`. Use this set for the next App Store Connect version if screenshots remain locked on the live `1.0 Ready for Distribution` page.

A 6.9-inch reference set also exists under `.tmp/ui-review/app-store-screenshots/iphone-6-9-zh/` at `1320x2868`, but the current App Store Connect page is not asking for that size. The 6.1-inch set remains useful as visual review/reference material.

Treat screenshots as raw app screenshots, not marketing-framed composites. Before final upload, confirm image order, localization copy, and whether the current App Store Connect version is editable or a new version is required.

Avoid screenshots that imply:

- public social posting
- hard realtime sync
- developer-hosted cloud account
- medical/health diagnosis
- automatic AI without user consent

## TestFlight

Decision for v1:

- v1 skips TestFlight distribution.
- Final validation uses owner real-device UAT with the daily iPhone plus iPad, then direct App Store submission.
- Use manual release after approval so the app does not go live automatically.
- If App Review rejects or real-world feedback shows onboarding/privacy/sync risk, introduce TestFlight for the next iteration.

Archived beta copy, if needed later:

```text
Ownlight is a local-first private timeline for text, photos, audio, videos, comments, tags, AI summaries, and optional iCloud Sync. This beta focuses on first-run experience, offline capture, media handling, iCloud cross-device behavior, AI provider setup, and local export/import.
```

## Data Deletion And Recovery Draft

User-facing deletion posture:

- Ownlight v1 has no account, registration, login, subscription, ads, analytics account, or developer-hosted user profile to delete.
- Deleting the app from the device deletes the local app container on that device.
- Deleting individual moments, comments, AI summaries, check-in entries, tags, or reviews inside the app removes them from the local library; if `iCloud Sync` is enabled, the deletion is expected to propagate to other devices signed in to the same Apple Account.
- Turning off `iCloud Sync` stops future sync from that device, but it should not be described as automatically deleting records that were already stored in the user's private iCloud database.
- Export packages are ordinary files saved where the user chooses. They can contain private text, comments, tags, summaries, reviews, check-ins, and media, and they are not encrypted by Ownlight. Users must delete those files from Files, iCloud Drive, AirDrop destinations, or other storage locations when no longer needed.
- Removing an AI provider profile clears local configuration and its API key from the iPhone Keychain. Content already sent to a user-selected AI provider is governed by that provider's retention and deletion policy.
- Support email is user-initiated. Users can ask `support@popcornnn.xyz` to delete support correspondence, but the app itself does not create a developer-operated account record.

Recovery posture:

- `Storage & Export` supports local archive export and empty-library import for a basic recovery drill.
- Import is not a non-empty library merge, not an overwrite restore, and not a one-tap new-phone migration promise.
- Export/import must not include AI API keys, provider credentials, raw private transcript text, CloudKit runtime queues/cursors/cache, legacy session tokens, or local diagnostics.
- Release-grade export/import UAT is defined in [APP-STORE-UAT-RUNBOOK.md](APP-STORE-UAT-RUNBOOK.md) and still must be run on a final candidate build.

## Submission Checkpoint

No owner input remained for the `1.1 (4)` submission. English screenshots, overseas availability, App Privacy (`Data Not Collected`), age rating, build selection, review notes, and manual release mode were all confirmed before submission. The next human-facing decision is manual release after Apple approves `1.1`.
- Manual release timing after approval.
