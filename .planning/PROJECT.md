# 项目概览

## 说明

这是当前仓库的结构化项目概览。后续项目事实、路线和决策统一在 `.planning/` 下维护；旧双轨 GSD 工作流材料已从 active checkout 移除，历史边界见 `.planning/LEGACY-GSD-ARCHIVE.md`。

## 项目是什么

Ownlight 是一个**本地优先、无公开观众、以时间流为核心**的个人时间线系统。

- iPhone 是主要采集与浏览入口。
- iPhone 本地 SQLite 是默认 source of truth；无网络、无 iCloud、无 server 时也应能完成日常记录和浏览。
- iCloud / CloudKit private database 是当前可选跨设备同步方向。
- `server/`、`admin/` 和旧 API/sync 文档作为 legacy compatibility、archive/diagnostics、维护实验和历史数据兼容层保留，不再是当前产品默认运行形态。
- 产品目标不是公开云服务，而是“个人私有表达空间”。

## 当前架构

- iOS：SwiftUI + 本地 SQLite + 本地 media cache + Share Extension + iPhone-direct AI + CloudKit private sync。
- CloudKit：独立 `local_cloudkit_*` metadata tables、pending queue、payload mapper、record encoder/decoder、transport、local apply 和 media asset transfer。
- Transcription gateway：可选 OpenAI-compatible transcription helper，只作为高级转写 endpoint，不是默认产品依赖。
- Legacy Server/Admin：Node/Fastify/Prisma/SQLite 与 React Admin，保留给历史兼容、archive/diagnostics 和低频维护。
- Shared：`shared/openapi.yaml` 与 `shared/sync-protocol.md` 主要记录 legacy API/sync contract。

## 当前产品面

当前已经落地的主要能力：

- Timeline / Calendar / Check-ins 三个主入口。
- 文本、图片、音频、视频 moments。
- Share Extension 导入。
- 本地优先草稿、离线兼容队列、延迟重试。
- iPhone-direct AI media summaries / Weekly Review / topic tags。
- iCloud / CloudKit opt-in sync：普通 Moment create/update/delete、整条 Moment 删除 tombstone、编辑媒体增删、媒体 metadata/asset、comments、tags、check-ins、AI summaries、weekly reviews、drafts/preferences 已进入真实设备 UAT；iPad full pull 已验证到数据库层。
- Smart Tags。
- Calendar Review 与 Weekly Review。
- Check-ins item / entry / image-media / time insights。
- iOS Settings / Diagnostics 优先的运维与诊断入口。

## 当前工作方式

- `.planning/` 是结构化事实源，`docs/` 是稳定人类文档层。
- `main` 是固定集成线；并行功能开发优先用独立 worktree。
- 高风险改动要升级到 milestone / slice planning。
- 真机与人工验收门禁统一记录在 `docs/UAT-GATES.md`。

## 当前里程碑位置

- 已完成里程碑：16 / 17
- 当前活跃里程碑：M017 App Store Readiness And Product Maturity
- 当前正在推进的重点：App Store English-first `1.1 (4)` 与 GitHub `v1.1.0` clean source release 双发布收口。

## 继续阅读

- 当前决策：`.planning/DECISIONS.md`
- 当前状态：`.planning/STATE.md`
- 当前路线：`.planning/ROADMAP.md`
- 当前验收门禁：`docs/UAT-GATES.md`
