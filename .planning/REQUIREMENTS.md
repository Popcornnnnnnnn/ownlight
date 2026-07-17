# 需求概览

## 说明

这是当前仓库的活跃需求概览。后续 requirement 事实统一维护在 `.planning/` 下；旧 GSD requirement 历史已从 active checkout 移除，必要时从 git history 追溯；边界见 `.planning/LEGACY-GSD-ARCHIVE.md`。

## 当前需求状态

- Requirements Status：55 active · 9 validated · 0 deferred · 0 out of scope
- 当前活跃里程碑：M017 App Store Readiness And Product Maturity
- 当前 open gate：none

## 当前最高优先级需求

### 1. 单机 iPhone 发布稳定性优先于新功能扩张

- 下一阶段不以公开源码为目标，也不急于扩新模块。
- 优先把无 Mac、无 iCloud、无网络时的真实 iPhone 日常记录、浏览、搜索、AI provider 设置、local export 和空资料库 local import 打磨到稳定可依赖。
- iCloud/CloudKit、legacy server 和 backup/export 都是可选复制、归档或恢复层，不能重新成为普通使用的前置条件。
- 新增能力必须服务于稳定性、数据安全、未来 TestFlight/App Store 准备，或解决真实使用阻塞。

### 2. 数据安全与恢复演练必须保持当前证据

- Archive / export / import / restore 不只要“有功能”，还要有当前 checkout 的演练证据。
- 当前恢复承诺只到 iPhone local export + 空资料库 local import；文案必须避免暗示已经能非空库 merge、一键迁移或覆盖恢复。
- 恢复路径继续采用 restart-safe promote preparation，不做 live SQLite hot swap。
- iOS sync recovery、Admin health、doctor output 必须能证明恢复后的数据路径可用。

### 3. iCloud 路径要分层，CloudKit 保持 opt-in

- iCloud Drive backup repository、iCloud Backup 信息、CloudKit private sync 是三件事，不能混成一个不清楚的“iCloud 支持”。
- 历史 Mac Archive repository 可放在用户选择的 iCloud Drive path；这不是 app-managed cloud upload，也不是当前产品主线。
- CloudKit private sync 是当前 opt-in UAT 能力，必须保护真实 iPhone 数据安全。
- 当前 `main` 已按小切片实现 CloudKit scaffold、transport、local apply、media asset transfer、首次本地库上传准备、普通 Moment/媒体/评论/Timeline AI summary 等派生内容同步、favorite/pin/tag/check-in/preference allowlist 入队、composer/edit draft metadata 实时入队、整条 Moment 删除子记录 tombstone 入队、编辑媒体增删入队、非空第二设备初始同步保护、普通用户可读的 CloudKit failure message 分类，以及一次性 full reconciliation 自愈 pull。
- `UAT-M017-CLOUDKIT-CROSS-DEVICE` 已关闭：真实设备 UAT 和容器 spot-check 已覆盖普通跨设备同步、派生内容、草稿/设置/check-ins、删除/tombstone、编辑媒体增删、secrets/provider config exclusion、SQLite health 和 pending queue。后续不能再把 CloudKit core sync 当成“仍未实现”的主线任务；新增 sync work 应进入独立 Backlog 或新 slice。
- App Store metadata 可以描述 `iCloud Sync` 作为可选跨设备同步能力，但必须保持 local-first、opt-in、同 Apple Account、private iCloud database、无 Private Moments 账号、无开发者服务器同步前提等边界。真实 quota/full-storage 未人工耗尽，v1 提交前已按当前 archive/source preflight 复核 App Privacy Label、Privacy Policy、screenshots 和 Review Notes；后续版本若改同步/隐私/AI 行为必须重新复核。
- 旧 `codex/apple-native-v1-direction` 分支只能作为历史参考；不得整支回灌或把其中旧 App/native 模式重新当作当前产品事实。

### 4. 分发配置需要稳定，并支持 App Store 与公开源码双发布

- Bundle id、App Group、signing config、entitlements、legacy fallback server URL、本地 override 边界要清楚稳定。
- `PrivacyInfo.xcprivacy`、Info.plist 权限文案和 release docs 必须按当前实际能力声明，不为未启用 CloudKit、非空资料库 merge 或覆盖式 restore 提前做产品承诺。
- App Store `1.1 (4)` 使用 English-first metadata/screenshots；公开源码使用新的 clean-history repository，不公开 private repository 历史。
- App Store policy 细节应在每次提交前重新核对最新官方规则。

### 5. AI 与数据复制必须解耦

- iPhone 本地 SQLite 是默认 source of truth；iCloud/CloudKit、legacy server 和 backup/export 都属于后续数据复制或恢复层。
- AI & Analysis 由用户在 iPhone 上配置 provider profiles；API credentials 只保存在本设备 Keychain，不进入 sync、iCloud、legacy server 或导出包。
- 普通音视频 summary/title/tags、check-in audio summary 和 weekly review 应走 iPhone-direct AI artifact path；现有 Mac-generated artifacts 继续显示为 historical data。
- 语音转录默认使用 iPhone on-device transcription；外部 transcription/audio-input provider 是 advanced option，核心数据流仍是 transcript -> text analysis。失败说明必须区分 transcription 阶段和 text provider/API key/model/quota/network 阶段。

### 6. 隐私与 AI provider 边界要适合未来商店审查

- 明确哪些数据只在 iPhone，哪些数据会进入 iCloud/CloudKit，哪些 legacy server/historical paths 仍可能保存数据，哪些文本可能发送给外部 AI provider。
- 日志与诊断只能记录 metadata、长度、状态、错误码，不记录私密正文、transcript、prompt 或 provider raw response。
- Public source onboarding 以 README、SECURITY、CONTRIBUTING 和 provider-neutral public defaults 为入口；不得暴露 owner signing、credentials、设备数据或私有开发历史。

### 7. 诊断与运维入口仍然优先放在 iOS Settings

- 日常 settings、monitoring、diagnostics、safe repair controls 默认优先 iOS。
- Legacy Admin 只保留给 Archive / promote / export-import / server logs / filesystem-process recovery 这类低频维护能力；普通产品路径不应暴露 Mac/server controls。

## 长期约束摘要

- 本地优先、默认无观众、时间流体验优先于数据库式管理体验。
- Timeline 保持克制，低频控制尽量放 toolbar menu、detail、settings、swipe actions。
- Check-ins 不能滑向 KPI dashboard，也不能混入 AI / streak / reminder / comments / pin / favorite 这些重社交或重习惯追踪特性。
- 所有 release claim 都要经过 `docs/UAT-GATES.md` 的真实设备或人工确认。
- 现有 private development repository 保持 private；公开源码通过独立 clean snapshot repository 和 source-only GitHub Release 分发。

## 历史需求归档

如果你要追溯旧工作流时期的逐条 requirement 原文、来源、validation 和 owning slice，请回到删除 `.planning/_legacy-gsd/` 之前的 git history；不要在当前 checkout 重新创建第二套规划树。
