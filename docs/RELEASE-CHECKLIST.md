# Ownlight 发布检查清单

本文档用于把当前项目收口成可验证的 App Store 与公开源码版本。它不是功能路线图，而是发布门禁。

## 版本边界

v0.1 的目标是交付一个稳定的私有时间线闭环：

- iPhone 可以在无 Mac、无 iCloud、无网络时发布、浏览、搜索和管理个人 Moments。
- `This iPhone` 的本地 SQLite 是默认 source of truth；iCloud/CloudKit 是当前 opt-in 多设备同步层。Mac server/admin 只作为 legacy 归档、恢复、诊断或 API 参考保留。
- 文本、图片、语音、视频、评论、收藏、搜索筛选、AI media summary 都能在日常使用中形成闭环。
- Share Sheet import、Smart Tags、AI 音频标题写回、local export 和 Settings 管理入口不破坏主时间线简洁性。
- Timeline 保持简洁，低频诊断和维护能力放在 Settings 或文档里；legacy Admin UI 不作为普通用户入口。
- iPhone 可以创建 local archive export package，并能把该 package 导回空的本机资料库做恢复演练；它不是非空资料库 merge、覆盖式 restore 或新手机一键迁移。legacy Mac Admin 仍可创建 migration-first export package，并把 export package 导入到 staged data directory。

v0.1 收口后，只接受以下类型变更：

- 阻塞真实使用的 bug。
- 数据安全、同步安全、媒体恢复相关修复。
- 安装、配置、文档、发布材料清理。
- 不改变产品语义的小范围体验修补。

## 本地启动门禁

新用户或新机器优先使用：

```bash
npm install
npm run verify:ios:low-impact
```

通过标准：

- `npm install` 成功。
- iOS generic low-impact build 成功。
- 不启动 Simulator、不要求 legacy server/admin。

## Legacy Server/Admin 验证门禁

仅当本轮修改 `server/`、`admin/`、legacy sync/API 或 archive 相关代码时运行：

```bash
npm run verify:server
npm run server:dev
curl -fsS http://127.0.0.1:3210/api/v1/health
npm run doctor:runtime
PRIVATE_MOMENTS_SMOKE_PASSWORD="<read-from-server-env>" npm run doctor:sync
```

通过标准：

- TypeScript typecheck 通过。
- Server build 通过。
- Admin build 通过。
- Health endpoint 返回成功。
- legacy Admin UI 可以登录并查看 storage、sync、AI summary diagnostics。
- Runtime doctor 不再发现旧目录、旧 LaunchAgent cwd、旧 SQLite 路径或旧虚拟环境 shebang。
- Sync doctor 没有 pending/rejected sync、media、AI summary 或 maintenance job 的阻塞项。

## iOS 验证门禁

```bash
cd ios
xcodegen generate
xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug -jobs 2 CODE_SIGNING_ALLOWED=NO build
```

等价脚本：

```bash
npm run verify:ios:low-impact
```

真实设备验证：

```bash
npm run ios:device
```

通过标准：

- App 可以安装到配对 iPhone。
- 不配置 legacy Server URL 时，本机发布、浏览、搜索、导出和 AI provider 设置仍可用。
- iCloud 开关默认关闭；开启后通过 CloudKit private database 同步，不要求 Ownlight 账号或 Server URL。
- 前台、后台再回前台、手动复制/同步动作都不会造成 timeline 丢失或重复。

## 产品 UAT 清单

每个候选版本至少手工验证一次。权威 gate 状态记录在 `docs/UAT-GATES.md`；release candidate 前必须运行：

```bash
npm run doctor:app-store
npm run verify:release-gates
```

以下是人工验证范围摘要：

- 发布纯文本 Moment。
- 发布图片 Moment。
- 发布语音 Moment，播放结束后回到初始播放状态。
- 发布视频 Moment，滑到视野中可静音自动播放。
- 发布带文本的图片、语音、视频 Moment。
- 从 Photos / Files / Safari 等系统 Share Sheet 使用 `Save to Ownlight` 导入内容，确认主 App Composer 打开、可编辑并成功发布。
- 主界面评论按钮能打开输入框，评论后滚动到最新评论位置。
- 长按评论能出现确认删除提示。
- 搜索支持模糊命中和媒体类型筛选。
- 按月份、收藏、评论、命中筛选可用。
- AI media summary 生成后显示 `Summary ready`，点击进入可阅读 Markdown-like summary。
- 如果 audio summary 失败，UAT 要能区分 transcription 阶段失败、text provider/API key/model/quota 失败、网络超时和 provider 暂时不可用。
- 新语音未手写标题时，AI ready 后可把短标题写入正文顶部；已有 `#` / `##` 标题或关闭 `AI Title Auto-Insert` 时不自动写入。
- 手动主标签、主题标签筛选、Settings > Tags 的 archive/restore/delete/merge/alias/color 管理可用；新语音的 AI 建议标签能在 summary ready 后同步出现。
- Settings > iCloud 可以看到 iCloud account、sync toggle、last sync/last error 和 `Sync Now`。
- Settings > Storage & Export 可以看到本机 storage、local export/import 和诊断。
- legacy Mac Admin 的 Archive & Export / Backups 区域可以作为历史维护路径创建、列出、校验、恢复并 promote 备份快照。

如果某一项暂时只能由用户肉眼确认，关闭 gate 时必须把用户确认写进 `docs/UAT-GATES.md`、`docs/HANDOFF.md` 和 `.planning` 验证记录。

## iCloud / CloudKit 收口门禁

CloudKit 第一阶段工程主路径已完成并关闭 `UAT-M017-CLOUDKIT-CROSS-DEVICE`。后续可以把 `iCloud Sync` 作为可选跨设备同步能力纳入 App Store v1 文案，但必须保持 local-first、opt-in、同 Apple Account、private iCloud database、无 Ownlight 账号、无开发者服务器同步前提等边界。

已完成的当前证据：

- Apple Developer release App IDs、App Group、iCloud container、entitlements 和真机 signing 已验证。
- 真实 iPhone/iPad guarded CloudKit smoke test 已通过。
- 普通 text/audio Moment、media metadata/assets、Timeline AI summary artifact 和 comments 已能自动跨 iPhone/iPad 同步。
- 首次本地库上传准备、derived-content backfill、optional derived orphan skip、missing-parent recovery、manual multi-batch drain、empty/sample-only second-device pull 和非空第二设备阻止静默合并/覆盖均已有自动化或真实设备 checkpoint。
- Favorite、pin、topic/tag/alias/assignment、check-in item/entry/media、ready check-in AI summary、app preference allowlist 和 Composer/Edit draft metadata 已接入 `iCloud Sync` 开启后的 CloudKit pending queue，并有 focused tests/build 覆盖新增入队行为。
- 用户已确认草稿、Settings preference、check-ins、delete/tombstone、编辑媒体增删和新语音 Moment summary/comment 路径在真实设备上没有明显问题。
- 收口容器检查确认 SQLite health、pending queue、provider secret exclusion 和两端实体一致性；一次性 `cloudkit_full_reconcile_v1` full private-zone pull 用于恢复历史遗漏的可选派生记录。

提交 App Store 前仍需复核：

- 真实 quota/full-storage 没有人为耗尽演练；如果截图、Review Notes 或支持文档要描述 quota/网络恢复，需要先重跑或降低措辞。
- Privacy Policy、App Privacy Label、screenshots、onboarding 和 App Review Notes 必须和最终 build 的实际 CloudKit 行为一致。
- 若后续再改 CloudKit schema、initial upload、media asset、delete/tombstone、preference/draft 或 local apply 逻辑，需要重新抽测两台真实设备。

## 数据恢复门禁

legacy archive 维护路径仍应满足：

- Admin 可初始化 backup repository；repository 可选本机目录或用户明确选择的 iCloud Drive 路径。
- 底层 backup 使用 restic deduplicated snapshots；项目自动管理 `.private-moments-restic-key`，用户不需要记备份密码。
- Admin 清楚说明：谁同时拿到 repository 和 key 文件，就可以恢复 archive；这不是额外的加密保险箱。
- 支持立即备份和每日固定时间定时备份。
- 支持 snapshot list/check。
- Restore 必须恢复到新数据目录，不能直接覆盖当前数据。
- Promote preparation 前必须验证恢复目录、进入 maintenance mode、创建 pre-promote snapshot，并要求强确认。
- 当前 v0.1 promote 不做 live SQLite hot swap；通过 `archive/pending-promote.json` 输出 `PRIVATE_MOMENTS_DATA_DIR` 和 `DATABASE_URL` restart instructions，operator 停止 server、切换 env、重启 server。
- 普通 sync/media/AI 写入在 restore/promote 期间被暂停。

- Export 支持全量和日期范围。
- Export package 以 JSON manifest/metadata 为权威，Markdown 只是预览。
- Export 包含 media、comments、tags、AI summary/title metadata、archived/soft-deleted 未永久清理状态。
- Export 不包含 auth token、session、device runtime state。
- Import 只导入到新/空数据目录，并保留 archive IDs/timestamps/generated metadata；导入后重新初始化 sync/outbox/device 状态。

自动化演练入口：

```bash
npm run doctor:archive
```

通过标准：

- live SQLite 的临时副本 `quick_check` 通过。
- report 中 posts/media/check-ins/server changes 统计符合当前 archive 预期。
- 未删除 media 引用的文件存在。
- restic 可用，archive config 可读。
- 没有遗留的 `archive/pending-promote.json` 挡住下一次 restore/promote 演练。
- 如果遗留了 `archive/pending-promote.json`，Admin 必须能把它识别成 stale/malformed 并提供安全清理入口，而不是继续把旧 handoff 当成 active truth。

## AI 质量门禁

```bash
npm run doctor:ai
```

通过标准：

- 新 ready summary 使用当前 prompt version，标题不超过当前约束。
- Weekly Review 使用当前 prompt version，anchors 指向仍存在的 active posts。
- `ai_usage_events` 有可用的 feature/model/status/token 记账，不包含私密正文。
- 历史旧 summary/review 可以作为 warning 记录，但不能掩盖新生成路径的回归。

## 单机 iPhone 稳定门禁

发布候选版本必须先证明单机 iPhone 路径可信：

- 首次安装后不配置 legacy Mac server，也能创建文字、图片、语音和视频 moment，并能重启后继续看到本地内容。
- Settings 首页以 `This iPhone`、`iCloud`、`Storage & Export`、`AI & Analysis` 为主，不把 Mac/server 登录当成默认起步。
- `Storage & Export` 承诺当前 local export 和空资料库 local import；`Import Archive` 必须说明不会 merge 或覆盖已有本机数据，也不能暗示本版本支持一键迁移到已有资料库的新手机。
- `PrivacyInfo.xcprivacy`、Info.plist 权限文案、AI/provider 隐私说明和 release docs 口径一致。

## App Store 前置准备

`1.0 (3)` 已通过审核并发布。`1.1 (4)` 继续跳过 TestFlight，已使用 English-first metadata/screenshots 直接提交 App Store，当前为 `Waiting for Review`；现有海外 availability 保持不变。

未来进入 TestFlight / App Store 准备时，至少需要完成：

- 运行 `npm run doctor:app-store`，确认 UAT gates、Info.plist 权限文案、PrivacyInfo required reason API、iCloud/App Group entitlements、public fallback URL、Privacy/Support URL、analytics/crash/ad/tracking SDK 漂移和明显 required-reason API 漂移均通过。
- 使用 `docs/APP-STORE-SUBMISSION-DRAFT.md` 填写或复核 App Privacy Label、export compliance、metadata、Review Notes、TestFlight 文案和截图计划。
- 使用 `docs/APP-STORE-UAT-RUNBOOK.md` 跑最终候选 build 的真实设备 UAT，尤其是 export/import、无网、权限拒绝、性能和 accessibility smoke。
- 明确 iCloud 分层：CloudKit private sync 是当前 opt-in 多设备同步层；iCloud Backup 只能作为系统备份 eligibility 信息；iCloud Drive 仅是用户选择的 legacy Mac Archive repository path。
- 稳定 bundle id、App Group、signing config、entitlements 和本地 override 边界。
- 维护 `PrivacyInfo.xcprivacy`，只声明当前 build 实际使用的 required-reason API；不要为未启用 CloudKit、非空资料库 merge 或覆盖式恢复提前声明产品承诺。
- CloudKit 提交前，确认 container、entitlements、provisioning、默认 source build、真实设备 owner build、普通 Moment 自动同步、首次本地库上传、媒体 asset 同步、派生内容同步、第二设备恢复、非空第二设备保护和 failure copy 仍符合当前 build。
- CloudKit 第一阶段 UAT 已关闭；App Store 文案可以描述可选 iCloud Sync，但不要承诺实时同步、跨 Apple ID 共享、非空库自动 merge、开发者服务器托管同步或 100% 不受 iCloud quota/系统状态影响。
- 明确隐私说明：哪些数据只在 iPhone，哪些数据进入 iCloud/CloudKit，哪些 legacy server/admin 路径可能保存历史数据，哪些文本可能发送给外部 AI provider。
- 确认日志、diagnostics 和 `ai_usage_events` 不包含正文、transcript、prompt、provider raw response 或 API key。
- 准备可截图/可录屏的真实设备 UAT 路径：文本、图片、音频、视频、评论、Share Extension、Sync Now、后台恢复。
- 准备数据恢复证据：backup、restore、export/import、promote preparation 的当前 checkout 演练结果。
- 提交前重新核对最新 App Store Review Guidelines 和 App Privacy 要求；本地 doctor 只证明当前 checkout 的可机械检查项，不替代 App Store Connect 最终填写和 Apple 最新规则复核。

## 开源前门禁

公开源码必须完成：

- 仓库不包含 `server/.env`、真实数据库、媒体文件、设备日志、API key、私人 Tailscale IP。
- `.gitignore` 覆盖本地数据、构建产物、依赖目录和运行时缓存。
- `README.md` 能让新用户通过 `npm run setup:local` 完成本地安装。
- `docs/OPERATOR-RUNBOOK.md` 覆盖常见启动、安装、排查路径。
- `docs/OPEN-SOURCE-READINESS.md` 中没有未解释的 release-blocking 项，剩余风险有明确处理路径。
- 明确 license。
- 明确外部 AI provider 的隐私边界。
- 补齐最小数据安全闭环：backup、restore、promote preparation、export/import 的操作说明或脚本。

当前工作区扫描入口：

```bash
npm run doctor:release
```

`doctor:release` 只覆盖当前 checkout。公开仓库必须从当前已审计 tree 创建 clean history，不能把 private development repository 的旧提交和 backup branches 一起公开。

2026-07-17 已完成首个公开 checkpoint：`https://github.com/Popcornnnnnnnn/ownlight` 为 public，`v1.1.0` 为 MIT source-only GitHub Release，不包含 IPA 或 owner signing material。公开仓库 GitHub Actions 的 source 与 iOS jobs 均通过，iOS job 覆盖 Xcode 16.4 generic-device build。

## 当前结论

截至 2026-07-17，`1.0 (3)` 已发布并在海外 174 个国家或地区可用，China mainland `Not Available`。CloudKit 第一阶段和真实 iPhone/iPad UAT 已关闭。English-first `1.1 (4)` 已上传、绑定并提交 App Review，当前为 `Waiting for Review`。公开源码已在新的 `Popcornnnnnnnn/ownlight` clean-history repository 发布；现有 `Popcornnnnnnnn/private-moments` 保持 private。公开版本 `v1.1.0` 只发布 source，不上传 owner-signed IPA，GitHub Actions source/iOS jobs 均为绿色。当前剩余发布动作是监控 App Review、批准后 manual release，并验证 App Store 安装版本。
