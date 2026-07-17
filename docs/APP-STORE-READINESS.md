# App Store 上架准备控制台

Last updated: 2026-07-02

本文档用于管理 Ownlight 面向 iOS App Store 的上架准备。它不是功能 PRD，也不是最终法律意见；它的作用是把 Apple 官方要求、当前不确定项、总任务表和完成状态放在一个地方，后续每完成一项就在这里打勾。

## 当前上架假设

- 第一版以 iPhone 单机、本地优先为默认体验。
- 第一阶段已纳入并完成 iCloud / CloudKit private sync UAT checkpoint；本地 iPhone SQLite 仍是默认 source of truth，提交前还需按最终 build 复核隐私文案、App Privacy Label、screenshots 和 Review Notes。
- AI 是可选能力，只走用户自带 provider/API key 或用户自托管/自选 endpoint。第一版不提供开发者托管默认 AI 服务。
- 第一版确认免费下载，不做账号系统、注册、登录、订阅、IAP、广告、第三方 analytics。
- 第一版不做 TestFlight 分发；最终候选 build 跑 owner real-device UAT 后直接提交 App Store，审核通过后手动发布。
- 当前 live availability 先移出中国大陆，面向 174 个海外国家或地区；中国大陆分发待 ICP/备案策略明确后再恢复。若要把商店页完整切成英文截图/副标题/默认 metadata，需要通过下一版本处理 live page 目前锁住的素材入口。
- App Store category 确认为 primary `Lifestyle / 生活`、secondary `Productivity / 效率`。
- 公开 URL 先复用现有 Cloudflare 域名，使用产品专属 path 或 subdomain；不为 v1 单独购买新域名，前提是页面公开、稳定、无需登录、HTTPS 可访问。
- 所有最终 App Store Connect 回答都必须以提交前的实际 build 为准，不能按未来计划提前填写。

## 当前本地 preflight 结论

2026-06-08 已新增 `npm run doctor:app-store`，用于提交/归档前机械检查当前 checkout 的上架基础项：UAT gates、Info.plist 权限文案、export compliance plist key、PrivacyInfo required reason API、iCloud/App Group entitlements、public fallback URL、Privacy/Support URL、第三方 analytics/crash/ad/tracking SDK 漂移、明显 required-reason API 漂移。当前运行结果为 19 checks、0 failures、0 warnings。

当前活跃 Backlog 不阻塞 v0.1：`.planning/BACKLOG.md` 中 `B001` local transcription adapter 和 `B002` push-assisted near-realtime sync 都是 v0.1 后增强候选。旧 `.planning/_legacy-gsd/` 已从活跃 checkout 移除，清理边界见 `.planning/LEGACY-GSD-ARCHIVE.md`。

## 状态标记

- `[ ]` 未开始
- `[x]` 已完成
- `Decision needed` 需要先确认产品/分发方案
- `Research done` 官方要求已查，尚未执行
- `Blocked` 被外部条件阻塞

## 官方要求核对结果

### 1. Privacy Policy URL

官方要求：

- iOS App 必须在 App Store Connect 提供 Privacy Policy URL。
- App Review Guidelines 还要求所有 App 在 App Store Connect metadata 和 App 内易访问位置都包含隐私政策链接。
- App Store Connect 允许为不同语言/地区本地化隐私政策 URL。
- User Privacy Choices URL 是可选项；如果提供，应是公开可访问页面，用于说明用户如何管理隐私选择、访问数据或请求删除。

当前结论：

- Apple 官方文档没有要求 Privacy Policy URL 必须使用独立注册域名，也没有要求必须先向 Apple 注册该 URL。
- 但实际提交时，URL 应该是公开、无需登录、稳定、可被审核员访问的完整 URL。建议用 `https://`，避免依赖临时预览地址、需要登录的 Notion/Google Doc、内网地址或会过期的链接。
- 如果只上架 iOS，不需要 tvOS 的隐私政策正文。

Ownlight 待办：

- 准备一个公开 Privacy Policy 页面。
- Settings 内增加或确认已有 `Privacy Policy` / `Privacy & AI` 可访问入口。
- 确认是否需要单独的 User Privacy Choices URL。第一版无账号时可以先不提供，但 support/privacy 页面里仍要说明本地数据删除、导出文件删除、AI provider 关闭方式。

官方来源：

- https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy
- https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy
- https://developer.apple.com/app-store/review/guidelines/

### 2. Privacy Policy 内容

官方要求隐私政策清楚说明：

- App/service 收集什么数据、如何收集、如何使用。
- 与哪些第三方共享用户数据，并说明第三方提供同等或相当的数据保护。
- 数据保留/删除政策，以及用户如何撤回同意或请求删除数据。
- 若向第三方 AI 分享个人数据，必须清楚披露数据共享位置，并在共享前取得明确许可。

术语说明：

- `BYOK` 是 `Bring Your Own Key`，意思是用户自己提供 API key。
- 在 Ownlight v1 语境中，更准确的产品表达是“用户自托管/自选 AI endpoint”。API key、Base URL、model 等配置由用户自己提供，开发者不提供默认 AI 中转或托管服务。

当前结论：

- 本地只在 iPhone 处理且不传给开发者或第三方的内容，一般不构成 App Privacy Label 里的“收集”；但隐私政策仍应解释本地保存内容和导出包风险。
- 只要 AI 功能会把 transcript、moment text、comments、summary input 或其他用户内容发到外部 provider，就必须在产品内和隐私政策中明确说明。
- v1 已确认不提供开发者托管默认 AI 服务；用户需要自己选择 provider/endpoint 并提供凭据，AI 关闭或未配置时核心记录功能仍可用。
- 因为 Ownlight 是私密记录产品，隐私政策必须比普通工具 App 更具体，不能只写模板化 “we value your privacy”。

Ownlight 待办：

- 写出一版 Privacy Policy，覆盖本地存储、AI、导出、可选私有 endpoint、权限、日志、支持邮件、数据删除方式。
- 明确 AI 默认状态、启用前提示、provider/API key 存储位置，以及哪些内容会发送给 provider。
- 提交前根据最终 build 复核 App Privacy Label。

官方来源：

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/app-store/app-privacy-details/

### 3. App Privacy Label / 数据收集问卷

官方要求：

- App Store Connect 需要说明 App 的数据处理方式。
- 如果 App 或第三方 partner 收集数据，需要选择所有涉及的数据类型、用途、是否 linked to user、是否 tracking。
- Apple 对 “collect” 的定义是：数据从设备传出，并允许开发者或第三方 partner 在服务实时请求所需时间之外访问。
- 即使数据只用于 App 功能，也需要披露，除非满足 Apple 的可选披露条件。
- 如果不同用户、地区、免费/付费状态或 opt-in 状态下收集不同数据，回答应覆盖所有实际会发生的数据收集。

当前结论：

- 不应在没有完成最终数据流审计前选择 “No, we do not collect data from this app”。
- 如果第一版没有开发者服务器、无 analytics、无 crash SDK、无广告追踪，并且 AI 完全由用户自选 endpoint/provider 处理，App Privacy Label 仍需要谨慎判断外部 AI provider 是否属于第三方 partner 或数据共享接收方。保守策略是：隐私政策明确披露，App Privacy 问卷单独做一次逐项映射后再决定。
- 私密内容相关数据类型可能涉及 `User Content` 下的 photos/videos、audio data、other user content，也可能涉及 search history、diagnostics、product interaction，取决于最终是否传出设备。

Ownlight 待办：

- 已建立 [App Privacy Data Inventory](APP-PRIVACY-DATA-INVENTORY.md)：每类数据在哪里产生、是否离开设备、谁能访问、用途、保留/删除方式。
- 按最终 build 填一版 App Privacy answers draft。当前 inventory 给出一个“无开发者收集数据”的主口径和一个“AI provider 保守披露”的备选口径。
- 避免引入第三方 analytics / crash SDK，除非愿意承担隐私标签和文案成本。

官方来源：

- https://developer.apple.com/app-store/app-privacy-details/
- https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy

### 4. 账号系统与账号删除

官方要求：

- 如果 App 没有显著 account-based features，应允许用户不登录使用。
- 如果 App 支持账号创建，必须在 App 内允许用户发起账号删除。
- 账号删除入口应容易找到，通常在 account settings；只提供停用/禁用账号不够。
- 非高度监管行业不应要求用户打电话、发邮件或走客服流程才能删除账号。
- 自动创建的 guest account 也需要提供删除选项。
- 如果使用第三方或社交登录作为主账号登录方式，需要满足 Apple Login Services 规则；只用自有账号系统时不强制提供另一种登录方式。

当前结论：

- 第一版已确认不做账号系统。这样更符合本地优先产品定位，也减少账号删除、服务端隐私、安全、客服和审核负担。
- 如果未来做云同步、订阅、跨设备账号，再单独设计 Sign in with Apple / 账号删除 / 服务端数据删除 / 订阅状态处理。

Ownlight 待办：

- v1 App Store 版本无账号、无注册、无登录。
- App Review Notes 写清楚：no account required；所有核心功能可直接本地使用。
- 如果后续改为有账号，必须先完成账号删除设计再提交。

官方来源：

- https://developer.apple.com/app-store/review/guidelines/
- https://developer.apple.com/support/offering-account-deletion-in-your-app/

### 5. App Store metadata 与公开 URL

官方要求：

- App name：2 到 30 个字符。
- Subtitle：不超过 30 个字符。
- Description：必填，不超过 4000 字符，纯文本，不支持 HTML。
- Keywords：必填，最多 100 bytes，不应重复 app name/company name，也不能使用其他 App 或公司名称。
- Screenshots：必填，每个 localization 上传 1 到 10 张，格式 `.jpeg`、`.jpg`、`.png`。
- Support URL：必填；必须是完整 URL，包括协议；页面应提供真实联系方式，便于用户反馈问题、一般意见或功能建议。
- Marketing URL：可选；如果提供，也要是完整 URL。
- Copyright：必填。
- App Review Notes：可提供最多 4000 bytes 的审核说明；如果 App 需要登录，需要提供不会过期的 demo account。

当前结论：

- Privacy Policy URL、Support URL、Marketing URL 可以共用同一个网站的不同页面，但 Support URL 必须能找到真实联系方式。
- Apple 没要求这些 URL 必须是某种特定域名；但不要用内网、本机、临时地址或需要登录才能访问的页面。
- 个人开发者如果面向 EU 分发，还要处理 DSA trader status；如果选择在中国大陆分发，需单独核查是否触发 ICP 或其他材料要求。
- iOS 本地 build 的公开 URL 来自 `.env.local`，由 `scripts/write-ios-local-config.sh` 写入 git-ignored `ios/Config/Local.xcconfig`。不要在 `.xcconfig` 中手写裸 `https://`，因为 `//` 会被 Xcode 当作注释；生成脚本会自动写成 `https:/$()/...`，最终 Info.plist 会展开回正常 `https://...`。

Ownlight 待办：

- 准备官网/支持页/隐私政策页的最小公开版本。
- 准备 App Store name、subtitle、description、keywords、screenshots、review notes。
- 确认 distribution territories，尤其是是否包含 EU、中国大陆、韩国、越南。

官方来源：

- https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications

### 5A. v1 商业化边界与未来付费候选

官方要求：

- 如果 App 内要解锁功能、内容、订阅、数字服务或完整版本，通常必须使用 Apple In-App Purchase。
- 如果 App 包含 IAP，metadata、截图和 preview 必须清楚说明哪些功能需要额外购买。
- 如果提供订阅，必须在订阅前清楚说明用户会得到什么、订阅周期和持续价值。

当前结论：

- v1 已确认免费下载、无 IAP、无订阅、无广告、无开发者托管默认 AI 服务。
- 当前没有足够明确的付费点；第一版应优先验证是否有人长期使用、是否愿意配置自托管 AI、是否会积累足够多的个人记录。
- v1 可以做 provider presets 降低用户自配 AI 的门槛，但不要在当前版本销售托管 AI API 或额度。

未来付费候选，不进入 v1 必做范围：

1. **AI Memory / 日记知识库**：把长期 moments、评论、AI summary、语音转写、topic 等变成可问答/可语义搜索的个人记忆库，例如 `Ask Your Timeline`、项目/人生时间线、长期主题追踪。这是当前最有潜力的 Pro 方向。
2. **Managed AI / 一键 AI 服务**：用户不用配置 API key，直接使用开发者托管 AI。适合未来有用户后评估，但会引入账号、IAP、额度、限流、防滥用、隐私和后端稳定性成本。
3. **高级回顾与分析**：月度/年度深度报告、主题趋势、生活领域分布、反复出现的问题、值得重看的记录、长语音/视频多层 summary。
4. **高级搜索与整理**：语义搜索、跨媒体搜索、批量 topic cleanup、自动聚类、collections、按人物/地点/项目归档。
5. **同步、备份、迁移**：iCloud/CloudKit sync、加密云备份、新手机迁移、多设备同步、Web/Desktop companion、备份版本历史。价值强，但复杂度和隐私责任高。
6. **导出和作品化**：年度 PDF、Markdown/HTML archive、打印成册、按月份/主题生成私人小册子、项目回顾包。

不建议作为付费点：

- 基础记录文字、照片、语音、视频。
- 基础导出。
- 基础 tags/filter。
- 限制 moment 数量。
- 强制 AI 订阅。
- 单纯外观主题。

官方来源：

- https://developer.apple.com/app-store/review/guidelines/

### 5B. 第一阶段 CloudKit / iCloud 工作范围

官方要求与事实：

- CloudKit 用 iCloud containers 在 app 与 iCloud 之间移动数据，用于让用户在多台设备访问自己的 app data。
- 用户私有数据应使用 CloudKit private database；保存单个用户的私有数据需要用户有有效 iCloud account。
- CloudKit 不是本地数据模型的替代品；Apple 文档明确说明它只提供有限离线缓存，因此 Ownlight 仍需要本机 SQLite 作为默认 source of truth。
- 工程上需要 Apple Developer Program、iCloud/CloudKit capability、container identifier、provisioning profile、entitlements、Development/Production 环境、CloudKit schema，以及真实设备测试。
- App Store 文案、Privacy Policy、App Privacy Label 和 Settings copy 必须与最终提交 build 的实际 CloudKit 行为一致。

当前实现状态：

- 2026-06-08：CloudKit private sync 第一阶段已从“实现中”转为“UAT checkpoint closed”。真实 iPhone/iPad UAT 已覆盖 ordinary text/audio/media sync、summary artifacts、comments、drafts、Settings preferences、check-ins、delete/tombstone 和 edit-media add/remove；container spot-check 覆盖 SQLite health、CloudKit pending queue、provider secret exclusion 和两端实体状态。
- 当前主线已经包含：本地 CloudKit metadata tables、record state、pending queue、payload mapper/resolver、CKRecord encoder/decoder、transport、pull/apply、media asset upload/download、initial local-library upload、non-empty second-device guard、manual multi-batch drain、missing-parent recovery、optional derived orphan skip、delete/tombstone/edit-media enqueue、user-readable failure copy，以及一次性 `cloudkit_full_reconcile_v1`。
- 普通用户 Settings 只保留 `iCloud Sync`、低频 `Sync Now`、账号状态和必要 guidance；smoke test、default-zone probe、container ID 和 raw diagnostics 不进入普通设置界面。
- 真实 quota/full-storage 没有人为耗尽演练；提交 App Store 前仍按最终 archive 复核 failure copy、privacy copy、App Privacy Label、screenshots 和 Review Notes。

当前结论：

- CloudKit private sync 是第一阶段已完成 UAT 的 opt-in 增强能力，但不改变“无账号、免费下载、本机可用”的 v1 基线。
- 用户可见控制只保留一个 `iCloud Sync` 总开关；不要暴露“只同步结构化数据 / 同步媒体 / 按媒体类型同步 / 按大小同步”等工程选项。
- 用户开启 CloudKit Sync 后，产品承诺应是完整 moment 同步，包括文字、评论、tags、check-ins、AI metadata、照片、音频、视频和文档附件。结构化数据先到、媒体稍后补齐只能是实现过程中的临时状态，不是长期用户模式。
- 不使用自建账号系统；用户身份由 Apple iCloud account / CloudKit private database 承载。
- 不把 Mac server 作为普通用户同步前提；legacy Mac server 仍可作为高级/历史兼容路径。
- CloudKit 已达到 M017 第一阶段真实设备 UAT gate，可以作为 App Store v1 的可选同步能力描述；文案仍要保守：local-first、opt-in、同 Apple Account、private iCloud database、无 Ownlight 账号、无开发者服务器同步前提。
- 已实现的 local mapper、local payload resolver、runner skeleton、CKRecord encoder/decoder、default transport boundary、incoming apply policy、zone changes download transport、sync cursor DAO、pull runner dispatch、moment/comment local DB apply、tag metadata local DB apply、media metadata local DB apply、check-in metadata local DB apply、AI artifact local DB apply、Weekly Review mapper/resolver/local apply、Preference mapper/resolver/local apply、Draft metadata mapper/resolver/local apply、media asset upload/download、guarded Settings smoke、ordinary Moment/media/comment/summary/tag/check-in/draft/preference enqueue、ordinary auto sync trigger、first-device initial local-library queue preparation、non-empty second-device initial-sync guard、manual multi-batch drain、missing-parent recovery、optional derived orphan skip、delete/tombstone/edit-media enqueue、user-readable failure copy 和一次性 `cloudkit_full_reconcile_v1` 均已进入当前主线。同步边界继续排除 Mac/server runtime、raw transcript text、provider/model/token/error diagnostics、queue/cache state、server URL、device identity、本机 gateway/provider 配置、新草稿媒体文件字节、credentials/API keys 和 sample data。

已冻结的产品/工程边界：

1. **完整同步范围**：第一版 CloudKit 覆盖 posts、comments、tags、check-ins、AI summaries、weekly reviews、media records、media assets 和 document attachments；本地-only metadata 继续按同步排除清单处理。
2. **媒体内部策略**：照片、音频、视频和 PDF/文档附件都应最终同步；工程上需要定义大文件上传/下载队列、失败重试、iCloud quota、后台传输、低电量/弱网下的内部调度，但这些不作为普通用户选项。
3. **冲突策略**：普通字段按最新 `updatedAt` 自动胜出；delete wins；comments 按独立 id 合并；tags/aliases/merge 按独立对象/操作状态幂等应用；media 按 media id 同步，不做内容级 merge；AI metadata 按最新生成/状态同步。
4. **本地优先策略**：无网、未登录 iCloud、iCloud Drive 关闭、CloudKit quota 满、CloudKit temporarily unavailable 时，用户必须仍可创建/编辑；Settings 只显示必要状态，不把同步细节塞进主 Timeline。
5. **迁移策略**：首次开启 CloudKit Sync 时，当前 iPhone 作为初始资料库，完整上传本机 active archive。这个动作需要清楚说明将把 Moments 同步到用户 iCloud，但不要求用户理解 merge/pull。
6. **多设备初始化**：第二台空库设备开启 CloudKit Sync 后自动下载 iCloud 中的完整资料库；第二台非空设备第一版不自动合并，提示先导出/清空或等待后续 merge 功能，避免误合并造成重复或覆盖。
7. **隐私与导出边界**：CloudKit 只同步用户可见资料库内容和允许同步的偏好/草稿 metadata；AI provider keys、raw transcript text、diagnostics、runtime queue/cache 和本机 endpoint/provider 配置绝不进入 CloudKit。
8. **App Store 文案边界**：`iCloud Sync` 可以作为可选同步能力进入 App Store v1 文案，但最终 screenshots、description、onboarding 和 App Review Notes 必须按提交 archive 复核，不夸大 realtime、merge、quota 或开发者托管能力。
9. **Owner UAT gate**：CloudKit 不依赖外部 TestFlight 用户数量；当前 owner real-device UAT 已覆盖主要 P0 同步路径，最终提交前只补齐 archive/privacy report、quota/full-storage copy、无网/权限等 release-grade smoke。

Owner real-device UAT gates:

| Gate | 验证什么 | 通过标准 |
| --- | --- | --- |
| CK-P0-01 | 首设备完整上传 | 现有 iPhone 开启 `iCloud Sync` 后，文字、照片、音频、视频、PDF/文档、评论、tags、check-ins、AI metadata 都进入 CloudKit 队列并最终完成。 |
| CK-P0-02 | 第二台空设备自动恢复 | 第二台空库设备用同 Apple ID 开启同步后，自动出现完整 timeline，媒体最终可打开/播放。 |
| CK-P0-03 | 离线创建后补同步 | 无网创建文字/图片/语音/视频/文档，恢复网络后另一台设备出现完整内容。 |
| CK-P0-04 | 修改同步 | 一台设备修改正文、评论、tags、favorite、check-in 等，另一台设备最终显示最新内容。 |
| CK-P0-05 | 删除同步 | 一台设备删除 moment/comment/tag 后，另一台设备也删除，不复活。 |
| CK-P0-06 | 媒体完整性 | 图片、音频、视频、PDF/文档跨设备可打开；不能长期停留在只有文字没有媒体的状态。 |
| CK-P0-07 | 非空第二设备保护 | 第二台已有本地数据时开启 `iCloud Sync`，不会自动合并或覆盖，并给出清晰提示。 |
| CK-P0-08 | 未登录/不可用 iCloud | 未登录 iCloud、iCloud 关闭、CloudKit 暂不可用时，本机记录仍可用，Settings 只显示低干扰状态。 |
| CK-P0-09 | quota / 大文件 / 网络失败 | 大文件、quota 或网络失败不影响本机记录；不会误标同步完成；可自动或低频手动重试。 |
| CK-P0-10 | 重装/空库恢复 | 删除 App 或清空本地库后，在空库设备开启同步可从 CloudKit 恢复完整资料库。 |
| CK-P0-11 | Secret 不同步 | AI API key、provider secrets、本机诊断状态、private transcript text 不进入 CloudKit；第二台设备需要重新配置 secrets。 |
| CK-P0-12 | 文案一致性 | 最终 build、Privacy Policy、App Privacy Label、screenshots、onboarding 和 App Review Notes 都只描述已通过 UAT 的 CloudKit 行为。 |

UAT 记录格式：

- Date
- Build number
- Device A / Device B
- Apple ID / iCloud status
- Dataset size
- Gate id
- Result
- Issues found
- Gate status

App Store direct-submission 口径：

- 第一阶段不做 TestFlight；没有外部 tester 不阻塞 App Store v1。
- 最终候选 build 用 owner daily iPhone + iPad 跑 release-grade UAT。
- App Store Connect 选择 manual release after approval，避免审核通过后自动上线。
- 若审核或首批真实用户反馈暴露 onboarding/privacy/sync 风险，再为后续版本引入 TestFlight。

官方来源：

- https://developer.apple.com/icloud/cloudkit/
- https://developer.apple.com/documentation/CloudKit
- https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app

### 5C. First Launch Onboarding / Welcome Sample

当前结论：

- v1 不做传统三步功能导览，也不做复杂设置向导。首次体验只承担两个目标：建立“私人时间线”的产品心智，以及让用户相信核心记录可以无账号、本机优先地开始使用。
- 首次启动保留一个极短 welcome page，只在当前 app installation 的第一次进入时出现。它只讲理念和安全感，文案气质偏“只给自己的私人时间线”，并用一个 `Start` 主按钮进入 Timeline。
- 关闭 welcome page 后不再自动出现；Settings 不提供 replay onboarding / restore welcome 的入口。删除 App 后重新安装视为新的 installation，可以重新出现。
- 空资料库新用户进入 Timeline 后自动创建一条今天顶部的 welcome sample moment。它是一条真实本地样例数据，用来展示产品自己的内容形态，而不是额外教程页或营销页。
- Welcome sample moment 应包含：私人记录式欢迎正文、示例音频块、明确标注为 sample generated summary 的 AI summary、topic tags、一条评论，以及一次性手势提示。
- Welcome sample moment 正文承担主要说明：可以像只给自己看的朋友圈一样记录，tags 可以帮助整理，AI summary 是可选能力且可在 Settings 中配置/授权，常用操作可通过滑动、长按等完成。正文应短、温和、可扫读，不写成帮助文档。
- UI 只做轻标记：低调但明确的 `Welcome` / `Sample` 标记、首次显示一次的手势提示、样例专用删除确认。不要做大系统公告卡、长期浮层或多页教程。
- 手势提示绑定 welcome sample moment 首次显示，只出现一次。它用于提示常用 Timeline 操作，例如滑动收藏/删除、长按置顶；看过后即消失，正文里仍可保留简短提示。
- 示例音频块不强调真实播放；它主要用于建立“AI summary 来自语音/媒体内容，而不是正文说明”的视觉关系。对应 AI summary 可以展示真实 summary UI 的标题、一句话总结、Markdown-like block、分点、折叠和图标/提示能力，但必须明确是 sample generated summary。
- Welcome sample moment 是本机教学样例，不是用户私人资料：不同步、不导出、不进入 Weekly Review / AI review 输入、不进入未来 CloudKit 资料库，不应污染用户真实 archive。
- Welcome sample moment 删除后不自动恢复；同一次 installation 内也不重新创建。删除体验复用普通删除入口，但使用样例专用确认文案，避免用户误以为在删除真实私人记录。
- Welcome page 跟随当前 App UI 语言；welcome sample moment 创建时按当前 App 语言写入，之后像普通 moment 一样不随 UI 语言切换而改变正文。

实现边界：

- 需要有内部 sample 标记，确保 sample moment、sample comment、sample tags、sample AI summary 和示例音频块不会进入 sync/export/review/CloudKit 等真实数据流。
- 不要把 `Base URL`、`API key`、model 等 AI 配置细节放进首次 welcome page。AI 的具体配置仍属于 Settings > AI & Analysis；AI 外发仍必须走已有 explicit consent gate。
- 不要把 Check-ins 放进首次 onboarding 主线。Check-ins 是后续使用中的辅助记录入口，不是第一次理解 Ownlight 所必需的能力。

UAT 口径：

- 使用 `npm run ios:device:uat` 安装隔离的 `Ownlight UAT` 验证新用户状态，不覆盖日常 `Ownlight` 数据。
- 验证空资料库首次进入：welcome page 只出现一次；点击 `Start` 后进入 Timeline；今天顶部出现 welcome sample moment；手势提示只显示一次。
- 验证删除样例：右滑/详情删除应显示样例专用确认；确认后 sample 不再出现，重启 App 后也不恢复。
- 验证数据边界：sample 不进入 sync/outbox、export archive、Weekly Review / AI review 输入，也不应在未来 CloudKit sync 中出现。

### 6. Privacy manifest / Required Reason APIs / 第三方 SDK

官方要求：

- App 或 SDK 可以包含 `PrivacyInfo.xcprivacy`，用来声明收集的数据和 required reason APIs。
- 如果上传包中包含 invalid privacy manifest，App Store Connect 会拒绝。
- 从 2024-05-01 起，使用 required reason API 的 App 需要在 privacy manifest 里声明 approved reason。
- 从 2025-02-12 起，提交包含 Apple 列表内常用第三方 SDK 的新 App 或更新时，必须包含这些 SDK 的有效 privacy manifest；二进制依赖还涉及签名要求。

当前结论：

- 项目已有 iOS `PrivacyInfo.xcprivacy`，但提交前必须按最终 build 重新审。
- 目前应尽量避免新增第三方 SDK，尤其是 analytics、login、crash、image/cache、networking SDK；每加一个都增加 privacy manifest 和 App Privacy Label 成本。

Ownlight 待办：

- 审计 `PrivacyInfo.xcprivacy` 是否覆盖当前实际 API 使用。
- 审计 iOS target 是否包含 Apple 列表内第三方 SDK。
- archive build 后检查 privacy report / App Store Connect 上传反馈。

官方来源：

- https://developer.apple.com/support/third-party-SDK-requirements/
- https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk
- https://developer.apple.com/documentation/BundleResources/describing-use-of-required-reason-api

### 7. Export compliance / encryption

官方要求：

- 如果 App 使用、访问、包含或实现加密，并计划上传、测试、分发，需要在 App Store Connect 确认 export compliance。
- 如果只使用 Apple 操作系统提供的加密能力，通常不需要在 App Store Connect 上传文稿。
- 如果使用 Apple OS 之外的行业标准算法或专有/非标准算法，可能需要提交额外文稿，尤其涉及法国分发时的声明。

当前结论：

- Ownlight 至少会使用 HTTPS/TLS、Keychain、系统存储等 Apple OS 层能力；提交前仍要按 App Store Connect 问答确认。
- 不应在第一版引入自研加密、第三方加密库或 E2EE 承诺，除非愿意同步做合规和恢复设计。

Ownlight 待办：

- 审计当前 iOS build 是否只使用 Apple OS 提供的加密能力。
- 确认 `Info.plist` export compliance key 是否需要设置。
- App Store upload / 提交前完成 export compliance answers。

官方来源：

- https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/
- https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/

### 8. Direct App Store Submission

官方要求：

- 提交 App Review 前，需要在 App Store Connect 提供 required metadata 并选择要提交的 build。
- App Preview 是可选项；screenshots 是必填项。
- 审核通过后可以选择自动发布、手动发布或指定日期发布。
- TestFlight 是可选测试分发通道，不是 App Store 上架的强制前置步骤。

当前结论：

- v1 不做 TestFlight，直接走 App Store submission。
- 由于当前只有 owner 能持续真实使用和验证，外部 TestFlight 不会显著提高首发质量，反而会增加 beta metadata、反馈流和隐私说明成本。
- 风险控制改为：最终候选 build 的 owner iPhone/iPad UAT、manual release after approval、首发中国大陆小范围可用性、无 IAP/账号/广告/analytics 的低复杂度提交。

Ownlight 待办：

- 准备 archive upload / App Store direct-submission runbook。
- 提交前跑最终候选 build UAT。
- App Store Connect 选择手动发布。
- 把 TestFlight 作为后续版本的可选工具，而不是 v1 gate。

官方来源：

- https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app
- https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/overview-of-publishing-your-app-on-the-app-store
- https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots

### 9. Accessibility Nutrition Labels

官方要求：

- Accessibility Nutrition Labels 初期自愿提供，但 Apple 鼓励填写，且未来会逐步要求提交新 App/更新时分享 accessibility support details。
- 在声明支持某项 accessibility feature 前，需要确认用户能用该 feature 完成 App 的 common tasks。
- Common tasks 包括 App 主功能、first launch、login、purchase、settings 等。

当前结论：

- 第一版不一定要主动填写所有标签，但应该至少做一轮 accessibility audit，避免新手引导、Composer、Timeline、Settings、导出流程在 VoiceOver / Larger Text 下不可用。
- 如果没有完整验证，不要在 App Store Connect 里过度声明支持。

Ownlight 待办：

- 定义 common tasks。
- 做 VoiceOver、Larger Text、Dark Interface、Sufficient Contrast、Differentiate Without Color Alone、Reduced Motion 的最小审计。
- 决定是否提供 accessibility URL。

官方来源：

- https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/

### 10. 地区、类别与其他合规开关

官方要求/提示：

- Age Rating 是必填。
- Category 需要选择最符合 App 的类别；iOS App 可设置 primary category 和 secondary category，primary category 对 App Store 浏览、筛选和发现更重要。
- Apple 对 `效率 / Productivity` 的描述包含帮助用户更有条理、更高效地处理流程或任务，示例包括笔记、日程、音频记录、数据查看等。
- Apple 对 `生活 / Lifestyle` 的描述更偏普遍兴趣、兴趣爱好、家居、育儿、时尚等生活主题。
- Apple 对 `社交 / Social Networking` 的描述强调发展人际关系网络或社区；Ownlight 明确不做公开社交、好友关系和社区。
- Apple 对 `健康健美 / Health & Fitness` 和 `医疗 / Medical` 有更强健康、医疗或跟踪含义，不适合作为 Ownlight 的默认定位。
- App Store Connect 的 `主要语言` 是 metadata 的默认显示语言：如果某个国家或地区没有本地化 metadata，产品页和安装信息会使用主要语言；这不等同于 App 内“跟随系统语言”的 runtime 设置。
- 如果面向 EU，App Store Connect 会询问 Digital Services Act trader status；若是 trader，可能需要在 App Store 产品页展示地址和联系方式。
- 中国大陆分发可能触发 ICP 或其他内容/出版/新闻/宗教/游戏类材料要求，取决于 App 和内容类型。
- Apple 明确说明，在中国大陆供应时，特定类型 App 需要额外信息和文件；部分 App 可能需要有效 ICP 备案号，游戏、图书/报刊、宗教、新闻等类别有额外许可证要求。
- 如果选择 Health & Fitness 或 Medical 类别，或 age rating 中包含频繁医疗/治疗信息，可能触发 regulated medical device declaration。

当前结论：

- Ownlight 不应优先选择 Health & Fitness / Medical 类别，避免把个人记录、check-ins 或情绪分析误导成医疗产品。
- Ownlight 也不应选择 Social Networking；它不是社交网络，不提供好友关系、公开内容、互动通知或社区。
- 当前 live availability 已先移出中国大陆。中国大陆恢复前需要单独核查 ICP / 中国大陆 availability 要求；如果触发材料要求，先按真实 App 类型判断是否需要材料，不把它预设成新闻、出版、宗教、游戏或医疗类 App。
- 确认 category：primary 选 `Lifestyle / 生活`，secondary 选 `Productivity / 效率`。理由是 `Ownlight` 的名字和产品第一认知更像私人生活记录/私人朋友圈；`Productivity` 仍作为次级类别承接整理、检索、记录和回顾能力。
- live v1 的 primary language 仍是 `Simplified Chinese`，但当前海外可见性更适合 English-first 商店页。App 内继续保留 `System` / `English` / `Simplified Chinese`，不为 v1 扩展更多语言；完全英文截图/副标题/primary-language 口径在下一版本复核。

Ownlight 已完成 / 待复核：

- App Store Connect 已设置 primary `Lifestyle`、secondary `Productivity`。
- Age Rating 已保存为 global `4+`。
- App Store Connect Availability 已在 2026-07-02 从 China mainland-only 改为 174 countries or regions 可用，并取消 China mainland。页面随后显示 China mainland `Not Available`，其他地区 `Processing to Available`。
- 之前设置 China mainland availability 时未出现阻塞式 ICP 字段，但 App Store 搜索可见性/中国大陆分发仍受 ICP 策略影响；恢复 China mainland 前需要重新核查。
- 因当前已进入海外地区，DSA trader status、EU/韩国/越南等地区问答需要在 App Store Connect 中保持真实填写；如后续变更商业化或地区范围，需要重新复核。
- 已确认不做医疗声明、不做健康诊断承诺。

官方来源：

- https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- https://developer.apple.com/cn/app-store/categories/

## 总任务表

| Done | Area | Task | Status | Notes |
| --- | --- | --- | --- | --- |
| [x] | 官方要求 | 查 App Store privacy / URL / account / metadata / TestFlight / accessibility / export compliance 官方要求 | Research done | 2026-06-01 已完成第一轮官方核对 |
| [x] | 产品边界 | 确认第一版无账号、无注册、无登录 | Done | 2026-06-01 确认；App Review Notes 需写明 no account required |
| [x] | 产品边界 | 确认第一阶段 CloudKit / iCloud 具体范围 | Done | 2026-06-01 确认：单总开关、完整 moment 同步，metadata-only 仅作临时中间态 |
| [x] | 产品边界 | 确认第一版免费、无 IAP、无订阅、无广告 | Done | 2026-06-01 确认；未来付费候选记录在 5A |
| [x] | 产品边界 | 确认 AI 是可选 BYOK / user endpoint，不提供开发者托管 AI 服务 | Done | 2026-06-01 确认；产品文案优先写“用户自托管/自选 AI endpoint” |
| [x] | 地区策略 | 确认首发国家/地区 | Updated | 2026-06-21 App Store Connect Availability 曾设置为 China mainland only；2026-07-02 因 ICP/中国大陆可见性策略未定，已改为 174 countries or regions 可用并取消 China mainland。确认弹窗说明会从 China mainland 下架并在 174 个国家或地区可用，变更最多 24 小时生效；页面随后显示 China mainland `Not Available`、其他地区 `Processing to Available` |
| [x] | Store metadata | 确认 App Store 主要语言 | Needs next-version review | 2026-06-01 确认：首发 metadata 使用 Simplified Chinese primary、English localization。2026-07-02 切换海外 availability 后，live `1.0 Ready for Distribution` 的 App Information 仍显示 primary language `Chinese (Simplified)`，未暴露可编辑控件；如要完全改成英文主口径，需在下一版本重新复核 App Store Connect 可改项 |
| [x] | URL | 确认公开 URL host 策略 | Done | 2026-06-01 确认：v1 可复用现有 Cloudflare 域名，用产品专属 path/subdomain；不需要单独注册新域名 |
| [x] | 类别策略 | 选择 App Store primary/secondary category | Done | 2026-06-02 确认：primary `Lifestyle`、secondary `Productivity` |
| [x] | iCloud | 注册 Apple Developer Program 并确认 Team ID / bundle id / iCloud container 命名 | Done | 2026-06-03 Apple Developer portal 已配置 owner 专用正式 identity：主 App ID 绑定 App Group 与 iCloud container；Share Extension 只绑定 App Group、不启用 iCloud。2026-06-04 重新保存正式 App ID 绑定并重签安装后，签名产物确认只包含正式 container/group，CloudKit guarded smoke 已在真实 iPhone 成功上传一条测试 Moment；具体 signing identifiers 不进入公开源码快照 |
| [x] | iCloud | 实现 CloudKit account-status scaffold | Done | 2026-06-03 首个 checkpoint 已完成：Settings > iCloud 只检查 iCloud/CloudKit 可用性，并明确当前 build 不上传 Moments、不创建 CloudKit records；focused CloudKit tests 与 `npm run verify:ios:generic` 已通过 |
| [x] | iCloud | 设计 CloudKit record schema 与 local SQLite 映射 | Done | 2026-06-07 `.planning/phases/017-app-store-readiness-and-product-maturity/017-03-CLOUDKIT-SYNC-SPEC.md` 已冻结同步边界；本地 CloudKit metadata tables / record state / pending queue、payload mapper/resolver、CKRecord encoder/decoder、transport、pull/apply、media asset transfer、initial upload、derived-content backfill/realtime enqueue、non-empty second-device guard、delete/tombstone/edit-media enqueue、draft/preference sync、user-readable failure copy 和一次性 full reconciliation 已完成。M017 cross-device UAT 已关闭；真实 quota/full-storage 未人为耗尽，提交前按最终 build 复核 failure copy、隐私文案和 App Privacy label。 |
| [x] | iCloud | 跑 guarded CloudKit real smoke | Done | 2026-06-04 重新保存正式 App ID 的 App Group / iCloud container 绑定并重签安装后，真实 iPhone 上 `Run CloudKit Smoke Test` 成功上传一条显式测试 Moment 到 private iCloud database；同一正式配置 build 安装到真实 iPad 后，iPad 侧 CloudKit smoke 也已成功。此前 `CKErrorDomain 15` / `serverRejectedRequest` / `CKHTTPStatus 500` 先作为已解除的 portal/profile 状态问题处理。后续 M017 已完成跨设备 pull、完整资料库同步、删除传播、媒体 asset、派生内容和首设备 upload UAT；smoke/default-zone 测试入口不再作为普通用户设置项展示。 |
| [x] | iCloud | 设计 CloudKit sync conflict / migration / retry 策略 | Done | 2026-06-03 已冻结：首设备完整上传、空库设备自动下载、非空设备暂不自动合并、delete wins、普通字段 `updatedAt` wins、draft/preferences 最新胜出、Settings 保留低频 `Sync Now` |
| [x] | iCloud | 定义 CloudKit release UAT gates | Done | 2026-06-01 确认：owner real-device P0 gates，不依赖外部 TestFlight 用户 |
| [x] | URL | 准备公开 Privacy Policy URL | Done | 2026-06-02 已部署到 Cloudflare Pages project `private-moments-site`；Simplified Chinese URL：`https://private-moments.popcornnn.xyz/privacy/zh-Hans`；English URL：`https://private-moments.popcornnn.xyz/privacy/en`；`/privacy` 为语言选择页 |
| [x] | URL | 准备公开 Support URL | Done | 2026-06-02 已部署到 Cloudflare Pages project `private-moments-site`，最终 URL：`https://private-moments.popcornnn.xyz/support`；`support@popcornnn.xyz` 已配置到私人收件箱，并已完成外部收信测试。 |
| [x] | URL | 决定是否提供 Marketing URL | Done | v1 不单独填写 Marketing URL；如 App Store Connect 允许留空则留空，Support/Privacy URL 使用现有公开站点 |
| [x] | URL | 决定是否提供 User Privacy Choices URL | Done | v1 无账号、无开发者托管数据删除入口；不单独填写 User Privacy Choices URL，隐私页已说明本地删除、iCloud、导出包和 AI provider 关闭/删除方式 |
| [x] | 隐私政策 | 起草 Privacy Policy | Done | 2026-06-02 `site/privacy/zh-Hans/` 与 `site/privacy/en/` 已按 Apple 5.1.1(i) 补强：覆盖数据清单、收集方式、用途、共享边界、AI provider、iCloud、导出、撤回同意、保留和删除；提交前需法律/最终 build 复核 |
| [x] | 隐私政策 | 在 App 内提供易访问 Privacy Policy 入口 | Done | 2026-06-02 Settings 新增 `Privacy & Support`，链接由 Info.plist / xcconfig 配置，并按当前 App 语言选择简中或英文 Privacy Policy URL |
| [x] | 隐私政策 | 建立 Apple 5.1.1 Privacy Policy 复查清单 | Done | 2026-06-02 新增 `docs/APP-STORE-PRIVACY-POLICY-CHECKLIST.md`，用于提交前逐项复核页面和官方要求 |
| [x] | 隐私政策 | 起草并实现 AI disclosure / explicit consent | Done | 2026-06-02 iOS 新增 `AI Privacy Permission` sheet、Settings > AI & Analysis 许可状态入口，以及底层 AI/text transcription 外发前 guard；提交前按最终 archive 复核 App Privacy Label、截图和 App Review Notes 文案一致性 |
| [x] | 数据审计 | 建立 App Privacy data inventory | Done | 2026-06-02 新增 `docs/APP-PRIVACY-DATA-INVENTORY.md`，覆盖数据类型、存储位置、传出路径、接收方、用途、App Privacy Label 初步口径和 P0 gates |
| [x] | 数据审计 | 填写 App Privacy Label draft | Published | 2026-06-11 App Store Connect final answer 已发布为 `Data Not Collected`；依据仍是 public build 无开发者默认 endpoint、无 analytics/crash/ads/tracking、AI 为用户自选 provider。若后续加入开发者托管 AI、analytics、crash upload、账号或反馈上传，必须重填 App Privacy |
| [x] | 数据审计 | 审计是否有 tracking / analytics / crash SDK | Done | 2026-06-02 当前 iOS target 未发现 Firebase/Sentry/Amplitude/Mixpanel/PostHog/Crashlytics/AdSupport/ATT 等路径；最终 archive 前仍需重扫 |
| [x] | Privacy manifest | 复核 `ios/PrivateMoments/PrivacyInfo.xcprivacy` | Done | 2026-06-08 `npm run doctor:app-store` 检查当前 source manifest：tracking=false、tracking domains 空、collected data 空、File Timestamp `C617.1`、UserDefaults `CA92.1`；未发现 required Disk Space API；最终 archive/privacy report 仍需复核 |
| [x] | Privacy manifest | 审计第三方 SDK privacy manifest/signature 要求 | Done | 2026-06-02 当前 iOS target 未发现 Apple 列表内常见第三方 SDK；如果后续新增 SDK 必须重审 manifest/signature |
| [x] | 权限 | 复核 Info.plist 权限 purpose strings | Done | 2026-06-08 `npm run doctor:app-store` 检查 Camera/Photos/Microphone/Speech/Local Network purpose strings 非空且非 placeholder；提交前仍建议做真实触发和权限拒绝路径 UAT |
| [x] | Export compliance | 完成 encryption/export compliance 判断 | Done | 2026-06-08 当前 iOS app 只发现 HTTPS/TLS、CloudKit、Keychain 等 Apple OS 安全能力；未发现 CryptoKit/CommonCrypto/自研或第三方 crypto。主 App `Info.plist` 已设置 `ITSAppUsesNonExemptEncryption=false`；最终 archive 前仍按 App Store Connect 上传反馈复核 |
| [x] | QA / UAT | 建立隔离 real-device UAT 安装入口 | Done | 2026-06-02 新增 `npm run ios:device:uat`，安装独立 `Ownlight UAT`，用于 first launch、AI consent、onboarding 和新用户状态验证，不覆盖日常 `Ownlight` 数据 |
| [x] | Onboarding | 设计 first launch onboarding 信息架构 | Done | 2026-06-02 确认：只做极短 welcome page，一个 `Start`，只讲私人时间线理念和本机优先安全感，不做三步功能导览或设置向导 |
| [x] | Onboarding | 设计空 timeline / 首条记录引导 | Done | 2026-06-02 确认：空库新用户创建今天顶部 welcome sample moment，展示正文、示例音频块、sample AI summary、tags、评论和一次性手势提示 |
| [x] | Onboarding | 设计 AI 配置入口和默认关闭/可选说明 | Done | 2026-06-02 确认：welcome sample 可展示 sample generated summary，但不讲 Base URL/API key；AI 配置留在 Settings > AI & Analysis，外发仍走 explicit consent |
| [x] | Onboarding | 实现 welcome page / welcome sample moment / one-time gesture hint | Done | 2026-06-02 已实现：空资料库首次安装显示极短 welcome page；`Start` 后进入 Timeline；本地 welcome sample moment 展示正文、示例音频块、sample generated AI summary、tags、评论和一次性手势提示；删除后本 installation 内不恢复；不提供 Settings replay/restore |
| [x] | Onboarding | 验证 welcome sample 数据边界 | Done | 2026-06-02 已加 focused tests 和 generic test build guard：sample 不创建 outbox/上传任务，不进入 archive export，不进入 Weekly Review / AI review 输入；AI regenerate/delete 对 sample summary 为 no-op；CloudKit build 已保持 sample exclusion，提交前随最终 App Store gate 再复核一次 |
| [x] | Settings | 设计 `Privacy & AI` 或同等隐私说明页 | Done | Settings 已有 `Privacy & Support`，AI 外发另有 `AI Privacy Permission` 和 Settings > AI & Analysis 许可状态入口；无需再做独立 `Privacy & AI` 页面 |
| [ ] | 数据安全 | 完成 release-grade local export/import UAT | Plan ready | 2026-06-08 已在 `docs/APP-STORE-UAT-RUNBOOK.md` 定义空资料库 export/import 恢复闭环；仍需最终候选 build + 真机跑完后才能关闭 |
| [x] | 数据安全 | 明确删除 App / 清空本地资料库 / 删除导出包的用户说明 | Draft done | 2026-06-08 Privacy Policy 已覆盖删除/保留边界，`docs/APP-STORE-SUBMISSION-DRAFT.md` 已补充无账号、本地 App container、iCloud、导出包和 AI provider 的删除口径 |
| [x] | Store metadata | 确认 App name | Done | 2026-06-10 更新：App Store name 和 Home screen display name 都用 `Ownlight`；中英文 metadata 统一使用同一品牌名，不另起中文名 |
| [x] | Store metadata | 确认 subtitle | Done | 2026-06-08 确认：zh-Hans `自己的私密时间线`，English `Your private timeline` |
| [x] | Store metadata | 撰写 description draft | Entered | 2026-06-10 zh-Hans / English description 已按 `docs/APP-STORE-SUBMISSION-DRAFT.md` 录入 App Store Connect iOS 1.0 version；定位为私密时间线、本地优先、可选 iCloud/AI，不把 AI 写成主卖点 |
| [x] | Store metadata | 准备 keywords draft | Entered | 2026-06-10 zh-Hans / English keywords 已录入 App Store Connect iOS 1.0 version；2026-06-21 提交审核前已随 screenshots/build 完成基本复核 |
| [x] | Store metadata | 准备 copyright / SKU / age rating / content rights | Done | SKU `private-moments-ios-v1`、copyright `2026 Weizhi Wang`、content rights no third-party content。2026-06-21 App Store Connect Age Rating 已保存为 global `4+`，Made for Kids / higher age override 为 not applicable |
| [x] | Store assets | 准备 App icon release 版本 | Done | 2026-06-11 build `1.0 (2)` 已上传并在 App Store Connect iOS 1.0 version 中选中；build 区域 `Included Assets` 已显示 `App Icon` |
| [x] | Store assets | 准备 iPhone screenshots | Uploaded / English set generated | 2026-06-21 App Store Connect iPhone `6.5" Display` 已上传 6 张 zh-Hans PNG，当前显示 `6 of 10 Screenshots`；App Preview 显示 `0 of 3 App Previews`，v1 intentionally 不做视频。2026-07-02 已生成英文 6.5-inch 候选图 `.tmp/ui-review/app-store-screenshots/iphone-6-5-en/`，6 张均为 `1284 x 2778` PNG；但 live `1.0 Ready for Distribution` Media Manager 的 English localization 仍显示 `Using Chinese (Simplified) 6.5" Display`，页面无上传/file input，替换截图可能需要下一版本 |
| [x] | Store assets | 决定是否做 app preview 视频 | Done | 2026-06-08 v1 不做 App Preview；App Preview 是 optional，首发先用截图降低制作、本地化和审核成本 |
| [x] | App Review | 撰写 App Review Notes draft | Draft done | 2026-06-08 已在 `docs/APP-STORE-SUBMISSION-DRAFT.md` 准备 no account、local-first、AI optional、iCloud opt-in、权限用途和核心测试路径 |
| [ ] | App Review | 如果有需要登录的路径，提供 demo account | Not applicable | 当前假设无登录 |
| [x] | TestFlight | 决定 v1 是否走 TestFlight | Skipped for v1 | 2026-06-08 确认：v1 不做 TestFlight；直接提交 App Store，审核通过后手动发布 |
| [x] | TestFlight | 保留 Beta App Description 草案 | Archived | `docs/APP-STORE-SUBMISSION-DRAFT.md` 仅保留为后续版本可复用材料，不是 v1 gate |
| [x] | QA | 定义 App Store common UAT path | Done | 2026-06-08 已在 `docs/APP-STORE-UAT-RUNBOOK.md` 定义 first launch、text/photo/audio/video、Share Sheet、AI、tags、Calendar、Check-ins、iCloud、Settings 路径 |
| [ ] | QA | 跑无网、本地重启、权限拒绝路径 | Plan ready | 2026-06-08 UAT runbook 已定义；仍需最终候选 build + 真机执行 |
| [ ] | QA | 跑性能/卡顿/大数据量 smoke | Plan ready | 2026-06-08 UAT runbook 已定义 800+ moments、Timeline、media、search/filter、Composer/Edit、Storage & Export smoke；仍需最终候选 build + 真机执行 |
| [x] | Accessibility | 定义 accessibility common tasks | Done | 2026-06-08 已在 `docs/APP-STORE-UAT-RUNBOOK.md` 定义 VoiceOver、Larger Text、icon label 和深浅色最小审计范围 |
| [ ] | Accessibility | 完成 VoiceOver / Larger Text / contrast 最小审计 | Plan ready | 未验证前不要在 App Store metadata 中夸大 accessibility 支持；最终候选 build 需要真机审计 |
| [x] | Release process | 稳定 bundle id / signing / App Group / entitlements | Done | 2026-06-11 正式 Release archive/export/upload 成功；导出 IPA 已复核主 App、Share Extension、App Group 与 Production CloudKit container 使用匹配的 owner 专用 identifiers，并确认 `get-task-allow=false`；具体值不进入公开源码快照 |
| [x] | Release process | 准备 archive upload / App Store direct-submission runbook | Done | 2026-06-21 新增 `docs/APP-STORE-SUBMISSION-RUNBOOK.md`，记录 screenshot 上传、age rating、中国大陆合规提示、最终 preflight、真实设备 smoke、manual release 和 `Add for Review` 的暂停边界 |
| [x] | Release process | 提交 App Store review | Submitted once | 2026-06-21 22:08 CST owner 确认后点击 `Add for Review` 和 `Submit for Review`；2026-06-24 build `1.0 (2)` 因 Guideline 2.5.4 / `UIBackgroundModes = audio` 被打回，manual release after approval 仍保留 |
| [x] | Release process | 处理 App Review 2.5.4 并重提 | Approved | 2026-06-24 已移除 background audio entitlement，语音 Moment / check-in audio / playback / AI summary 保留为前台-only；build `1.0 (3)` 已 archive/export/upload，App Review Notes 已补充 foreground-only audio 说明，后续通过审核 |
| [x] | App Review | 处理 App Review 3.1.1 / BYOK API key 反馈 | Approved | 2026-06-25 build `1.0 (3)` 被 Guideline 3.1.1 打回，reviewer 认为 API keys 启用 paid functionality 且不能通过 IAP 购买；2026-06-27 已通过 `Reply to App Review` 澄清 Ownlight 免费、无 IAP/广告/购买链接/开发者托管 AI，核心功能不依赖 API key，AI provider 只是用户自有/自托管 endpoint 的可选配置。2026-06-28 Apple 接受澄清并批准。 |
| [x] | Release process | 手动发布 App Store v1 | Released | 2026-06-28 22:35 CST 已点击 `Release This Version`；App Store Connect 当前状态为 `1.0 Ready for Distribution`。2026-07-02 已调整 availability 为海外 174 countries/regions、China mainland `Not Available`；该地区变更预计最多 24 小时传播。 |

## 推荐讨论顺序

1. **产品边界决策**：无账号、无 IAP、AI BYOK、CloudKit 范围、首发地区。
2. **隐私与 URL**：Privacy Policy、Support URL、AI disclosure、App 内入口。
3. **数据审计**：App Privacy Label、PrivacyInfo.xcprivacy、权限文案。
4. **新手引导**：first launch、空状态、AI 可选入口。
5. **Store listing**：name、subtitle、description、keywords、截图、icon。
6. **Final UAT / submission**：最终候选 build、owner iPhone/iPad UAT、截图、App Store Connect 填表、manual release。
7. **发布后监控**：监控 App Store Connect / 邮件反馈 / App Store listing；公开可下载后跑一次 App Store 安装版本 smoke。

## 当前已确认 URL / 联系方式

- 公开 URL 已确认使用产品专属 subdomain `private-moments.popcornnn.xyz`，不复用 owner/private backend tunnel endpoint。
- Support email 已确认使用 `support@popcornnn.xyz`；Cloudflare Email Routing 状态为 active，并已用外部邮箱完成收件测试。私人转发地址不进入公开仓库。
- `site/` 静态页面已部署到 Cloudflare Pages project `private-moments-site`。App Store Connect Simplified Chinese localization 应填 `https://private-moments.popcornnn.xyz/privacy/zh-Hans`，English localization 应填 `https://private-moments.popcornnn.xyz/privacy/en`。App Store build 环境应设置：`PRIVATE_MOMENTS_PRIVACY_POLICY_URL=https://private-moments.popcornnn.xyz/privacy`，`PRIVATE_MOMENTS_PRIVACY_POLICY_URL_ZH_HANS=https://private-moments.popcornnn.xyz/privacy/zh-Hans`，`PRIVATE_MOMENTS_PRIVACY_POLICY_URL_EN=https://private-moments.popcornnn.xyz/privacy/en`，`PRIVATE_MOMENTS_SUPPORT_URL=https://private-moments.popcornnn.xyz/support`。

## 维护规则

- 每开始一个上架准备子项，先在本文件中把对应任务标为进行中或补充决策。
- 每完成一个子项，必须把 `Done` 改为 `[x]`，并在 Notes 写清验证方式或产物链接。
- 如果 Apple 官方要求或 App Store Connect UI 有变化，更新“官方要求核对结果”并记录日期。
- 不要把未来计划写成已实现能力；App Store metadata、隐私政策、隐私标签必须跟当前提交 build 一致。
