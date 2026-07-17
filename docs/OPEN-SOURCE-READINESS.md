# 开源发布评估

Last updated: 2026-07-17

当前结论：**Ownlight 已达到首个公开源码 checkpoint。公开发布采用新的 `Popcornnnnnnnn/ownlight` 仓库和单一干净历史；现有私有开发仓库 `Popcornnnnnnnn/private-moments` 继续保持 private，不公开旧提交、backup branches 或内部 release history。**

公开仓库发布 MIT source release，不分发可安装 IPA。Apple signing、bundle id、App Group 和 CloudKit container 必须由每位开发者使用自己的 Apple Developer account 配置。

这个项目已经具备个人使用闭环，但开源发布需要额外关注隐私边界、安装路径、历史敏感信息和数据安全。

## 已具备的基础

- 根目录已设置 npm workspaces，server 和 admin 可以统一安装依赖。
- `LICENSE` 已选择 MIT。
- 新增 `npm run setup:local`，用于新机器初始化、生成 Prisma client、应用数据库迁移、构建 Admin UI 和 Server。
- `server/.env.example` 使用占位配置，没有包含真实 API key。
- 新增 `docs/NETWORKING.md` 和 `.env.local.example`：公开默认只要求用户配置 `Server URL`，LAN、Tailscale/private VPN、Cloudflare Tunnel 或其他受保护 HTTPS endpoint 都只是可选网络层；个人 device name、Apple Team ID、bundle id、App Group 和 fallback URL 通过 ignored 本地配置覆盖。
- iOS 公开默认 identifiers 已迁移到 `ios/Config/Public.xcconfig`，本地 override 由 ignored 的 `ios/Config/Local.xcconfig` 承载。
- `.gitignore` 已覆盖 `server/.env`、`server/data/`、`server/.venv/`、`server/dist/`、`admin/dist/`、`ios/build*`、`ios/PrivateMoments.xcodeproj/`、`node_modules/`、`.tmp/` 等运行时或生成内容。
- 文档已经覆盖产品定位、技术设计、操作 runbook、integration guide、design principles、workflow 和 handoff。
- README 通过可重复 simulator demo fixture 维护 6 张公开截图：Timeline、Detail、Calendar、Check-ins、Settings 和 Tags。
- 当时的 legacy server-side AI media summary provider credential 设计为只存在 Mac server 环境变量中；当前 App Store / iPhone-first 路径改为用户在 iPhone Settings > AI & Analysis 配置 provider，API key 存在 iPhone Keychain。
- 2026-07-17 公开策略改为 clean snapshot：只把当前已审计 checkout 写入新的 public repository，不复用旧 private repository 的 Git history。

## 剩余发布风险

### 1. Git history 风险通过 clean snapshot 隔离

`npm run doctor:release` 负责扫描当前 tracked checkout。公开仓库从已审计的当前树创建新的单一提交，因此不携带私有开发仓库的历史。后续只需要继续扫描 public repository 自己的新提交和 release tag。

### 2. 最小数据安全闭环已经有主路径，仍需最终发布级演练

项目保存的是私人 timeline、图片、音频、视频、评论和 AI summary。公开前至少需要给出明确的 backup/restore/export 路径。

当前进展：

- M009 Phase A 已加入 Mac Admin 管理的 restic backup/restore：repository config、项目管理 `.private-moments-restic-key`、manual backup、daily schedule、snapshot list/check、staged restore 和 promote preparation。
- M009 Phase B 已加入 Mac Admin 管理的 export/import：全量或日期范围导出、JSON manifest/metadata 权威包、Markdown preview、media payload、导入到 staged data directory，并排除 auth/session/device runtime state。
- `docs/OPERATOR-RUNBOOK.md` 已说明 repository + key file 的恢复语义，iCloud Drive 只是用户选择的文件夹，不是 app-managed cloud upload。
- 当前 promote 是 restart-safe preparation：写 `archive/pending-promote.json`，operator 停止 server、切换 env、重启。

持续维护仍需要：

- 用干净数据目录演练 import/restore 后 health check、Admin UI 和 iOS sync recovery。
- 明确公开版中 `.planning/`、历史日志和示例数据的处理策略。
- 运行 `npm run doctor:archive`，保留本轮 archive drill report 作为当前 checkout 的数据恢复演练证据。

建议 history scan 门禁：

```bash
git log --all --stat -- server/.env server/data
git grep -n "PRIVATE_MOMENTS_INITIAL_PASSWORD\\|AI_SUMMARY_API_KEY\\|sk-" $(git rev-list --all)
```

本次轻量扫描结果：

- 当前 iOS `Info.plist` 中的个人 Tailscale exception 已移除，开发期仍依赖 `NSAllowsArbitraryLoads` 和 `NSAllowsLocalNetworking`。
- `server/.env.example` 只包含 AI API key 占位示例。
- `scripts/setup-local.sh` 只包含写入本地 password 的脚本逻辑，不包含真实 password。
- 2026-06-08 已从活跃 checkout 移除 `.planning/_legacy-gsd/` 历史规划树，并以 `.planning/LEGACY-GSD-ARCHIVE.md` 记录清理边界。旧细节只从 git history 追溯。
- 2026-05-10 起，当前 checkout 可用 `npm run doctor:release` 做重复扫描；它会检查 license、tracked API key 形态、个人配置片段、ignore 边界、公开 docs 和 planning/archive release policy。它不扫描 Git history。

### 3. 外部 AI provider 隐私说明仍需更面向外部用户

AI media summary 会把本地转录后的文本发送给配置的外部 API。公开发布前需要在 README 或 SECURITY 文档中明确：

- 音频和视频文件本身是否发送给第三方。
- 转录文本是否发送给第三方。
- API key 存储在哪里。
- 用户如何完全关闭 AI summary。
- provider 超时、失败、重试时会记录哪些日志。

### 4. `.planning` 与历史归档公开策略

`.planning/` 是当前项目事实源。旧 `.planning/_legacy-gsd/` 工作流历史已在 2026-06-08 从活跃 checkout 移除，避免把内部过程、个人偏好、旧 UAT 记录和过期项目叙事带入未来公开快照。

当前策略：公开仓库以 `README.md`、`SECURITY.md`、`CONTRIBUTING.md` 和 `docs/` 作为人类读者入口；`.planning/` 只保留当前事实源，不公开历史 phase execution artifacts。旧 GSD 和私有开发历史只保留在 private repository。

## 建议保留为私有的内容

- `server/.env`
- `server/data/`
- `server/.venv/`
- `server/prisma/dev.db`
- 任何真实媒体文件、缩略图、录音、视频。
- iPhone 设备 container dump。
- 本机 Tailscale IP、Tailnet 名称、个人设备名。
- 外部 AI provider API key、base URL、日志里的请求内容。

## 开源发布材料建议

最小公开包应包含：

- `README.md`：项目是什么、适合谁、如何本地启动、如何配置 iOS。
- `LICENSE`：明确复用边界。
- `SECURITY.md`：隐私、安全、AI provider 和 secret 处理说明。
- `docs/PRD.md`
- `docs/TECH-DESIGN.md`
- `docs/OPERATOR-RUNBOOK.md`
- `docs/INTEGRATION-GUIDE.md`
- `docs/DESIGN-PRINCIPLES.md`
- `docs/RELEASE-CHECKLIST.md`

## 每次公开发布

1. 运行 `npm run doctor:release`、`npm run doctor:app-store` 和 `npm run verify:ios:low-impact`。
2. 检查最终 public tree 不包含 `.env.local`、`ios/Config/Local.xcconfig`、`.tmp`、设备数据或 signing material。
3. 确认 README、SECURITY、CHANGELOG、版本号和 App Store 产品边界一致。
4. 为 public repository 创建 signed source tag 和 GitHub Release；不要上传 owner-signed IPA。
