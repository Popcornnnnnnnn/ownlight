# App Store UAT Runbook

Last updated: 2026-06-08

本文档用于 App Store / TestFlight 前的真实设备验收。它只定义可重复路径和记录方式，不替代 `docs/UAT-GATES.md` 的最终 gate 状态，也不替代 App Store Connect 上传后的隐私报告和审核反馈。

## UAT 原则

- 优先用真实 iPhone / iPad，不为了非视觉验证启动 Simulator。
- 日常使用的正式 `Ownlight` 和隔离的 `Ownlight UAT` 分开测试；首次体验、空资料库和破坏性恢复演练优先用 `Ownlight UAT`。
- 每次 UAT 记录 build、设备、iOS 版本、是否登录同一 Apple Account、网络状态、是否开启 `iCloud Sync`、是否配置 AI provider。
- 不把“没有看到报错”当成完整同步证据；跨设备路径至少要检查内容、媒体、评论、AI summary、check-ins、drafts/preferences 和删除传播。
- 如果某项只能人工肉眼确认，关闭 gate 时把用户确认写回 `docs/UAT-GATES.md`、`docs/HANDOFF.md` 和 `.planning/STATE.md`。

## 预检

本地 source-level preflight:

```bash
npm run doctor:app-store
npm run verify:release-gates
npm run verify:ios:low-impact
```

最终 archive / TestFlight 前还需要：

- 重新运行 `npm run doctor:app-store`。
- 用最终 archive 检查 Xcode / App Store Connect privacy report。
- 在 App Store Connect 里确认 App Privacy Label、Export Compliance、age rating、category、territories 和 China mainland availability 提示。

## Common App Store UAT Path

每个 release candidate 至少跑一次：

1. First launch：新装 `Ownlight UAT`，确认 welcome page 只出现一次，Start 按钮可进入 Timeline。
2. Empty timeline：确认 welcome sample moment 可读、可删除，删除后不自动恢复。
3. Text moment：发布一条短文本和一条长 Markdown 文本，重启 App 后仍存在。
4. Media moment：发布图片、相机拍摄图片、语音、视频；确认播放、缩略图、详情页和编辑页可用。
5. Share Sheet：从 Photos / Files / Safari 分享内容到 `Save to Ownlight`，确认主 App Composer 打开、可编辑并发布。
6. Timeline interaction：收藏、置顶、删除、评论、搜索、日期跳转和筛选都可用。
7. AI optional path：不开启 AI 时核心记录可用；配置 provider 后，AI consent 出现且只出现于外发前；语音 summary 可生成、失败时错误文案可理解。
8. Tags / Areas：AI topic tags 进入固定 Areas，普通筛选不显示 legacy Primary。
9. Calendar / Reviews：Calendar 可按日期查看；AI off 且无历史 review 时不强行展示 Weekly Review。
10. Check-ins：创建 item、打卡、编辑时间、删除 entry，确认不会选到未来时间。
11. iCloud Sync：开启 `iCloud Sync` 后跨 iPhone/iPad 验证 text/media/comments/AI summary/check-ins/drafts/preferences/delete/tombstone。
12. Settings：`This iPhone`、`iCloud`、`Storage & Export`、`AI & Analysis`、`Tags`、`Appearance`、`Language`、`Display` 扫一遍，确认普通用户看不到 CloudKit smoke/default-zone diagnostics。

## Local Export / Import UAT

目标是证明最小本机恢复闭环，不证明非空资料库 merge、覆盖式 restore 或跨 Apple ID 迁移。

1. 在有真实样本数据的设备上打开 `Settings > Storage & Export`。
2. 运行 `Export Data`，确认导出前文案说明 package 可能包含私密内容且不加密。
3. 保存导出包到可信位置，例如 Files 的临时测试目录。
4. 新装或清空 `Ownlight UAT`，确保目标资料库为空、没有 pending local/cloud sync 工作。
5. 在 `Settings > Storage & Export` 运行 `Import Archive`，选择刚才的导出包。
6. 预览导入内容，确认它只导入到空资料库，不 merge、不覆盖已有资料库。
7. 导入后检查 Timeline、media、comments、tags、AI summaries、Weekly Reviews、check-ins 和 timestamps。
8. 确认导入包不恢复 AI API key、provider credentials、raw private transcript text、CloudKit runtime queue/cursor/cache 或 legacy session token。
9. 删除临时导出包，确认测试记录写入 `docs/UAT-GATES.md`。

通过标准：

- 空资料库导入后，主要内容可浏览、媒体可播放、评论/tag/summary/check-in 元数据保留。
- AI provider 需要重新配置；导入后没有凭据泄露。
- `iCloud Sync` 不因为导入自动打开；只有用户主动开启后才开始 CloudKit 同步。

## Data Deletion UAT

用于验证无账号版本的数据删除口径：

- 删除单条 Moment 后，Timeline 和详情页消失；若 `iCloud Sync` 已开启，另一台设备最终也删除。
- 删除评论、AI summary、check-in entry 和 tag 后，相关 UI 不再显示。
- 关闭 `iCloud Sync` 只停止未来同步，不应声称自动删除已经在 iCloud private database 中的内容。
- 删除 App 会删除本机 app container；不要把这写成自动删除 iCloud、导出包或 AI provider 侧副本。
- 导出包是普通用户文件，保留在用户保存的位置，必须由用户在 Files / iCloud Drive / AirDrop destination 中自行删除。
- AI provider 数据按用户选择的 provider 政策保留；App 内删除 provider profile 只清除本机配置和 Keychain API key。

当前 v1 没有 Ownlight 账号，也没有开发者运营的账号数据删除入口。如果未来加入账号、托管 AI、诊断上传或订阅，必须重新设计账号删除和 App Privacy Label。

## Offline / Permission UAT

- Airplane Mode 下发布 text/photo/audio moment，重启后仍存在。
- 离线时 `iCloud Sync` 不阻塞本地记录；恢复网络后再补同步。
- 拒绝 Photos/Camera/Microphone/Speech/Local Network 权限时，App 不崩溃，并给出可理解 fallback。
- AI provider 网络失败、quota/error、unsupported response 不应把已配置 provider 错标为未配置。

## Performance Smoke

真实设备上至少检查：

- 800+ moments 的 Timeline 首屏、滚动、详情页打开、返回。
- 大媒体缩略图滚动不会明显卡死。
- 搜索和 filter 输入不阻塞主界面。
- Composer / Edit Moment 长文本编辑时键盘和光标不明显卡顿。
- `Settings > Storage & Export` 统计和导出操作不会让 App 无响应。

如果 Mac 资源紧张，本地验证优先选择 generic build 和真机安装，不启动 Simulator。

## Accessibility Smoke

提交前至少做一轮最小审计：

- VoiceOver 可以完成 first launch、创建 moment、打开详情、删除确认、进入 Settings 和 export/import。
- Larger Text 下 Timeline row、Composer、Settings grouped rows、AI summary sheet 不出现明显文本重叠或按钮不可点。
- 重要按钮有可理解 label；图标-only 操作不能完全依赖视觉猜测。
- 深色/浅色模式下，文字、分隔线、按钮和 destructive actions 对比可读。

没有完整验证前，不在 App Store metadata 中主动强调 accessibility 支持范围。

## UAT 记录模板

```text
Date:
Build:
Device / iOS:
Install target: Ownlight / Ownlight UAT
Apple Account / iCloud status:
AI provider status:
Network:

Path:
Result:
Issues:
Evidence:
Follow-up:
```
