# Handoff

Last updated: 2026-07-17

本文档只记录当前交接状态、最近完成的关键 checkpoint、剩余风险和下一步。历史流水记录已从本文件移除；需要追溯旧实现细节时，优先看 `.planning/DECISIONS.md`、`.planning/STATE.md`、`.planning/phases/`、`docs/RELEASE-CHECKLIST.md` 和 git history。

## 当前状态

- 当前阶段：M017 App Store Readiness And Product Maturity。
- 当前产品形态：iPhone local-first 私密时间线；本机 SQLite 是默认 source of truth；`iCloud Sync` 是 opt-in CloudKit private database 同步层。
- App Store `1.0 (3)` 已发布；English-first `1.1 (4)` 已提交并处于 `Waiting for Review`。当前剩余 release checkpoint 是把 clean source snapshot 发布到新的 public GitHub repository。
- 第一版无账号、无注册、无登录、无 IAP、无广告、无第三方 analytics；AI 走用户自选 provider / endpoint。
- Mac server/admin 仍作为 legacy 兼容、归档、诊断和 API 参考保留，不是普通用户默认 runtime。

## 已完成的关键 checkpoint

- 2026-07-17 已冻结双发布策略：现有 private development repository 保持 private；公开源码使用新的 `Popcornnnnnnnn/ownlight` clean-history repository，GitHub Release 只发 source，不发 owner-signed IPA。
- English `6.5-inch` screenshots 已进入 tracked public assets；iOS app 与 Share Extension 版本统一到 `1.1 (4)`。
- 2026-07-17 已完成 App Store Connect `1.1 (4)` 提交：正式 archive/upload 成功；Primary Language 改为 `English (U.S.)`；English (U.S.) 保存 6 张英文截图；Social Media age-rating 新问题按无社交、无公开 UGC、无用户间 messaging 作答，结果仍为 `4+`；build `1.1 (4)` 已绑定；Review Notes 已刷新；当前状态为 `Waiting for Review`。

- CloudKit 第一阶段已关闭 `UAT-M017-CLOUDKIT-CROSS-DEVICE`：真实 iPhone/iPad 覆盖 ordinary text/audio/media sync、summary artifacts、comments、drafts、Settings preferences、check-ins、delete/tombstone、edit-media add/remove 和新语音 summary/comment 路径。
- `iCloud Sync` 设置页已收敛为普通用户可理解的低频控制：account/status、toggle、guidance copy、`Sync Now`；smoke/default-zone/container diagnostics 不再作为普通设置项展示。
- `cloudkit_full_reconcile_v1` 已作为一次性自愈范围，用于恢复历史遗漏的可选派生记录，不改变普通同步语义。
- App Store 隐私/上架文档已形成当前主线：`docs/APP-STORE-READINESS.md`、`docs/APP-STORE-SUBMISSION-DRAFT.md`、`docs/APP-STORE-UAT-RUNBOOK.md`、`docs/APP-PRIVACY-DATA-INVENTORY.md`、`docs/APP-STORE-PRIVACY-POLICY-CHECKLIST.md`、`docs/APP-STORE-RELEASE-LESSONS.md`、`docs/RELEASE-CHECKLIST.md`。
- 2026-06-08 新增 `npm run doctor:app-store`，当前运行 19 checks。它覆盖 UAT gates、Info.plist 权限文案、export compliance plist key、PrivacyInfo required reason API、iCloud/App Group entitlements、public fallback URL、Privacy/Support URL、analytics/crash/ad/tracking SDK 漂移、明显 required-reason API 漂移，以及首发版不得声明 `UIBackgroundModes = audio` 的 App Review 2.5.4 门禁。
- App Store 提交草案已覆盖 App Privacy Label 主/保守口径、export compliance、metadata、Review Notes、截图计划、无账号数据删除口径和 export/import 恢复口径；真实设备 UAT 路径已独立写入 `docs/APP-STORE-UAT-RUNBOOK.md`。
- 2026-06-10 已更新首发 metadata 口径：App Store name `Ownlight`、Home screen display name `Ownlight`、zh-Hans subtitle `自己的私密时间线`、English subtitle `Your private timeline`；中英文商店名统一使用 `Ownlight`，v1 不做 App Preview、不走 TestFlight，审核通过后手动发布。
- 2026-06-10 已在 App Store Connect 录入当前 metadata checkpoint：App Information / App 菜单显示 `Ownlight`；iOS 1.0 version 的 zh-Hans / English description、keywords 和 App Review Notes 已切到 `Ownlight` 口径；Support URL 继续使用现有 `private-moments.popcornnn.xyz` 公开站点。
- 2026-06-11 已完成 App Store Connect build/privacy checkpoint：App Privacy final answer 已发布为 `Data Not Collected`；正式 Release archive / export / upload 成功；iOS 1.0 version 已选择 build `1.0 (2)`，App Store Connect 的 build 区域已识别 `App Icon`。导出 IPA 已复核正式 bundle id、Share Extension bundle id、App Group、Production CloudKit container 和 `get-task-allow=false`。
- 2026-06-10/11 已生成 zh-Hans App Store 截图审核稿：6.1-inch 审核参考图位于 `.tmp/ui-review/app-store-screenshots/`，当前 App Store Connect `6.5" Display` 上传候选图位于 `.tmp/ui-review/app-store-screenshots/iphone-6-5-zh/`，6.9-inch 备用参考图位于 `.tmp/ui-review/app-store-screenshots/iphone-6-9-zh/`。文件名为 `01-ownlight-timeline-zh.png`、`02-ai-summary-zh.png`、`03-markdown-detail-zh.png`、`04-calendar-review-zh.png`、`05-topic-areas-zh.png`、`06-icloud-sync-zh.png`。本轮同时完成高频中文 UI 文案初筛，把普通用户路径中的 `Moment`、`Check-ins`、`Area`、`iCloud Sync` 等直译感较强词汇收敛为 `记录`、`打卡`、`分类方向`、`iCloud 同步`。
- 2026-06-21 已补齐 `docs/APP-STORE-SUBMISSION-RUNBOOK.md`：记录截图上传、年龄分级、中国大陆合规提示、最终 preflight、真实设备 smoke 和 `Add for Review` 的操作边界。截图候选图本地尺寸预检通过：`iphone-6-5-zh` 为 `1284 x 2778` PNG，`iphone-6-9-zh` 为 `1320 x 2868` PNG。
- 2026-06-21 已完成 App Store Connect live setup checkpoint：Age Rating 保存为 `4+`；App Privacy 复核仍为 `Data Not Collected`；Pricing 设置为 free；Availability 设置为 China mainland only（`1 Available`、`174 Not Available`）；Apple Silicon Mac 和 Apple Vision Pro 分发已关闭；iOS 1.0 version 使用 build `1.0 (2)`、manual release。
- 2026-06-21 已完成 App Store Connect iPhone `6.5" Display` screenshot 上传：当前页面显示 `6 of 10 Screenshots`、`0 of 3 App Previews`，6 张图顺序为 Timeline、AI summary、Markdown detail、Calendar review、Topic areas、iCloud sync。v1 仍不做 App Preview。
- 2026-06-21 22:08 CST，owner 明确确认后已在 App Store Connect 点击 `Add for Review` 和 `Submit for Review`；2026-06-24 Apple Review 返回 `Changes Needed` / `Rejected`，原因是 build `1.0 (2)` 在 `UIBackgroundModes` 中声明 `audio` 但审核未发现需要持久后台音频的功能。当前处理方案是保留语音 Moment / check-in audio / AI summary，但 v1 移除后台 audio entitlement，录音/播放保持 foreground-only。
- 2026-06-24 已完成 App Store 2.5.4 修复重提：`npm run doctor:app-store` 和 `npm run verify:ios:low-impact` 通过；Release archive/export/upload 成功；导出 IPA 复核 `UIBackgroundModes` absent；App Review Notes 已补充 build `1.0 (3)` 移除 background audio entitlement；App Store Connect 已选择 build `1.0 (3)` 并重新 `Resubmit to App Review`，当前状态为 `Waiting for Review`。
- 2026-06-25 Apple Review 对 build `1.0 (3)` 返回第二个 rejection：Guideline 3.1.1 / Business / Payments / In-App Purchase，认为 Ownlight 使用 API keys 启用 paid functionality 且这些 API keys 不能通过 IAP 购买。2026-06-27 已在 App Store Connect 用更自然的开发者口吻回复澄清：Ownlight 完全免费、无 IAP/广告/购买链接/开发者托管 AI，API key 不是 Ownlight license key，核心本地功能不依赖 AI，AI provider 只是用户自有/自托管兼容 endpoint 的可选配置，并请求 Apple 指出具体违规实现点。
- 2026-06-28 22:35 CST，Apple 已接受 3.1.1 澄清并批准 Ownlight iOS `1.0 (3)`；owner 登录 App Store Connect 后，已点击 `Release This Version`。App Store Connect 当前状态为 `1.0 Ready for Distribution`，后续只需要等待 App Store listing 传播，Apple 提示发布后最多可能需要 24 小时可见。
- 2026-07-02 已根据 ICP/中国大陆可见性问题调整 App Store Connect Availability：从 China mainland-only 改为 174 countries or regions 可用，并取消勾选 China mainland。确认弹窗说明 app 会从 China mainland 下架、在 174 个国家或地区可用，变更最多 24 小时生效；页面随后显示 China mainland `Not Available`，其他地区 `Processing to Available`。
- 2026-07-02 已生成英文 App Store 6.5-inch 截图候选：`.tmp/ui-review/app-store-screenshots/iphone-6-5-en/01-ownlight-timeline-en.png` 到 `06-icloud-sync-en.png`，尺寸均为 `1284 x 2778`。英文截图已修正文案，避免旧 `server was reachable` 口径，改为 iCloud/local-first 语义。
- 2026-07-02 已检查 App Store Connect iOS `1.0 Ready for Distribution` 的 Media Manager：English (U.S.) localization 仍显示 `Using Chinese (Simplified) 6.5" Display`，DOM 中没有上传按钮或 file input；App Information 页中 primary language 仍是 `Chinese (Simplified)`，English subtitle 也未在 live page 暴露可编辑控件。若要完全切成英文截图/副标题/primary-language 口径，需要准备下一个 app version 后再处理。
- 2026-06-28 已新增 `docs/APP-STORE-RELEASE-LESSONS.md`，沉淀 Ownlight 首发对下一款 App 可复用的经验：v1 简化边界、entitlement 最小声明、BYOK/API key 审核说明、隐私数据盘点、截图差异化、真机 UAT、manual release 和审核回复方式。
- 2026-06-08 清理旧规划噪音：受版本控制的旧 `.planning/_legacy-gsd/` 目录已移除，边界记录在 `.planning/LEGACY-GSD-ARCHIVE.md`；旧细节只从 git history 追溯。ignored `.tmp/` 已清理。

## 当前 Backlog 判断

- `.planning/BACKLOG.md` 中没有 v0.1 上架阻塞项。
- `B001` SenseVoice/FunASR local transcription adapter 是 v0.1 后高级转录增强。
- `B002` CloudKit push-assisted near-realtime sync 是 v0.1 后实时性增强；当前不要承诺 hard realtime，继续用 foreground/polling/manual fallback 语义。
- `docs/BACKLOG.md` 中 AI 文字总结、Ask Timeline / LLM Chat、Monthly Review、AI reviewer 等都是上架后候选能力，不进入当前上架阻塞判断。

## 剩余上架工作

这些是发布后监控和后续版本复核，不是当前长期 backlog：

- 监控 App Store Connect、Apple Developer 邮箱和 App Store listing；当前重点是 English-first `1.1 (4)` 的 App Review 结果。
- Apple 批准 `1.1 (4)` 后执行 manual release，并复核海外默认商品页是否使用 English metadata 与 6 张英文截图。
- 首次可下载后，用真实 iPhone 跑一次 App Store 安装版本 smoke：首次打开、创建记录、iCloud toggle、AI provider 设置入口、隐私/支持链接。
- 后续版本继续保留 3.1.1 澄清口径：Ownlight 免费、无 IAP、无开发者托管 AI；API key 是用户自有 provider 的可选互操作配置，不是 Ownlight 付费解锁。
- 后续版本继续使用 `docs/APP-STORE-UAT-RUNBOOK.md` 和 `npm run doctor:app-store` 做提交前 preflight。

## 推荐验证命令

轻量本地收口：

```bash
npm run doctor:app-store
npm run verify:release-gates
npm run verify:ios:low-impact
```

如本轮改动 legacy server/admin：

```bash
npm run verify:server
```

如本轮改动 archive/recovery：

```bash
npm run doctor:archive
```

如未来重新考虑公开源码：

```bash
npm run doctor:release
```

## 注意事项

- 不要把 old Mac/server sync 当作普通用户默认路径重新写回 UI 或文案。
- 不要把 `iCloud Sync` 描述成实时同步、跨 Apple ID 共享、非空库自动 merge、开发者服务器托管同步或完全不受 iCloud quota/系统状态影响。
- Provider profile/API key、raw transcript、provider raw response、diagnostics、sync queue/cache 和本机 gateway 配置不得进入 CloudKit、export 或日志。
- 若再改 CloudKit schema、initial upload、media asset、delete/tombstone、preference/draft 或 local apply 逻辑，重新抽测两台真实设备。
