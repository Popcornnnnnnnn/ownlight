# v0.1 UAT 门禁

本文档记录 v0.1 内部候选版本前必须人工确认的真实使用路径。它和自动化测试不同：自动化验证负责防止代码退化，UAT 负责确认真实 iPhone、iCloud/CloudKit、AI provider、本机存储/导出和个人数据路径在日常使用里成立。legacy server/admin 相关 gate 只保留历史维护记录，不作为当前首发前置条件。

运行状态检查：

```bash
npm run verify:uat-gates
npm run verify:release-gates
```

`verify:uat-gates` 只汇总当前 open gate；`verify:release-gates` 会在仍有 open gate 时失败，用于 release candidate 前的硬门禁。

## 当前 Gate

| Gate | Status | Area | Required Evidence |
|---|---|---|---|
| UAT-M004-AUDIO-VIDEO | closed | Audio and Video Moments | 真实 iPhone 上录音、暂停/继续/停止、试听、发布、后台播放、短视频导入、超长视频拒绝、全屏播放、sync/upload/recovery、Storage cache clear 均通过。 |
| UAT-M005-AI-SUMMARY | closed | AI Media Summaries | fresh clear-speech audio/video 发布后，iOS 不显示 transcript/占位；iPhone-direct AI 生成 ready summary 后，timeline 显示 `Summary ready`，sheet 显示 v4 document summary，Regenerate/Delete/failed 保留旧摘要语义均可用。 |
| UAT-M005-AI-TITLE | closed | AI Title Auto-Insert | fresh audio 无用户标题时首次 ready summary 写入 `##` 短标题，不显示 `Edited`；已有 `#`/`##` 或关闭 `AI Title Auto-Insert` 时不写入；Regenerate 不覆盖已有标题。 |
| UAT-M006-SMART-TAGS | closed | Smart Tags | 手动主标签发布、timeline tag toggle、Detail 标签显示/单条编辑、topic alias search、topic merge/archive/restore/delete、Storage diagnostics tags、新语音 summary ready 后 AI tags sync 均通过，并确认 AI topic 优先复用已有 topic/alias 而不是创建近义重复标签。 |
| UAT-M007-LANGUAGE | closed | App Language | `System` / `English` / `简体中文` 切换后，主 App 主要 UI、日期、筛选、Settings、Tags、Summary、Detail/Edit 可读且不翻译用户内容。 |
| UAT-M008-CALENDAR | closed | Calendar Review | 真实 iPhone 上 Calendar month grid、Day Review、Month Stats、Day Review filters、Timeline day filter handoff、返回位置记忆、音频/视频提示体验成立。 |
| UAT-M009-ARCHIVE | closed | Legacy Archive / Restore / Export / Import | 历史维护路径：真实本地服务上通过 Mac Admin 创建 backup、list/check snapshot、staged restore、promote preparation、export package、import staged data directory；确认真正切换仍走 `pending-promote.json` restart 流程。当前首发数据安全主路径另看 iCloud 和 iPhone local archive。 |
| UAT-M009-SYNC-HEALTH | closed | Legacy Sync Health | 历史维护路径：iOS Settings 和 Mac Admin 能区分 server unreachable、auth failure、cursor lag、pending outbox、failed media upload、missing media、AI non-ready，并且安全动作可恢复常见状态。当前 iCloud sync health 需要单独 gate。 |
| UAT-M010-WEEKLY-REVIEW | closed | Weekly Review | 真实最近 7 天数据生成 Review，语气是冷静观察 + 适度鼓励，不逐条过度解读；`Worth Revisiting` 低权重 anchors 能在 Review 内打开原 moment。 |
| UAT-SHARE-EXTENSION | closed | Save to Ownlight | Photos 多图、Safari URL/text、Files/Voice Memos 音频、视频分享都能打开主 App Composer，发布成功后 import queue 被清理；真实 provisioning/App Group 正常。 |
| UAT-M011-PINNED-MOMENTS | closed | Pinned Moments | 合并/真机安装前先完成 Sync Health/outbox/recovery checkpoint；真实 iPhone 上确认 Detail `More` pin/unpin、Timeline 长按 pin/unpin、`Pinned · N` 默认折叠、1-3 条展开、超过 3 条 sheet、sheet 内 detail navigation、普通 Timeline 保留 pinned row 且显示 pin 标识、搜索/筛选隐藏 Pinned 且仍能找到原 moment。 |
| UAT-M013-CONTINUITY-POLISH | closed | Check-ins / Day Review / Backup Status / Weekly Review | 真实 iPhone 上确认 Time Heatmap tap/drag bucket 探索、bucket 记录进入 entry detail、Day Review check-ins rhythm 不抢主时间轴、Diagnostics > Backup Status 可读且不暴露执行动作、真实最近 7 天 Weekly Review 语气更保守且 Worth Revisiting anchors 有效。 |
| UAT-M015-CHECKIN-AUDIO-AI | closed | Check-in audio AI summaries | 真实 iPhone 上确认：1) 已配置 AI 时，新的 check-in audio 会自动生成 summary；2) `Show Check-in Summaries` 关闭后只隐藏 UI、不影响后台生成；3) 未配置 AI 时上传 audio 不报错，也不会出现 failed summary。 |
| UAT-M017-CLOUDKIT-CROSS-DEVICE | closed | iCloud Sync | 真实 iPhone 与 iPad：开启 `iCloud Sync` 后，普通文字 Moment、语音 Moment、媒体 metadata/assets、评论/标签/check-ins、删除/tombstone、draft/preference metadata 能低频自动同步；第二台设备已有本地数据时不静默覆盖；CloudKit 失败时 UI 给出可理解状态且 App 保持 local-only 可用。 |

## 验收记录

- 2026-05-07：用户确认当前 10 个 UAT gate 先全部验收通过。本次收口只记录人工验收状态，不引入功能代码变更；后续如果发现回归或新增范围，应重新打开对应 gate 或新增 gate。
- 2026-05-08：M011 Pinned Moments 已在功能 worktree 通过自动化、隔离 server smoke 和模拟器 UI/交互验证；因为本轮明确不安装真机，新增 `UAT-M011-PINNED-MOMENTS` 作为后续真实设备验收门禁。
- 2026-05-08：用户确认 `UAT-M011-PINNED-MOMENTS` 已在真实使用中完成验收；当前所有 UAT gate 均为 `closed`。`UAT` 全称是 `User Acceptance Testing`，这里指用户验收测试。
- 2026-05-09：M013 连续性 polish 新增 `UAT-M013-CONTINUITY-POLISH`。自动化和真机安装可以验证功能可运行，但图表触感、Day Review 节奏和 Weekly Review 质量仍需用户在真实数据上确认后关闭。
- 2026-05-13：用户确认 M013 连续性 polish 的真实设备路径也没有问题，`UAT-M013-CONTINUITY-POLISH` 已关闭。至此当前 v0.1 路线图里的 UAT gate 全部为 `closed`。
- 2026-05-13：M015 Check-in audio AI summaries 已再次通过 `npm run ios:device` 真机 preflight、build、install 和 launch；随后用户确认 check-in audio auto summary、`Show Check-in Summaries` display-only toggle、以及 AI 未配置时的 silent skip 三条路径均正常，`UAT-M015-CHECKIN-AUDIO-AI` 已关闭。
- 2026-06-07：`UAT-M017-CLOUDKIT-CROSS-DEVICE` 仍保持 `open`。用户已确认新语音 Moment、转录/summary artifact 和评论可以自动跨 iPhone/iPad 同步，不需要手动点 `Sync Now`；本轮代码又补上非空第二设备初始同步保护，自动化覆盖“远端已有真实 archive + 本机也有真实内容时阻止开启”和“本机 sample-only 时先 pull 远端 archive”。关闭 gate 前还需要真实手动验收非空第二设备提示、delete/tombstone、draft/preference、quota/网络失败、secrets 不同步和最终文案一致性。
- 2026-06-07：`UAT-M017-CLOUDKIT-CROSS-DEVICE` 仍保持 `open`。本轮补齐更多普通 mutation 的 CloudKit 入队覆盖：favorite、pin、topic/tag/alias/assignment、check-ins、ready check-in AI summary 和 synced preference allowlist。自动化证据为真实 iPhone focused tests 12/12、`git diff --check`、`npm run verify:ios:low-impact` 和 `npm run ios:device` 安装/启动通过。关闭 gate 前仍需真实手动验收非空第二设备提示、delete/tombstone、draft/preference 跨设备效果、quota/网络失败、secrets 不同步和最终两端 UI/数量一致性。
- 2026-06-07：`UAT-M017-CLOUDKIT-CROSS-DEVICE` 仍保持 `open`。本轮补齐 draft metadata realtime enqueue：Composer/Edit draft save/clear 在 `iCloud Sync` 开启时会 enqueue `.draft` upsert/delete，连续输入会复用 pending upsert，先删除后继续输入会追加新的 upsert；AI provider profile/API key/Base URL/model 和临时 draft media 文件仍保持 local-only。自动化证据为 `git diff --check`、`npm run verify:ios:low-impact` 和 generic iOS build-for-testing 通过；真实 iPhone focused test execution 曾因设备锁屏阻塞，后续 UAT 时再在解锁设备上跑。关闭 gate 前仍需真实手动验收非空第二设备提示、delete/tombstone、draft/preference 跨设备效果、quota/网络失败、secrets 不同步和最终两端 UI/数量一致性。
- 2026-06-07：`UAT-M017-CLOUDKIT-CROSS-DEVICE` 仍保持 `open`。真实设备诊断发现源 iPhone 有 CloudKit 历史但缺少显式 `iCloudSyncEnabled` preference key，导致草稿、部分设置和 check-in 本地保存后没有进入 CloudKit queue。本轮补上 history-backed opt-in recovery：启动时只在已有 CloudKit 历史且用户没有显式关闭 iCloud 时恢复开关，并用 `icloud_opt_in_recovery` 补传缺失本地记录、刷新 preference/draft singleton 快照。随后修复 composer draft 远端记录缺失空 `existingMediaIds` 字段时的 apply 兼容问题。自动化证据为 `git diff --check`、`npm run verify:ios:low-impact`、focused recovery tests 4/4 和 draft missing-empty-list regression test 1/1 通过；真实 iPhone/iPad 均已安装同一 build，容器复查显示两端 `composer.draft.text="测试一下草稿"`、`memoryLinksEnabled=0`、`showTagsInTimeline=0`、`markdownMathRenderingEnabled=1`、check-in entries 均为 132、CloudKit sync state 无 last error 且 pending queue 为 0。关闭 gate 前仍需真实手动验收 delete/tombstone、网络/配额失败、非空第二设备提示和最终两端 UI/数量一致性。
- 2026-06-07：`UAT-M017-CLOUDKIT-CROSS-DEVICE` 仍保持 `open`。真实设备诊断显示 synced preference 已经落到两端 `AppSettings`，但 CloudKit pull/manual `Sync Now` 后没有刷新 `TimelineStore` published state，导致 Settings UI 看起来滞后；本轮修复 auto sync 和 `Sync Now` 后刷新 synced preference allowlist，并把 preference auto sync debounce 缩短到 1 秒，content/media 仍为 5 秒，前台 poll 约 15 秒。验证证据为 `git diff --check`、`npm run verify:ios:low-impact` 和 generic iOS build-for-testing；新增 regression tests 已通过 build-for-testing 编译但未跑 Simulator；signed build 已安装/启动到真实 iPad，真实 iPhone 当前 CoreDevice 仍为 `unavailable`，待重连/解锁后补装。关闭 gate 前仍需真实手动验收可见 Settings 跨设备传播、delete/tombstone、网络/配额失败、非空第二设备提示和最终两端 UI/数量一致性。
- 2026-06-07：`UAT-M017-CLOUDKIT-CROSS-DEVICE` 仍保持 `open`。上述 preference refresh/cadence build 已补装到真实 iPhone，并由用户确认当前设置同步体验没有明显问题。Push-assisted near-realtime sync 已讨论并记录为 `.planning/BACKLOG.md` B002；它不是关闭当前 M017 gate 的前置条件。关闭 gate 前仍需真实手动验收 delete/tombstone、网络/配额失败、非空第二设备提示和最终两端 UI/数量/文案一致性。
- 2026-06-07：`UAT-M017-CLOUDKIT-CROSS-DEVICE` 仍保持 `open`。本轮补齐 delete/tombstone 和编辑媒体增删的 CloudKit 入队语义：整条 Moment 删除会为 parent Moment、child media、comments、Timeline AI summaries 和 post-tag assignments 生成 delete pending changes；编辑 Moment 新增媒体会入队 media metadata + asset upload，被移除媒体会入队 media delete。自动化证据为新增 focused tests 先红后绿、`CloudKitTimelineMutationTests` 整类通过、`git diff --check` 和 `npm run verify:ios:low-impact` 通过。关闭 gate 前仍需真实 iPhone/iPad 手动验收：删除含媒体/评论/summary/tag 的测试 Moment 后另一台设备无 stale child artifact；编辑另一条 Moment 增删媒体后另一台设备收敛到最终媒体列表；随后再验网络/配额失败、非空第二设备提示和最终两端 UI/数量/文案一致性。
- 2026-06-07：`UAT-M017-CLOUDKIT-CROSS-DEVICE` 仍保持 `open`。用户确认上一条 delete/tombstone 和编辑媒体增删 build 测试下来感觉没有问题，因此该子项不再作为当前 blocker。随后补上 CloudKit failure UX 与 Composer Audio 小修：`Sync Now` / enablement 失败会从 raw `CKErrorDomain` 诊断改为普通用户可读的 iCloud/offline/quota/temporary unavailable/restricted/non-empty-library 提示；新建 Moment 时点击 `Audio` 会先收起键盘再启动录音。自动化证据为新增 focused tests 先红后绿，并在 iPhone 13 Pro-class Simulator 上通过 `ComposerMediaActionPolicyTests` 与 `CloudKitSyncUserMessageTests`；Simulator 已关闭。关闭 gate 前仍需真实手动验收网络/配额失败文案、非空第二设备提示、secrets/provider config 不同步和最终两端 UI/数量/文案一致性。
- 2026-06-07：`UAT-M017-CLOUDKIT-CROSS-DEVICE` 已关闭。收口证据包括：真实 iPhone/iPad guarded CloudKit smoke 均成功；用户确认普通文字、语音、媒体、转录/summary artifact、评论可自动跨设备同步，草稿、Settings preference、check-ins、delete/tombstone 和编辑媒体增删路径没有明显问题；Settings 已隐藏普通用户不需要的 CloudKit diagnostics；用户可读 failure message 已覆盖未登录、离线、quota/full storage、iCloud 暂时不可用、账号限制、非空第二设备保护和通用可重试失败。收口检查复制真实 iPad container 和最近同阶段 iPhone/iPad container 快照，确认 SQLite `quick_check` 正常、CloudKit pending queue 无 unfinished work、iPad 本地没有 AI provider profile/secret 快照；本轮代码还新增一次性 `cloudkit_full_reconcile_v1` pull scope，用独立 cursor 从 private zone 做完整派生记录自愈，补齐历史 cursor 已前进但第二台设备缺少早期 AI summary/tag 派生记录的场景。真实 quota/full-storage 没有被人为耗尽制造，只以 classifier/failure-copy 自动化和历史真实 CloudKit 失败路径覆盖；正式 App Store 提交前仍应按 `docs/RELEASE-CHECKLIST.md` 复核隐私文案、App Privacy label 和截图口径。

## 关闭 Gate 的规则

关闭 gate 时必须同时更新：

- 本文档对应行的 `Status`，把 `open` 改为 `closed`。
- `docs/HANDOFF.md` 的当前工作状态或下一步。
- 对应 `.planning/STATE.md` / `.planning/REQUIREMENTS.md` 的验证记录。
- 最终回复里的当前会话验证证据。

不能只因为 build 或 simulator test 通过就关闭真实设备 gate。真实 iPhone UAT 可以由用户确认，也可以由 agent 在完成安装前数据安全检查后执行并记录证据。
