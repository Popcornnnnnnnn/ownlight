# App Store 发布经验沉淀

Last updated: 2026-06-28

本文档记录 Ownlight v1 首次 App Store 上架过程中形成的可复用经验。它面向以后发布下一款 iOS App，不替代 Apple 官方文档和当时最新审核规则；真正提交前仍要以当前 build、App Store Connect 页面和最新 App Review Guidelines 为准。

## 一句话原则

App Store 审核最怕“能力声明、产品文案、实际行为”三者不一致。下一款 App 发布前，先让这三件事对齐，再去填表、打包和提交。

## 关键经验

### 1. v1 尽量简单

Ownlight v1 的低复杂度边界是审核顺利收口的基础：

- 无账号、无注册、无登录。
- 无 IAP、无订阅、无广告。
- 无第三方 analytics / crash SDK。
- 无开发者托管默认 AI 服务。
- 本地优先，iCloud 是用户自己的 private database，同步是 opt-in。

下一款 App 如果没有明确商业闭环，首版优先保持这种低外部依赖形态。账号、付费、默认后端、analytics 和托管 AI 都会显著增加隐私、审核、客服和合规成本。

### 2. Entitlements 只声明当前真实可见能力

Ownlight 首次被拒的原因是 `UIBackgroundModes = audio`：App 有录音和播放，但没有 reviewer 能看到的“后台持续音频”功能，因此 Apple 认为声明过度。

以后提交前必须逐项审计：

- Info.plist 权限文案是否对应当前真实功能。
- entitlements 是否只包含当前发布版需要的能力。
- background modes 是否有明确用户路径和审核说明。
- 如果声明后台能力、HealthKit、Location、Push、Sensitive Content 等高风险 capability，要准备 reviewer 可复现路径和必要录屏。

原则：不要为了未来计划、旧实验或保险起见多声明 capability。

### 3. BYOK / 自带 API Key 要预先解释

Ownlight 第二次被拒是因为 reviewer 把 AI provider API key 理解成“绕过 IAP 启用付费功能”。这类误解以后很可能还会发生。

如果下一款 App 支持用户填写 API key、Base URL、model 或 self-hosted endpoint，Review Notes 一开始就应写清楚：

- App 本身是否免费。
- 是否有 IAP、订阅、广告、购买链接或付费 tier。
- API key 是用户自己的 provider 凭据，不是 App license key。
- 核心功能是否不依赖 API key。
- 开发者是否提供默认托管服务。
- App 是否引导用户购买第三方数字服务。

可复用说明模板：

```text
This app does not sell, unlock, or enable any paid functionality through external mechanisms.
It has no in-app purchases, subscriptions, ads, purchase links, developer-hosted AI quota, or paid tiers.

The optional API key field is for interoperability with a user-owned or self-hosted compatible provider endpoint.
The API key is not an app license key and is not issued, sold, or managed by us.
Core app functionality works without configuring any API key.
```

如果 UI 里出现 `Pro`、`Upgrade`、`Provider Marketplace`、`Buy credits`、`premium model` 等词，极易被 3.1.1 误判；v1 尽量避免。

### 4. 隐私标签先做数据盘点，不要先套模板

Ownlight 能采用 `Data Not Collected` 的前提是：

- public build 没有开发者默认同步服务器。
- 没有 analytics / crash upload / ads / tracking SDK。
- AI 是用户自选 provider 或 self-hosted endpoint。
- API key 保存在 Keychain，不进 CloudKit、不进 export。
- raw transcript、provider raw response、diagnostics 不同步、不上传到开发者服务器。

下一款 App 先做数据表，再写 Privacy Policy 和 App Privacy Label：

- 数据在哪里产生。
- 是否离开设备。
- 谁能访问。
- 用途是什么。
- 是否 linked to user。
- 是否用于 tracking。
- 保留和删除方式是什么。

只要加入 analytics、feedback upload、developer-hosted AI、账号、客服附件上传或默认后端，`Data Not Collected` 就要重新判断。

### 5. App Store 发布是工程、产品和运营的合体

代码 ready 不等于能上架。Ownlight 首发真正耗时的非代码事项包括：

- Bundle ID、Share Extension ID、App Group、CloudKit container。
- signing、archive、export、upload。
- Privacy Policy / Support URL。
- metadata、keywords、description、Review Notes。
- screenshots、icon、category、age rating。
- pricing、availability、China mainland 相关提示。
- App Privacy Label。
- App Review 往返回复。
- manual release 和上线后传播验证。

以后应在开发末期前就建立 runbook，而不是临提交前临时补。

### 6. 截图要证明差异化

Ownlight 的截图不能只像“又一个日记 App”，所以最终选择了 Timeline、AI summary、Markdown detail、Calendar review、Topic areas、iCloud sync。

下一款 App 的截图顺序应回答：

- 第一张：这个 App 是什么。
- 第二张：它和同类产品有什么关键差异。
- 第三张：核心工作流怎么闭环。
- 后续：高级能力、信任点、同步/隐私/整理能力。

不要把所有截图都做成同一种列表页或设置页。

### 7. 真机 UAT 比模拟器更重要

Ownlight 的关键风险都必须靠真机验证：

- iCloud / CloudKit。
- Keychain。
- Share Extension。
- microphone / camera / photo permissions。
- App Store signing。
- iPhone + iPad 跨设备同步。
- 长期真实数据量下的性能。

下一款 App 至少准备：

- 一台日常主设备。
- 一台空设备或接近空白环境。
- 一套最终 App Store build smoke path。

模拟器适合视觉检查，不适合作为 iCloud、权限、Keychain、真实安装包的最终信心来源。

### 8. 首发优先 manual release

Ownlight 选择 manual release 是正确的：审核通过后仍能检查状态、合同、地区、metadata 和最终发布时机。

下一款 App 首发默认选择 manual release。只有在非常成熟、流程稳定、无需发布窗口控制时，再考虑自动发布。

### 9. 审核回复要自然、具体、可复核

3.1.1 回复通过的关键不是“争论”，而是把 reviewer 的误解拆开：

- 承认对方指出的问题可能来自 UI / wording 的误解。
- 逐条说明当前 App 实际没有什么。
- 说明相关功能的真实目的和边界。
- 请求指出具体违规实现点。
- 表示愿意调整文案或实现。

回复不要太像模板，也不要情绪化。清楚、诚恳、可验证，比长篇规则引用更有用。

## 下一款 App 发布前复用清单

### 产品边界

- [ ] 是否真的需要账号。
- [ ] 是否真的需要 IAP / subscription。
- [ ] 是否真的需要默认后端。
- [ ] 是否真的需要 analytics / crash upload。
- [ ] 是否真的需要 AI，AI 是开发者托管还是用户自带 provider。
- [ ] 核心功能在无网、未登录、未配置 AI 时是否仍可用。

### 技术声明

- [ ] Info.plist 权限文案只描述当前真实用途。
- [ ] Entitlements 只包含当前 release 必需项。
- [ ] Background modes 有真实功能路径和 Review Notes。
- [ ] App Group / iCloud / Push / Location / HealthKit 等 capability 有对应 UI 和测试路径。
- [ ] `get-task-allow=false`、正式 bundle id、正式 container、正式 App Group 已在导出包里复核。

### 隐私和数据

- [ ] 完成 Data Inventory。
- [ ] Privacy Policy 覆盖本地存储、同步、AI、导出、权限、删除。
- [ ] App Privacy Label 与最终 build 一致。
- [ ] API key / token / credentials 不进入 sync、export、logs。
- [ ] 不把未来计划写进隐私标签或 metadata。

### App Store Connect

- [ ] App name、subtitle、description、keywords 已冻结。
- [ ] Review Notes 解释无账号、AI/BYOK、iCloud、本地优先、权限用途。
- [ ] Screenshots 展示差异化，而不只是基础列表。
- [ ] Age rating、category、pricing、availability 已复核。
- [ ] Support URL 和 Privacy Policy URL 公开、稳定、无需登录。
- [ ] 首发使用 manual release。

### UAT

- [ ] 主设备跑完整主路径。
- [ ] 空设备跑首次安装和恢复/同步路径。
- [ ] 权限拒绝、无网、重启、前后台切换最小 smoke。
- [ ] 大数据量或真实数据量下的性能 smoke。
- [ ] App Store archive/export/upload 后用最终 build 复核，不只看 debug build。

## Ownlight 这次最值得保留的资产

- `docs/APP-STORE-READINESS.md`：上架准备总控。
- `docs/APP-STORE-SUBMISSION-RUNBOOK.md`：实际提交、重提、回复、发布记录。
- `docs/APP-PRIVACY-DATA-INVENTORY.md`：隐私标签判断依据。
- `docs/APP-STORE-UAT-RUNBOOK.md`：真实设备 UAT 路径。
- `npm run doctor:app-store`：本地可机械检查的 App Store preflight。

下一款 App 可以直接复用这套结构，再按产品形态裁剪。
