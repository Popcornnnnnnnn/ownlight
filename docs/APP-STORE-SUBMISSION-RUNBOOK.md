# App Store 提交 Runbook

Last updated: 2026-07-02

本文档记录 Ownlight v1 从已上传 build 到最终提交审核的操作顺序。它不替代 App Store Connect 页面上的最终提示；如果页面出现新的法律、地区资质、账号、付款或合规确认，以页面实际要求为准并暂停处理。

## 当前已完成状态

- App Store Connect app id：`6778719728`。
- iOS version：`1.0`。
- 当前审核 build：`1.0 (3)`。`1.0 (2)` 在 2026-06-24 被 App Review 打回后，`1.0 (3)` 已完成修复、上传、选择并重提。
- App Privacy 已发布为 `Data Not Collected`。
- Build 区域已显示 `Included Assets: App Icon`。
- Age Rating 已保存为全局 `4+`；Made for Kids / higher age override 均为 not applicable。
- Pricing 已设置为 free（`$0.00` base price）。
- Availability 当前已从 China mainland-only 改为 174 countries or regions 可用，China mainland 已取消勾选并显示 `Not Available`。2026-07-02 确认弹窗说明该变更最多 24 小时生效。
- Apple Silicon Mac 和 Apple Vision Pro 分发已关闭。
- iPhone `6.5" Display` screenshots 已上传：当前 live version 显示 `6 of 10 Screenshots`、`0 of 3 App Previews`，但已发布版本仍使用 zh-Hans 截图；English localization 在 Media Manager 中复用 Chinese (Simplified) 截图且没有上传控件。
- 英文 6.5-inch 截图候选已生成在 `.tmp/ui-review/app-store-screenshots/iphone-6-5-en/`，用于下一版本或可编辑截图槽位。
- 2026-06-21 22:08 CST 首次提交审核；2026-06-24 App Store Connect 状态变为 `Changes Needed` / `Rejected`。
- 首次 rejection：Guideline 2.5.4，原因是 `Info.plist` 声明 `UIBackgroundModes = audio`，但审核未发现需要持久后台音频的功能。
- 当前处理方案：v1 保留语音 Moment、check-in audio、播放、转录和 AI summary，但录音/播放都是前台工作流；`1.0 (3)` 已移除 background audio entitlement 并重提。
- 2026-06-24 第二次提交后 App Store Connect 状态曾为 `Waiting for Review`。
- 2026-06-25 第二次 rejection：Guideline 3.1.1，原因是 reviewer 认为 API keys 用于启用 paid functionality，且相关 API keys 不能在 App Store 通过 IAP 购买。
- 2026-06-27 已通过 `Reply to App Review` 回复澄清：Ownlight 免费、无 IAP/广告/购买链接/开发者托管 AI，API key 不是 Ownlight license key，核心功能不依赖 AI，AI provider 只是用户自有或自托管 endpoint 的可选配置；同时请求 Apple 指出具体违反 3.1.1 的实现点。
- 2026-06-28 Apple 已接受 3.1.1 澄清并批准 iOS `1.0 (3)`。
- 2026-06-28 22:35 CST 已在 App Store Connect 点击 `Release This Version`；当前状态为 `1.0 Ready for Distribution`。Apple 提示发布后最多可能需要 24 小时才完全可见。
- v1 不走 TestFlight；当前已按 manual release 发布。
- v1 无账号、无 IAP、无广告、无 analytics、无 developer-hosted default AI。

## 操作原则

- 不点击最终 `Add for Review`，除非 owner 当场明确确认。
- 不把截图、年龄分级、地区合规和最终送审混成同一步；每一步完成后先看页面是否产生新的 blocking prompt。
- 如果 App Store Connect 弹出中国大陆 ICP、State Council Decree No. 810、主体资质、联系方式、付款、税务或其他法律责任确认，暂停并交给 owner 确认。
- 如果 App Store Connect 要求重新登录、二步验证或 Apple Account 认证，暂停并让 owner 登录。
- App Store 官方文档当前说明：screenshots 每个设备/语言最少 1 张、最多 10 张，支持 `.jpeg`、`.jpg`、`.png`；App Preview 可选。年龄分级是必填信息，Unrated app 不能发布。

## 1. 上传 screenshots

目标位置：App Store Connect > Apps > Ownlight > iOS `1.0` version > App Previews and Screenshots。

当前候选图：

```text
.tmp/ui-review/app-store-screenshots/iphone-6-5-zh/01-ownlight-timeline-zh.png
.tmp/ui-review/app-store-screenshots/iphone-6-5-zh/02-ai-summary-zh.png
.tmp/ui-review/app-store-screenshots/iphone-6-5-zh/03-markdown-detail-zh.png
.tmp/ui-review/app-store-screenshots/iphone-6-5-zh/04-calendar-review-zh.png
.tmp/ui-review/app-store-screenshots/iphone-6-5-zh/05-topic-areas-zh.png
.tmp/ui-review/app-store-screenshots/iphone-6-5-zh/06-icloud-sync-zh.png
```

当前英文候选图：

```text
.tmp/ui-review/app-store-screenshots/iphone-6-5-en/01-ownlight-timeline-en.png
.tmp/ui-review/app-store-screenshots/iphone-6-5-en/02-ai-summary-en.png
.tmp/ui-review/app-store-screenshots/iphone-6-5-en/03-markdown-detail-en.png
.tmp/ui-review/app-store-screenshots/iphone-6-5-en/04-calendar-review-en.png
.tmp/ui-review/app-store-screenshots/iphone-6-5-en/05-topic-areas-en.png
.tmp/ui-review/app-store-screenshots/iphone-6-5-en/06-icloud-sync-en.png
```

尺寸预检：

- `iphone-6-5-zh/*`：`1284 x 2778` PNG。
- `iphone-6-5-en/*`：`1284 x 2778` PNG。
- `iphone-6-9-zh/*`：`1320 x 2868` PNG，备用。

下一次可编辑版本优先上传 `iphone-6-5-en` 6 张；当前 live v1 已发布页面仍显示 zh-Hans 截图，并且 Media Manager 在 English (U.S.) 下未暴露上传控件。如果页面提示需要其他尺寸，再使用 Media Manager 补充对应尺寸。

完成标准：

- iPhone screenshot 区域显示 6 张图。
- 预览顺序为 Timeline、AI summary、Markdown detail、Calendar review、Topic areas、iCloud sync。
- 保存后没有红色错误或缺失尺寸提示。

当前结果：

- 2026-06-21 App Store Connect iOS `1.0` version 页面已显示 `6 of 10 Screenshots`。
- App Preview 显示 `0 of 3 App Previews`，这是 v1 intentional：App Preview 是 optional，首发不制作视频。
- App Store Connect 弹出的 screenshot/localization 复用提示已确认；页面未显示红色截图错误，`Save` 处于 disabled 状态。
- 2026-07-02 已生成英文截图并检查尺寸/画面；但 live `1.0 Ready for Distribution` Media Manager 在 English (U.S.) 下只显示 `Using Chinese (Simplified) 6.5" Display`，DOM 中没有 file input 或上传按钮。若要替换为英文截图，准备下一版本时再上传。

## 2. 完成年龄分级问卷

入口：App Store Connect > App Information > Age Ratings。

当前结果：

- 2026-06-21 已在 App Store Connect 保存问卷。
- App Information 页面显示 global age rating `4+`。
- Regional age rating exceptions 显示 `172 countries or regions`。
- `Not Applicable` 已用于 Made for Kids / higher age override 等附加项。

提交前如需重新核对，当前产品口径：

- Not Made for Kids。
- 无公开社交、公开 UGC、聊天、用户匹配、赌博、抽奖、loot boxes、成人内容、医疗建议、药物/酒精/烟草推广、恐怖/暴力内容。
- App 保存用户自己的私密内容；App 本身不提供第三方媒体内容。
- 不使用 WebView 提供 unrestricted web access。
- 不提供位置分享、陌生人互动或外部可见评论。

如果问卷出现以下类型，按当前产品应选择 `None` 或 `No`：

- Violence / Horror / Mature themes
- Sexual content / Nudity
- Alcohol / Tobacco / Drug references
- Medical / Treatment information
- Gambling / Contests / Loot boxes
- Unrestricted web access
- Public user-generated content

如果页面询问是否提高年龄分级、是否 Made for Kids 或是否提供 Age Suitability URL：

- Made for Kids：No / Not Applicable。
- Override to Higher Age Rating：Not Applicable，除非 owner 另行决定。
- Age Suitability URL：v1 可留空。

完成标准：

- App Information 页面显示已计算的 age rating。
- 没有 unresolved age rating warning。

当前状态：已完成。

## 3. 检查中国大陆和地区合规提示

入口可能出现在：

- App Store Connect > Pricing and Availability / Availability。
- App Information 下的 App Store Regulations & Permits。
- 提交审核前的 blocking modal。

需要暂停给 owner 的情况：

- ICP filing / license / permit 字段。
- Mainland China compliance information。
- State Council Decree No. 810。
- 要求填写主体、证件、电话、地址、备案号或承诺声明。
- 要求选择是否下架/限制中国大陆可用性。

当前策略已临时调整为海外先行：China mainland 不可用，后续再单独处理 ICP/中国大陆上架策略。

当前结果：

- 2026-06-21 Pricing 已设为 free。
- 2026-06-21 Availability 曾选择 `Specific Countries or Regions`，仅勾选 `China mainland`。
- 2026-07-02 因 App Store 中国大陆可见性/ICP 策略未定，已在 Availability 中勾选海外 174 countries or regions 并取消 China mainland。确认弹窗为 “Your app will be removed from the App Store in China mainland and become available in 174 countries or regions. Your changes will take effect within 24 hours.”
- App Information 仍可见可选的 China Mainland ICP Filing Number `Set Up` 入口；v1 当前未填写备案号。后续如要恢复 China mainland availability，需先确认 ICP/中国大陆上架材料路径。

## 4. 最终本地 preflight

提交前运行：

```bash
npm run doctor:app-store
npm run verify:release-gates
npm run verify:ios:low-impact
```

通过标准：

- `doctor:app-store` 无 failure/warning。
- `verify:release-gates` 显示 0 open gates。
- `verify:ios:low-impact` build succeeded。

## 5. 最终真实设备 smoke

按 `docs/APP-STORE-UAT-RUNBOOK.md` 抽测最终候选 build：

- First launch / welcome sample。
- Text/photo/audio/video moment。
- Share Sheet。
- AI optional path。
- iCloud Sync 跨 iPhone/iPad。
- Export/import 空库恢复。
- 无网和权限拒绝。
- 800+ moments 性能 smoke。
- VoiceOver / Larger Text 最小 accessibility smoke。

如果最后没有改代码且近期同一 build 已完成真实设备覆盖，可以把 UAT 记录为“复核通过”，但仍要写清 build 号和设备。

## 6. 最终提交审核

首次提交前检查：

- App Store Connect iOS `1.0` version 选中 build `1.0 (2)`。
- Screenshots 已上传并保存。
- Age rating 已完成，当前显示 `4+`。
- App Privacy 为 `Data Not Collected`。
- Release mode 为 manual release after approval。
- App Review Notes 使用 Ownlight 口径，且没有旧 `Private Moments` 主品牌残留。
- 没有 unresolved compliance prompt。

最终结果：

- 2026-06-21 owner 明确确认后，已依次点击 `Add for Review` 和 `Submit for Review`。
- App Store Connect iOS `1.0` version 当时状态变为 `Waiting for Review`。
- 页面里仍有普通的中国大陆 permit 说明文字，但提交过程中没有出现新的阻塞式 ICP/permit 弹窗。
- 2026-06-24 Apple Review 返回 `Changes Needed` / `Rejected`，需要处理 Guideline 2.5.4 后重新提交。

首次提交后记录：

- App Store Connect status：`Rejected` / `Changes Needed`。
- 提交时间：2026-06-21 22:08 CST。
- 自动警告或 export compliance follow-up：提交页面未显示新的阻塞项。
- 是否需要补充 App Review message：重提 build `1.0 (3)` 时在 Notes 中说明已移除 background audio entitlement。

2.5.4 修复重提结果：

- 2026-06-24 已运行 `npm run doctor:app-store`，19 checks 通过，并确认首发版不再声明 `UIBackgroundModes = audio`。
- 2026-06-24 已运行 `npm run verify:ios:low-impact`，iOS build succeeded。
- 2026-06-24 已 archive/export/upload build `1.0 (3)`。
- 导出 IPA 复核：主 App 与 Share Extension 使用 owner 专用 explicit bundle IDs，App Group 与 Production CloudKit container 绑定一致，版本为 `1.0 (3)`，`UIBackgroundModes` absent。具体 signing identifiers 不进入公开源码快照。
- App Review Notes 已补充：`Build 1.0 (3) removes the audio UIBackgroundModes setting. Voice recording and audio playback are foreground-only in this version.`
- App Store Connect 已从 build `1.0 (2)` 切换到 build `1.0 (3)`，并已点击 `Update Review` 和 `Resubmit to App Review`。
- 2026-06-24 第二次提交后 App Store Connect status：`Waiting for Review`。

3.1.1 反馈与回复记录：

- Review date：2026-06-25。
- Review device：iPad Air 11-inch (M3)。
- Version reviewed：`1.0 (3)`。
- Review status：`Rejected` / `Unresolved Issues`。
- Guideline：`3.1.1 Business - Payments - In-App Purchase`。
- Reviewer issue：App 使用 API keys 启用 paid functionality，但这些 API keys 不能通过本 App 或 provider 关联 App 的 IAP 购买。
- 2026-06-27 19:24 CST 已从 App Store Connect 发送 `Reply to App Review`。回复口径：礼貌请求澄清与复核；说明 Ownlight 是免费 local-first timeline，没有 IAP、ads、purchase links、developer-hosted AI service 或 paid tier；API key 不是 Ownlight license key；主功能无需 API key；AI provider 只是用户自有兼容 provider 或 self-hosted endpoint 的可选互操作配置；如 UI wording 造成误解，愿意调整文案。
- Apple 后续接受该澄清并批准 build `1.0 (3)`；当前无需为 3.1.1 改包或重新提交。

## 7. 审核等待期与发布结果

- 2026-06-28 owner 已确认并登录 App Store Connect 后，手动发布 `1.0 (3)`。
- App Store Connect 当前状态：`1.0 Ready for Distribution`；2026-07-02 live availability 已改为海外 174 countries/regions，China mainland `Not Available`。
- 发布后最多可能需要 24 小时才在 App Store 完全可见或可搜索。
- 继续关注 App Store Connect、Apple Developer 账号邮箱和公开 listing。如果 Apple 后续发来新的问题，先记录原文，再决定回复或改包。

当前首次审核反馈：

- Submission ID：`5a800022-d869-47d2-a2f6-18cbffcc2a0c`。
- Review date：2026-06-24。
- Review device：iPad Air 11-inch (M3)。
- Version reviewed：`1.0 (2)`。
- Review status：`Rejected` / `Changes Needed`。
- Guideline：`2.5.4 Performance - Software Requirements`。
- 修复路径：移除 `UIBackgroundModes = audio`，保持 v1 语音录制/播放为前台-only；`npm run doctor:app-store` 必须拦截任何重新声明后台 audio 的改动。

重提顺序与结果：

1. 运行 `npm run doctor:app-store`，确认 19 checks 没有 failures。已完成。
2. 运行 `npm run verify:ios:low-impact`。已完成。
3. Archive/export/upload build `1.0 (3)`。已完成。
4. 在 App Store Connect 选择新 build。已完成。
5. App Review Information notes 补充 foreground-only audio 说明。已完成。
6. owner 确认后重新 `Submit for Review`。已完成；当时状态为 `Waiting for Review`，后续见 3.1.1 反馈记录。

3.1.1 当前处理顺序：

1. 先通过 `Reply to App Review` 澄清并请求 Apple 指出具体违规点。已完成。
2. Apple 已接受澄清并批准 build `1.0 (3)`。
3. 已手动发布。后续版本继续保持 Review Notes 和隐私文案一致：Ownlight 免费、无 IAP/广告/购买链接/开发者托管 AI，API key 不是 Ownlight license key。
