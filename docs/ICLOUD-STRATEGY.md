# iCloud 策略说明

Last updated: 2026-06-08

## 当前结论

Ownlight 的 iCloud 方向已经从设计阶段进入 M017 第一阶段 UAT closed 状态。产品仍然是 iPhone local-first：本地 SQLite 是默认 source of truth，`iCloud Sync` 是用户显式开启的可选跨设备同步层。

不要把 iCloud 混成一个大功能。当前有三层边界：

1. **CloudKit private sync**：当前 App Store v1 可描述的可选同步能力。它使用用户 Apple Account 的 private CloudKit database，不需要 Ownlight 账号，也不经过开发者服务器同步。
2. **iCloud Backup 信息**：系统级备份说明。App 可以解释本地 app data 可能受 iOS iCloud Backup 影响，但不能承诺读取 Apple 端精确备份状态。
3. **iCloud Drive 作为 legacy Archive repository 位置**：历史 Mac/Admin 维护能力，只是用户选择的 filesystem path，不是当前 App Store 首发同步策略。

## 已完成的第一阶段同步范围

M017 已关闭 `UAT-M017-CLOUDKIT-CROSS-DEVICE`。真实 iPhone/iPad UAT 和容器 spot-check 已覆盖：

- ordinary text/audio/media moments
- media metadata 与 asset upload/download
- comments
- topic tags、tag aliases、post-tag assignments
- check-ins items、entries、media、ready check-in AI summaries
- Timeline AI summaries 与 Weekly Reviews
- synced app preference allowlist
- composer/edit draft metadata
- delete/tombstone 与 edit-media add/remove
- first-device initial local-library upload
- empty second-device pull
- non-empty second-device initial-sync protection
- missing-parent recovery、optional derived orphan skip、一致性自愈 `cloudkit_full_reconcile_v1`
- provider secrets/raw transcript/runtime queue/cache exclusion spot-check

`iCloud Sync` 关闭时，普通使用仍保持本机优先，不进入 CloudKit queue。

## 不同步内容

CloudKit v1 明确排除：

- AI provider API key、provider profile、Base URL、model 配置
- raw prompts、raw transcripts、AI usage logs、provider/model/token/error diagnostics
- Mac/server runtime、legacy sync queue、device identity、server URL
- local caches、diagnostics、temporary files、new draft media bytes
- welcome sample / UAT-only data
- public sharing、多人协作、开发者托管账号数据

## 用户体验边界

- Settings 只展示用户能理解的 `iCloud Sync`、账号状态、必要说明和低频 `Sync Now`。
- 不展示 CloudKit container ID、smoke test、default-zone probe、per-moment sync badge 或工程队列细节。
- App Store 文案可以描述“可选 iCloud 同步”，但不能承诺 hard realtime、非空设备自动 merge、无限 quota、开发者托管云同步或跨账号共享。
- 真实 quota/full-storage 未人为耗尽；最终提交前需要用最终 archive 复核 failure copy、Privacy Policy、App Privacy Label、screenshots 和 Review Notes。

## 上架前剩余检查

- `npm run doctor:app-store`
- `npm run verify:release-gates`
- final Xcode archive privacy report
- App Store Connect App Privacy Label
- screenshots / metadata / Review Notes 与最终 build 行为一致性
- 无网、iCloud 不可用、权限拒绝、quota/full-storage copy 的 release-grade smoke
