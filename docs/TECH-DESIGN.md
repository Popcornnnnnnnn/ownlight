# Ownlight Technical Design

## 1. 架构概览

Ownlight 采用 iOS 原生 App + 可选 iCloud / CloudKit private sync 的本地优先架构。当前产品边界里，iPhone 本地 SQLite 是默认 source of truth；无网络、无 iCloud、无 server 时，日常记录和浏览仍应完整可用。

```text
  iPhone App
  Swift + SwiftUI
  Share Extension
  SQLite3 local database
  local drafts
  local timeline cache
  compatibility outbox state
  media compression
        |
        | Optional iCloud / CloudKit
        | private database, same Apple Account
        v
CloudKit Private Database
  custom private zone
  deterministic records
  media CKAsset transfer
  local-first conflict guards

Legacy / optional maintenance workspaces:
  server/ + admin/ for historical compatibility,
  archive diagnostics, and API contract reference
  transcription-gateway/ for advanced transcription endpoint
```

第一阶段的用户体验以 iPhone 本地数据为准：iPhone 离线时可以完整创建内容和浏览已有本地内容；iCloud 可达后再做同一 Apple Account 下的私有跨设备复制。CloudKit private sync 已完成 M017 第一阶段 UAT：开启后普通 Timeline create/update/delete 会进入独立 CloudKit queue；删除整条 Moment 会同时为其媒体、评论、Timeline AI summary 和 post-tag assignment 生成 tombstone；新建媒体 Moment 会同时上传 parent moment metadata、media metadata 和 app-owned media assets；编辑 Moment 增删媒体时也会分别入队新增媒体 metadata/assets 或被移除媒体的 delete。首次普通 sync 会运行一次 `cloudkit_initial_upload_v1` 本地库准备，把已有允许范围数据排入 CloudKit pending queue；正常 sync 成功后还会用独立 `cloudkit_full_reconcile_v1` scope 做一次完整 private-zone pull，用来恢复旧版本或历史 cursor 前进后遗漏的可选派生记录。launch/foreground、开启开关、本地变更 debounce、手动 `Sync Now` 和前台低频 poll 会触发同步。CloudKit 属于可选的数据复制层，不能重新把 AI、设置或日常记录能力耦合到同步是否可用。

AI & Analysis 走 iPhone-direct provider 配置：用户在 Settings 里配置一个或多个 text analysis provider profile，API key 只存本机 Keychain；provider metadata、生成结果、summary/title/tag/review artifact 和私有 transcript metadata 可以作为未来同步数据，但 credentials 永远不进入 iCloud、Mac server 或导出包。普通音视频、check-in audio 和 weekly review 的目标数据流是 `local media -> private transcript -> text analysis provider -> generated artifact`。语音转录默认使用 iPhone on-device transcription；本机转录会记住上次成功的中文/英文内容 locale，后续优先直接使用该 locale，只有本机语音语言不匹配类失败才尝试另一种语言。Advanced transcription 的 UI 只有 `iPhone On-device` 和 `OpenAI-compatible Endpoint` 两个选项；外部 endpoint 配置语义统一为 Base URL、API Key、Model。Local Gateway、LAN、Tailscale、Cloudflare 或本地网关只是 endpoint URL 背后的连接/部署方式，不再是单独 provider 类型；旧 `local_gateway` 本机设置会迁移为 `custom_openai_compatible`，保留 URL/model metadata 和 Keychain token。外部 endpoint `Test Connection` 使用当前表单值调 `/v1/models`，不要求先 Save；成功后把这组可用配置保存到本机 settings 和 Keychain，失败时保留旧配置。真实音频转录统一调 `/v1/audio/transcriptions`；如果旧配置把 Base URL 粘成 `/health`，iOS 会在 `/v1/...` 调用中把它视为 service root。外部 transcription provider 只返回 transcript，不读写 iPhone SQLite、不生成 summary、不进入 sync/server AI job 队列。transcript 正文是本机私有诊断数据：默认不在 Timeline 展示，不进入本机导出包正文，只在 audio/video Summary sheet 的 `Original Text` 底部动作或 check-in audio detail 的诊断区域供用户排查。外部 transcription/audio-input provider 属于 Advanced。

## 2. Monorepo 结构

项目放在 `private-moments/` 子目录，不直接在上层 `07-github` 根目录工作。

建议结构：

```text
private-moments/
  ios/
    PrivateMoments.xcodeproj
    PrivateMoments/
  transcription-gateway/
    package.json
    src/
  server/
    package.json
    src/
      api/
      auth/
      config/
      db/
      media/
      sync/
      admin/
      logging/
    prisma/
      schema.prisma
      migrations/
  admin/
    package.json
    src/
  shared/
    openapi.yaml
    sync-protocol.md
  docs/
    PRD.md
    TECH-DESIGN.md
    INTEGRATION-GUIDE.md
    OPERATOR-RUNBOOK.md
    HANDOFF.md
    DESIGN-PRINCIPLES.md
```

当前仓库包含 `ios/`、`transcription-gateway/`、`server/`、`admin/` 和 `shared/`。其中 `ios/` 是当前产品主线；`transcription-gateway/` 是高级转写 helper；`server/`、`admin/` 和 `shared/` 作为 legacy compatibility、archive/diagnostics 和历史 API/sync contract 保留。

当前实现已经覆盖第一版本地构建：iOS 本地优先发布文字、图片、语音、短视频和 PDF 文档附件，系统 Share Sheet 导入入口，主时间线单用户私密评论，独立 Check-ins 生活活动记录，check-in 照片/语音附件，手动选择发生时间、草稿保存、离线兼容队列、自动延迟重试、图片压缩、视频压缩与 poster、音频录制与播放、iPhone-direct AI provider 设置基础、本地媒体缓存、设置页存储/导出、App Language-aware 人性化时间标签、滚动月份浮层提示、时间线搜索、收藏、筛选、Calendar Review、详情页、编辑、软删除、iOS 本机语言偏好、空资料库本地 archive import，以及 CloudKit opt-in 普通 Moment/media、comments、tags、check-ins、ready AI artifacts、draft metadata 和 preference allowlist 自动同步、首次本地库 queue preparation、非空第二设备保护和一次性 full reconciliation 恢复。

iOS 仍保留同步/outbox 和上传状态字段用于旧数据兼容和后台复制层，但这些字段不再是主 UI 概念。普通 Timeline / Detail / Check-ins 不展示 `SyncBadge`，Timeline filter 不提供 `Needs Sync`，Settings 的本机 Storage & Export 只展示本机存储、手动导出和空资料库导入。iCloud 主页面只展示用户可理解的状态、`iCloud Sync` 和 `Sync Now`；CloudKit container、smoke test 和 default-zone probe 不进入普通用户界面。legacy server diagnostics 只作为维护/兼容路径存在。

历史 v0.1 owner reliability layer 曾增加 Mac Admin `Archive` 和 Sync Health。Archive 使用 restic 作为底层 deduplicated snapshot 工具，server 通过 durable `maintenance_jobs` 记录备份、检查、恢复和 promote preparation；这些能力现在属于 legacy maintenance，不是本地优先 iPhone 日常使用入口。

当前 UI 设计原则是保持主时间线安静：筛选、Calendar 回看、收藏和管理能力应尽量藏在 toolbar menu、底部 review tab、滑动操作或详情页里，避免把主界面做成后台管理界面。详细原则见 `docs/DESIGN-PRINCIPLES.md`。

iOS 主要模块已经按职责拆分。`TimelineStore` 按 session、mutations、sync、server changes、media、check-ins、payloads 和 sync retry 拆分；`LocalDatabase` 按 schema、records、timeline、sync、storage stats、check-ins/check-in media 和 SQLite helper 拆分；`TimelineView` 拆出 `TimelineRow`、`MomentDateFormatter`、`MediaGalleryView` 和 `ZoomableLocalImage`。设置页存储诊断拆在 `StorageStats.swift` 和 `StorageSettingsView.swift`。后续继续加功能时优先扩展这些小文件，不再把同步、数据库或主界面逻辑塞回单一大文件。

## 2.1 时间线交互决策

时间线 UI 保持低干扰原则。`MomentDateFormatter` 负责把 `occurredAt` 转换为跟随 App Language 的生活化标签：英文如 `Just now`、`2 min ago`、`Today 2:40 PM`、`Yesterday 2:40 PM`、`Apr 29, 2:40 PM`，中文如 `刚刚`、`2分钟前`、`今天 14:40`、`昨天 14:40`。月份标题不再作为列表里的常驻结构块，而是通过滚动时短暂出现的 `FloatingMonthIndicator` 提供方向感；停止滚动后自动淡出。

时间线删除使用右侧 swipe action 打开居中的系统 `alert`。右滑删除不允许 full swipe，并在点击 Delete 后延迟约 180ms 展示确认框，让系统 swipe 行先收回，避免列表跳动。这里不要使用位置相关的 `confirmationDialog`，因为它会表现得像从某个列表行冒出的气泡，删除确认语义不够清楚。

### 2.1.1 主时间线评论决策

评论由主时间线直接承载，不走单独内部评论界面。每条动态下有轻量评论入口，使用 `text.bubble` 语义图标；有评论时显示真实数量，没有评论时只显示图标，不显示 `Comment` 文案，也不使用编辑图标、加号或常驻灰色圆底。评论入口按下时显示轻量灰色胶囊底和缩放反馈。评论预览采用旁注式样式，用轻量竖线和缩进文本代替整块灰色评论卡片。默认预览最新两条评论，但预览内部按旧到新排列，避免阅读顺序倒置；`View all N comments` 和 `Show less` 在原位展开/折叠完整评论列表。

评论输入使用底部输入栏。点击某条动态的评论按钮后，输入栏显示 `Commenting on: ...` 或 `Photo moment · N photos` 等目标摘要并聚焦键盘。Return 插入换行，`Send` 发送；发送成功后收起输入栏，展开该动态评论区，并把时间线滚到该 moment 的底部，让最新评论可见。切换目标或关闭非空草稿时需要确认丢弃。

评论内容是 plain multiline text，最大 500 字符。第一版不支持评论作者、回复、点赞、媒体、Markdown/rich text 渲染、编辑或复制选择。长按评论行触发 `Delete comment?` 居中确认框；确认后只删除评论，不删除父动态。评论行不显示 `synced`、`pending` 或 `failed` 等逐条同步标识。

搜索先应用既有筛选，再匹配动态正文或评论文本。命中评论时，时间线仍显示父动态，但评论预览优先展示最多两条匹配评论并轻量强调命中行；评论数量始终是真实未删除评论总数，不变成搜索命中数。历史转写 metadata 可继续作为旧数据兼容存在；新 iPhone-direct audio/video summary 会在本机生成 private transcript，但 transcript 不进入 Timeline 默认展示，只作为搜索/重跑/排查输入，并通过 Summary sheet 底部 `Original Text` 动作查看。

### 2.1.2 Calendar Review 决策

Calendar 是 Timeline 的底部 tab 同级 review 模式，用于看过去某段时间的发布密度和快速回到某一天。Settings 不再作为底部 tab，而是保留在 Timeline/Calendar 的 toolbar 设置入口里。Calendar 不提供 Compose、新建、编辑或归档管理功能。

Calendar v1 完全由 iPhone 本地 Timeline 数据派生，不增加 SQLite schema、sync operation、server calendar API 或 Mac 统计缓存。它默认显示当前月份，支持左右箭头、横向滑动和 `Today` 返回当前月；月份网格固定为 42 个日期格，包含空月份和相邻月份日期。Weekday 顺序跟随 `Calendar.current.firstWeekday`，month/day 文案跟随 App Language。

日期格用低饱和 heatmap 表达本地 moment 数量。低频月份保持固定阈值，忙碌月份按当前可见月份的最高发布日做相对分级，支持 `light`、`medium`、`strong`、`intense`、`peak` 等层次，避免 4+ 后全部同色。日期格可以显示轻量数量标签，并最多显示两个媒体提示图标，作为记忆触发而不是内容列表。未来日期淡出且不可点击；今天只用轻量描边，不做任务 App 式强调。

Calendar 有自己的轻量月份筛选：All/Text/Photos/Audio/Video、Favorites 和 Comments。筛选只影响 Calendar 的 heatmap、媒体提示、日期是否可点和 Month Stats，不继承也不改变 Timeline 的搜索/筛选状态。Calendar navigation bar 的 `topBarTrailing` toolbar 放置 Month Stats 和 Settings 等低频入口；Month Stats sheet 由本地 month model 派生，展示总数、活跃天数、活跃日均、最多的一天、每日柱状节奏和内容组成，不展示单独 Summary 数量。Sheet 不放 Close 按钮，依赖系统下滑关闭；最多的一天和每日柱状条可直接进入对应 Day Review，内容组成行可把 Calendar 月份筛选切到对应类型。点击有内容的日期会在 Calendar navigation stack 内 push 一个完整 `Day Review` 页面，并使用未被月份筛选裁剪的当天数据；Day Review 右上角 `Timeline` 才是切回 Timeline 并应用临时 day filter chip 的二级动作。清除 chip 后 Timeline 恢复完整列表。普通 Timeline/Calendar tab 切换应保留 Timeline 原滚动状态。

Day Review 不使用 grouped `List` 或 sheet 的灰色大块背景，而是用 ScrollView + 无卡片日内时间轴表达“这一天发生了什么”。顶部显示日期、星期、当天 moment 总数和媒体构成；每条记录左侧是 24 小时制时间点，右侧是内容预览。Day Review 自带轻量横向 chips，多选 Photos、Audio、Video、Favorites、Comments 时按 OR 关系显示内容，点已选 chip 可取消，点 All 清空筛选；Summary 不作为独立筛选项。日内记录用 Morning/Afternoon/Evening/Late Night 等轻分隔增加一天内部的节奏。记录正文中的 `#` / `##` 标题做轻量 Markdown 渲染，正文缺失时回退到 AI 标题或媒体 fallback；不再显示 primary tag chip。图片 moment 在 Day Review 里全部显示为统一小缩略图，单张图片也不放大；视频只显示类型/时长提示，不播放、不自动播放，也不显示 poster；音频可行内播放并显示 ready/summarizing/failed summary 入口。点击非音频控件区域会 push 到 `MomentDetailView`，返回时保持在同一天 Day Review；Day Review 用本地 `UserDefaults` 按日期保存当前可见 moment id，返回 App 或重建该日期页面时恢复上次浏览位置。日期格点击反馈沿用 app 的轻量手感：`0.985` 左右的按压缩放、浅 tint、无阴影，并在确认进入 Day Review 时触发一次 selection feedback。旧 Timeline toolbar `Jump to date` 日历图标在 Calendar 落地后移除，避免两个日期入口并存。

### 2.1.3 Pinned Moments 设计

Pinned Moments 是时间线顶部的快捷回看层，不是新的内容类型。它只增加主 Timeline 顶部的可达性：置顶 moment 仍保留在普通主列表的原时间位置，并用轻量 pin 图标提示状态；它不改变 `occurredAt`、Calendar/Day Review 统计、Review 输入范围、搜索/筛选结果或原 moment 身份。

数据模型：

- server `posts` 增加 `is_pinned` 和 nullable `pinned_at`。
- iOS `local_posts` 增加 `isPinned` 和 nullable `pinnedAt`。
- 同步使用独立 `update_post_pin` operation，payload 包含 `isPinned`、nullable `pinnedAt` 和 `updatedAt`。
- server 接收后更新 post metadata，发出 `post_pin_updated` server change。
- `post_created` 和 `post_updated` payload 应包含 pin 字段，用于新客户端 baseline/recovery。
- export/import、Archive restore 和 staged promote 必须保留 pin metadata。

排序和冲突：

- Pinned 区域按 `pinnedAt DESC` 排序，时间相同时用 `occurredAt DESC` 和 id 做稳定兜底。
- 多设备或多次操作采用当前 sync 的 last-write-wins 语义，以 server 接收顺序为准。
- 删除 post 后，它自然从 Pinned 区域消失；`post_deleted` 已足够，不需要额外 unpin change。

Timeline UI：

- Pinned 只出现在主 Timeline，并且只在没有 active search/filter state 时出现；搜索、日期、Tag、Favorite、评论、内容类型或 match-source 筛选都会隐藏 Pinned。
- Timeline 顶部默认只显示 `Pinned · N` 汇总 header。
- 已置顶 items 保留在普通 Timeline list 的原时间位置；Pinned header/sheet 只是额外快捷入口，不搬移动态。
- 当置顶 items 作为普通 Timeline row 显示时，row 顶部 metadata 区显示一个低权重 `pin.fill` 图标，和 Favorite 一样作为状态提示，不增加文字或新操作按钮。
- 当 pinned 数量为 1-3 条时，点击 header 展开/收起最多 3 条标题行。展开/收起状态只保存在本机 `UserDefaults`，不进入 sync。
- 当 pinned 数量超过 3 条时，点击 header 打开底部 sheet，显示完整 pinned 标题列表。
- Pinned shelf 的实现必须保留上面的数量阈值语义；UI 重构、交互修复或容器调整不能把 `1-3 条 inline expand/collapse` 和 `>3 条进入 sheet` 的行为带丢。
- 如果 inline pinned 卡片需要 grouped 连续视觉，不要再把多条 pinned item 塞回同一个原生 `List` row 里做内部点击区域；那会把系统 pressed/highlight 反馈重新耦合成整块。应继续保持 pinned shelf 脱离主 Timeline `List`，或采用同样能保证单条独立点击反馈的结构。
- 标题行只显示标题和轻量发生日期辅助信息；不显示正文、media grid、comments、AI summary、tag wall 或 sync success badge。
- Pinned sheet 使用内部 `NavigationStack`。点击 pinned 行在 sheet 内 push 正常 `MomentDetailView`，Back 返回 pinned 列表；sheet 内 detail 保留编辑、删除、favorite、tag、pin/unpin 等完整行为。
- Pin / Unpin 入口放在 Moment Detail 顶部 `More` 菜单、Timeline row context menu 和 pinned sheet row context menu。不要给每条普通 row 新增常驻 pin 按钮，也不要占用现有 Favorite swipe action。
- Calendar、Day Review 和 Weekly Review 不新增 pinned 入口或 pin 标记。

标题生成计划：

1. 正文第一条非空 `# ` 或 `## ` 标题，去掉 marker。
2. 正文第一条非空普通行，单行截断。
3. ready audio/video AI summary 的 `documentTitle`。
4. `Photo moment` / `Audio moment` / `Video moment` 之类媒体 fallback，必要时加发生日期。

第一版不新增自定义置顶标题、手动拖拽排序、Pinned-only Timeline filter 或 Admin pin management。自定义标题会新增用户编辑字段，拖拽排序会新增排序冲突语义；两者都留到需要时再单独设计。

Pin 与 Favorite 保持独立。Pending、failed、partial 和 synced 本地 moment 都允许 pin/unpin，操作写入 outbox 后按普通同步流程发送。多设备冲突以 server 接收顺序为准，last server-accepted wins。删除 post 后 Pinned 表面直接不再显示它，不额外生成 unpin operation。

### 2.1.4 Check-ins 设计

Check-ins 是第三个底部 tab，和 Timeline、Calendar 并列；默认启动 tab 仍然是 Timeline。它记录重复生活活动，例如吃饭、运动、起床和健康饮食，但不把这些活动伪装成普通 moment。

数据模型分两层：

- `checkin_items` / `local_checkin_items` 定义活动：名称、SF Symbol `symbolName`、颜色、`oncePerDay` 或 `multiplePerDay`、可选 `dayStartHour`、活跃星期、手动排序、默认 `showInTimeline`、可选 tag、archive/delete 状态和 sync 状态。
- `checkin_entries` / `local_checkin_entries` 定义一次打卡：item id、发生时间、可选 note、entry-level `showInTimeline`、soft delete 状态和 sync 状态。

Check-in 图标没有单独的 server/database icon 表。同步协议只保存 SF Symbol 名称字符串；iOS 编辑器提供本地精选图标 catalog、类别筛选、搜索、预览和高级 `SF Symbol name` 输入，并在保存前用系统 symbol lookup 校验。只有未来需要跨平台可管理 icon library 时，才重新考虑 icon catalog 表。

一次一天 item 使用 item day 做去重，item day 由 `dayStartHour` 定义，默认 00:00；例如 Bed 可以把 `Daily reset` 设为 12:00，使 00:30 属于前一晚、23:30 属于下一晚。编辑 entry 时间时也要按同一 item day 重新校验是否已有 entry。一天多次 item 不做时间冲突 UI，因为用户不需要在同一时间连续打卡；按发生时间自然排序即可。Item 还同步一个 `timeVisualization` 配置，取值为 `none`、`timeLine` 或 `timeHeatmap`，旧 item 默认 `none`。`timeLine` 只允许 `oncePerDay` item 使用；`multiplePerDay` item 只能用 `none` 或 `timeHeatmap`。

Check-ins UI 的默认路径必须是 one tap。`Today` row 左侧 icon 负责一键打卡；已经完成的一天一次 item，左侧 icon 打开今日 entry。中间 item 区域打开只读 item insights/trends 页，右侧低权重入口打开单独表单，允许填写 note、发生时间、照片和 `Show in Timeline`。Entry detail 支持修改 note、发生时间、Timeline 显示开关，或取消打卡。`Manage` 负责 item 创建、编辑、archive/delete；item row 整行都是编辑入口，并提供按压/hover 式反馈，避免只有图标像可点击。创建 item 可以稍复杂，但日常打卡不能被表单拖慢。

Item insights 是只读回看页，不进入 Manage。`timeLine` 使用最近 30 天回看窗口，但绘图区从窗口内第一条有效记录所在日期开始延伸到今天；缺失日期为空点并断线，只有 today 一条记录时点位于左端。发生时间是 Y 轴，Y 轴根据真实最早/最晚时间自动外扩；当晚间/凌晨时间跨午夜时，图表会把凌晨点展开到连续晚间区间。折线图支持点按和横向拖动探索，交互时选择最近的真实记录点，显示竖向虚线 guide、点高亮和日期/时间浮层。`timeHeatmap` 展示最近 30 天所有非删除 entry 的发生时间，使用 1 小时 bucket，同时显示 `24h distribution` 和 `weekday x hour`，支持一天多次记录；小时分布可点选，weekday x hour 行可横向滑动选择，选中后显示该 bucket 的记录数和最近记录，并通过既有 entry detail 查看单条记录。第一版不做聚类、AI 解读、提醒、目标或连续天数。

Timeline 使用混合 feed：普通 `TimelineItem` 加上 `showInTimeline=true` 的 `CheckInFeedEntry`。Check-in row 由 item 图标/颜色和 item 名称表达身份，可显示 note 和可选 tag，但不提供 comments、favorite、pin、AI summary、transcription、OCR 或 AI auto-tagging。关闭某条 entry 的 `Show in Timeline` 只影响 Timeline 和 Timeline search/filter；entry 仍保留在 Check-ins、Calendar 和 sync 数据中。

Calendar 使用 check-ins 作为 activity signal。Heatmap、每日 activity count、Day Review 和 Month Stats 都纳入非删除 check-in entries，并在 Month Stats 中区分 `Moments` 和 `Check-ins`。Day Review 显示当天所有 check-ins，包括隐藏于 Timeline 的 entry；页面顶部可以先展示一个按发生时间排序的 compact check-ins rhythm strip，作为当天生活节奏的一眼扫读入口，点击仍进入既有 entry detail。真正统计型信息仍以 Calendar Month Stats 为主；Check-ins History 只显示最近周/月和 item 概况，避免把 Check-ins 变成 KPI dashboard。

Sync 使用四个独立 operation：

- `upsert_checkin_item`
- `delete_checkin_item`
- `upsert_checkin_entry`
- `delete_checkin_entry`

这些 operation 的 `entityType` 分别是 `checkin_item` 和 `checkin_entry`。Server changes 对应 `checkin_item_updated/deleted` 和 `checkin_entry_updated/deleted`。删除 item 会 soft-delete 其 entries；客户端应用 item delete 时本地级联即可。

Check-in media 使用独立的 `checkin_media` / `local_checkin_media` 父对象，不复用 ordinary post media。当前支持 still image 和单段 audio：图片来源是相册 `Add Photos` 或相机 `Use Camera`，语音来源是 Check-ins UI 内部录音并保存为 AAC/M4A。上传和恢复统一走 `/api/v1/checkin-media/upload`、`/api/v1/checkin-media/batch-download` 和 `GET /api/v1/checkin-media/:mediaId`。图片会出现在 Check-ins History、Calendar Day Review、Month Stats 和 Photos filter 中；语音会出现在对应的 History/Day Review/Month Stats 和 Audio filter 中；这些都不受 entry 是否发布到 Timeline 影响。Check-in audio summary 必须停留在 check-in 自己的 `checkin_ai_summaries` / `local_checkin_ai_summaries` 路径，不创建 ordinary post、ordinary post media、AI title auto-insert 或 AI tags。新架构下 check-in audio summary 由 iPhone-direct AI path 生成；Mac server 上传路径不再自动 enqueue check-in summary job。

v1 明确不做 reminders、streak、missed count、completion rate、preset templates、Mac Admin management、separate export、AI tags 或 OCR。Optional tag 默认 none，并且是 item-level secondary metadata；即使 check-in audio 已支持自动摘要，check-ins 也不应自动获得 ordinary moment 的 AI title/tag side effects。当前 check-in media 已启用 image 和 audio；如果后续扩展 video，必须继续使用 check-in-owned media，而不是把 check-ins 写成 ordinary posts。

## 2.2 详情与编辑决策

详情页是单条动态的管理入口。时间线点击动态进入详情页，详情页负责查看完整内容、图片/视频/语音浏览播放、编辑入口和删除入口。图片浏览器只负责查看，不承担删除操作；视频使用全屏播放；语音使用全局复用的细进度线播放条。

媒体模型支持 `image`、`video`、`audio`、`document` 四种 `kind`。每条动态只允许一种媒体类型：图片最多 9 张，视频 1 段，普通新建 Moment 语音最多 9 段，PDF 文档附件 1 个；Edit Moment 和 Share Import 暂不新增多音频或 PDF 创建能力。PDF 从 Composer `More > Files` 导入后以 `document` media 保存和上传，默认不转成图片，不触发 OCR 或 AI summary，Timeline/Detail/Edit 通过文件卡片和系统 Quick Look 预览。视频从相册导入后在 iOS 端压缩为 720p H.264 MP4，并生成 JPEG poster 写入 `thumbnail` variant；时间线里由单例 muted autoplay center 选择当前最靠近视口中心的视频静音自动播放，滑走、打开详情/全屏/发布页时停止，点击视频仍进入全屏播放。语音通过 AVAudioRecorder 写入 AAC/M4A，每段作为独立 `audio` media 以 `sortOrder` 排序；发布页里的 `Record Audio` 开始新段，`Pause/Resume` 只控制当前段，`Done` 才把当前段加入草稿。Composer 消失或 App scene 变为非 active 时，当前录音自动暂停而不是 finalize；由 presenting view 持有录音控制器，因此 sheet 被滑走后重新打开仍能继续当前暂停录音。Check-in 录音同样在 App scene 非 active 或页面消失时暂停，避免首版声明后台录音能力。本地播放进度按 media id 存在 UserDefaults；中途暂停或切走会保存进度，完整播放结束会清除该 media 的进度并让播放条回到初始未播放状态。音频播放在 App 仍 active 的界面切换中自动暂停，例如切换 Timeline/Calendar、进入详情、打开 Settings/Composer/Summary/gallery/video 或退出 Day Review/Detail；进入后台或锁屏时也会暂停并保存进度。v1 不声明 `UIBackgroundModes = audio`，不承诺持久后台录音或后台播放。语音条是全局复用的细进度线播放条：左侧独立播放/暂停按钮，中间进度线支持点按和拖动 seek，下方显示当前/剩余时间，右侧轻量 `1x/1.5x/2x` 菜单调倍速；Timeline、Detail 和 Day Review 会渲染同一 Moment 下的所有 audio 段。语音条不显示重复的 `Audio` 标题、不使用假波形，也不使用突兀的整块灰色卡片；正文语境由 moment text 或 comments 承担。语音/视频摘要目标路径默认是 iPhone on-device transcription 生成 private transcript，再交给用户配置的 text analysis provider；当 Settings > AI & Analysis > Advanced Transcription 选择外部 transcription provider 时，iPhone 会把本地音频文件以 OpenAI-compatible multipart 请求发给配置的 Base URL，拿到 transcript 后再继续同一条 text-analysis 路径。旧的 `transcriptionText` sync 字段只为历史兼容保留。评论仍然是纯文字，不复用媒体模型。

编辑采用直接覆盖模型：保存后原动态只显示最新文字、发生时间和图片列表，不提供可见历史版本。编辑页支持修改文字、发生时间、新增图片、删除图片和 9 张以内图片的长按拖拽重排。New/Edit Moment 与 Check-in create/edit 的发生时间选择器都不允许选到当前时间之后；保存入口还会在写入 SQLite / outbox 前把 `occurredAt` clamp 到当前时间，避免旧草稿、分享导入或未来入口绕过 UI 限制。保存时，编辑页里的最终图片列表就是新状态；服务端软删除移除的图片，保留新增图片等待上传，重排后的 `sortOrder` 作为权威顺序。

编辑入口不再等待 moment 完全 synced。`pending`、`partial`、`failed` 和 `synced` 的 moment 都可以编辑正文、时间、媒体顺序和标签；本地最新状态是用户看到的权威状态。当前主路径通过 CloudKit pending queue 在 iCloud 可用时同步，legacy server path 仍可通过 outbox operations 和 media upload queue 收敛旧 archive。详情页的正文复制动作复制 `post.text` 的 Markdown source，避免引入另一套富文本导出模型。

Share Extension 仍保持 thin extension 边界：截图、图片、音频、视频、网页 URL、微信文章 URL 或文本分享只会被 staged 到 App Group inbox，主 App Composer 负责最终编辑和发布。文章/URL 类内容不新增服务端抓取链路；iOS 从正文中的 URL 派生轻量 link-card 样式，点击时交给系统打开原 URL，是否回到微信由 iOS/微信的 Universal Link 或 URL 处理能力决定。

iOS New Moment composer 和 Edit Moment 的正文输入仍保存 `post.text` 为 Markdown source `String`。编辑器保持轻量 source editor，不提供常驻 Markdown 工具栏、H1/H2 键盘 accessory、list 按钮、Done 按钮或复杂格式控件；用户仍可手写行首 `# ` / `## ` 作为标题语法。普通 `- `、`• ` 和 numbered list continuation 仍可作为输入辅助存在，但编辑器不再试图把所有 Markdown block 在可编辑 `UITextView` 中实时富文本化，以避开中文等输入法 marked text 被刷新打断的问题。

Timeline、Detail、Day Review 和 Weekly Review 正文的只读渲染优先走 `MomentTextMarkdown.renderingSource` + Foundation `AttributedString(markdown:)`，因此支持更丰富的系统 Markdown 语法，例如多级标题、强调、链接、code、quote、无序/有序列表等；搜索索引会对常见 Markdown marker 做 line-based stripping，保留可读文本而不把符号噪声写入匹配内容。远程 Markdown 图片默认降级为普通链接，raw HTML 默认转义显示，避免私密 moment 渲染时请求外部 URL 或让 HTML-like source 进入渲染。`Settings > Appearance > Markdown > Advanced Rendering` 提供深层 opt-in：`Math Formulas` 会把 `$...$` / `$$...$$` 作为 code-like LaTeX source 渲染，`Remote Images` 允许 Markdown image syntax 进入渲染管线，`Raw HTML` 允许 HTML-shaped source 通过系统 Markdown 解析；这些选项默认关闭，开启前必须确认风险。当前没有引入 WebView、MathJax/KaTeX 或第三方 Markdown package，因此数学公式不是完整排版渲染，raw HTML 也不是可执行 HTML。

发布页会拦截真实剪贴板图片粘贴。粘贴到正文区域的图片不会写入 `post.text`，也不会解析 Markdown 图片语法，而是追加到现有 image draft media grid，并复用相册/相机图片的草稿保存、预览、最多 9 张、单一媒体类型、发布压缩、SQLite/outbox 和 sync 路径。普通文字粘贴继续由系统文本编辑器处理并可被 Markdown 渲染层识别；Edit Moment 第一版不启用图片粘贴，避免扩大编辑媒体替换语义。

iOS 继续本地优先：编辑先写入本地 SQLite，再按已启用的数据复制层进入 CloudKit pending queue 或 legacy outbox。AI 生成状态不应阻塞普通保存、编辑或同步；legacy Mac server 上传路径不再在 media/check-in media upload 后自动 enqueue AI jobs。同步中或部分同步的动态暂不允许编辑，避免多个本地操作和媒体上传互相打架；已同步或失败的动态允许编辑。编辑页的最终媒体列表是权威状态：新增媒体入队 CloudKit media metadata + asset upload，被移除媒体入队 media delete。新增图片上传失败时，动态显示 `partial`。

收藏是独立的轻量元数据操作，不进入编辑页。iOS 本地更新 `isFavorite`；CloudKit 路径把它作为 moment metadata 更新同步，legacy server path 仍通过 `update_post_favorite` outbox operation、`post_favorite_updated` server change 兼容旧 archive。置顶、topic tag/alias/assignment、check-in item/entry/media、ready check-in AI summary 和 allowlist 内的 app preference 也会在 `iCloud Sync` 开启时进入 CloudKit pending queue；AI provider profiles、API keys、Base URL、model、provider fallback state、raw transcript 和 diagnostics 仍保持 device-local。

编辑草稿按 `postId` 保存在本机文件目录中。打开编辑页时如果有草稿，先询问继续编辑草稿或丢弃草稿。保存成功或用户主动丢弃后清除草稿。

### 2.2.1 Share Extension 与导入队列

系统分享入口以真正的 iOS Share Extension 形式存在，显示名为 `Save to Ownlight`，随主 App 安装和卸载。它不是单独 App，也不直接承担完整发布流程。

Share Extension 的职责保持很窄：

- 从 Share Sheet 接收最多 9 张图片、1 段视频、1 个音频文件、URL 或纯文本。
- 允许用户在 extension 内补一句 plain text note。
- 把文件复制到 App Group 容器的 `ShareImports/<importId>/files/`，并把 `import.json` 作为 metadata 写入同一个 import 目录。
- 通过 `moments://import/<importId>` 唤起主 App。

主 App 负责真正的导入消费。`RootView` 监听 share import notification 并打开现有 `ComposerView`；`ComposerView` 从 App Group import queue 读取最早的 pending import，把文本合并到 composer 草稿，把图片读为现有 image draft，把视频交给 `VideoMediaProcessor.prepareVideo`，把音频复制到 draft media 目录并交给 `AudioMediaInspector`。消费成功后删除 import 目录。

这个边界避免了三套入口各自实现发布逻辑：相册 picker、相机、录音、Share Extension 进入的内容最终都复用同一个 composer、media preparation、SQLite/outbox 和 sync pipeline。Share Extension 不写主 App SQLite，也不调用 server，不做视频压缩或 AI summary。

### 2.2.2 AI Summary 决策

AI summary 是语音/视频之上的 iPhone-direct generated metadata，不是评论者或公开反馈。主时间线只在 audio/video media 已经有 ready summary 时显示 `Summary ready`；没有 ready summary、仍在处理、失败或 provider 未配置时，不在时间线显示 Summary 占位、transcript 或失败文案。

iOS 点击 `Summary ready` 入口后打开底部 sheet，只显示 ready AI 摘要内容；原始 transcript 不内联展示，而是作为底部低频 `Original Text` 动作打开独立 sheet。新生成路径由 iPhone 持有：audio/video 先得到 private transcript，再由用户配置的 text analysis provider 生成结构化 summary/title/tags；API key 只保存在 iPhone Keychain。provider profile 可多条配置并排序，自动 fallback 只处理 timeout、network、429、5xx 或 temporarily unavailable 这类 transient failure；401、invalid key、model not found、余额/权限类错误会标记 `needs_attention`，不无限重试。provider 返回了可连接但无法落库的 artifact response 时，错误归类为 artifact-generation failure：当前 summary 可以失败或继续尝试下一个 provider，但这个状态不会把已配置 profile 标记成 `needs_attention`、不会进入 cooldown，也不会让 Settings 显示成需要重新配置；旧版本遗留的这类 `unsupportedResponse` fallback record 会在设置读取时清理。Text provider `Test Connection` 只验证 text-analysis 请求路径，不代表 transcription 阶段已经成功；Advanced transcription 的 `OpenAI-compatible Endpoint` `Test Connection` 使用当前表单值调用 `/v1/models` 且不上传音频，成功后保存该 endpoint draft。真实 audio summary 若在转录阶段失败，不会进入 provider 调用。生成结果可以复制、重新生成或删除；删除只隐藏/软删除 generated metadata，不影响 media 或 comments，也不会把 summary 正文写入 post。

独立 `transcription-gateway` 的边界是 transcription-only helper。默认监听 `127.0.0.1:3322`，要求 `Authorization: Bearer <token>`，`GET /health` 返回 service/model/status，`GET /v1/models` 返回当前默认模型，`POST /v1/audio/transcriptions` 接受 OpenAI-compatible multipart 字段 `file`、`model`、可选 `language`、`response_format=json`，返回 `{ text, language, segments, model, provider }`。服务内部复用 `server/.venv/bin/python`、`server/scripts/local-transcribe.py` 和 `mlx_whisper`，默认模型 `mlx-community/whisper-large-v3-turbo`，并把并发限制为 1，避免本机长音频并发转写造成热量和内存压力。Cloudflare Tunnel、Tailscale 或 LAN 只负责把这个小服务安全传到 iPhone，不改变它不是 sync/server AI job 的事实。

唯一的 post-text 写回例外是新 audio 的 AI title auto-insert。iOS 在收到首次 ready audio summary 后，如果 `documentTitle` 有效、长度不超过 40 个字符、media 和 summary 都晚于本机 feature cutoff、当前 post 第一条非空行不是 `# ` 或 `## `，就把 `## <documentTitle>` 插入 `post.text` 顶部，并写入 `insert_ai_title` outbox operation。这个 operation payload 只包含 `summaryId`、`mediaId` 和 `insertedAt`，不包含标题正文；server 重新从自己的 ready summary 取 `documentTitle`，验证 audio/media/post 关系后发出带 `updateSource: "ai_title"` 的 `post_updated`。iOS 应用这类 `post_updated` 时不更新 `localEditedAt`，因此详情页不显示用户 `Edited` 标记。Settings > Feature Modules > `AI Title Auto-Insert` 只控制未来自动插入，不删除已经写入的标题。

摘要输出采用结构化 JSON。`media-summary-v4` 的主要渲染字段是 `documentTitle`、`oneLiner` 和 `documentBlocks`，iOS 用 native SwiftUI 渲染成标题、一句话总结、折叠详情、列表和无文字标签的建议 callout；`overview`、`keyPoints`、`sections` 只作为旧客户端兼容字段保留。iOS 对 provider 返回做容错解析：`documentBlocks` 中的 `level`、`text`、`items` 可以缺省，不应因为非关键字段缺失把整次 summary 标成 failed。iOS prompt 明确要求 provider 宁可更完整也不要漏掉 source 中的具体事实、问题、决策、工具、时间地点、next action 和 tradeoff；如果 transcript 为空、不可靠、矛盾或明显和用户预期不相关，summary 必须说明不确定性，不能编造自信结论。Summary sheet 会显示实际生成来源和模型，例如 `Generated by DeepSeek · deepseek-v4-flash`，并在摘要末尾用低权重 metadata 显示 provider 返回的 token usage；Timeline row 仍只显示轻量 `Summary ready`，不增加来源文字或 token 细节。v4 继承短标题要求：可识别的非空语音/转录摘要应返回 40 个字符以内的 `documentTitle`，且标题/摘要/tag 语言必须跟随 AI Language 或 source-dominant language。iOS 会把 active topic tag 词表传给 summary/tag prompt，要求优先复用已有 canonical topic；落库前也会按 exact/alias/明显包含关系复用旧 topic，避免 `HTTPS 中间人攻击` 与 `中间人攻击` 这类近义窄化标签继续分裂。iOS 本机记录 `promptVersion`、实际 provider/model、输入 transcript 长度、provider token usage、duration、错误码和 timestamps；处理状态区分 `transcribing` 和 `summarizing`，便于排查卡住环节。日志和导出只记录 id、状态、provider/model、错误码、输入长度和 usage metadata，不记录 transcript 正文、summary 正文或 audio body。已同步 AI summary generated metadata 参与 iPhone 本地搜索，但不会直接展开在 timeline row 内。

### 2.2.3 Smart Tags 决策

Smart Tags 是 moment 的一层轻量组织 metadata，不是公开话题系统。当前产品主路径改为 AI 自动 Topic + 固定 Area 归纳：

- Topic 描述具体内容，例如 `大语言模型`、`面试`、`康复训练`，支持动态新增、alias、merge 和 archive。
- Area 是少量固定系统方向，用来归纳大量 topic：`技术`、`产品与设计`、`学习与知识`、`工作事务`、`生活记录`、`健康与运动`、`情绪与关系`。Area 不是用户自由创建的 tag，也不暴露 `未分类` 作为普通分类。
- 旧 `primary` tag 和 assignment 保留为数据兼容层，不进入普通 Composer、Timeline Filter、Detail tag editor 或 Settings > Tags 主流程；新内容和新 AI 标签不再生成 primary。
- 标签词表和 moment 关联分离：`tags` / `tag_aliases` / `post_tags` 在 server 侧持久化，iOS 对应 `local_tags` / `local_tag_aliases` / `local_post_tags`；topic tag 可带可选 `areaId`。
- 关联记录保存 `role`、`source`、`confidence`、`aiSummaryId`，使 AI 标签和手动标签都能作为普通标签同步和恢复。
- iOS 应用 `post_tag_updated` 时优先按 assignment `id` 更新本地 `local_post_tags`。服务端 `merge_tag` 可能把同一个 assignment 从 source topic 移到 target topic，如果本地已有目标 topic 关联，iOS 先清理冲突行再写入服务端指定的 assignment，避免 SQLite 唯一约束错误阻断 cursor。
- `Post.aiTagProcessedAt` 记录首次 AI 标签处理；`Post.tagsUserEditedAt` 记录用户完整编辑过标签，用于阻止后续 AI 自动覆盖。

UI 边界：

- Composer 不再出现 tag picker；发布主路径只负责 capture。Topic 可由 AI 自动应用，也可在 Detail 的标签编辑器中手动调整。
- Timeline 不再显示 primary chip；主题标签不在主时间线常驻展示，避免每条 moment 变成一排 chips。成功态 `synced` badge 从 timeline 移除，只保留异常同步状态。
- Detail 在 `Show Tags in Timeline` 打开时只读显示 topic tags，并提供单条 topic 编辑入口；tag badge 不做省略号截断，长标签在可用宽度内换行，normal read mode 不显示 `Manual` / `AI` 来源信息。关闭后 Detail 不露出标签展示或编辑操作。
- Settings > Tags 根页按 Areas 分组，每个 Area 进入后管理该 Area 下的 topics，支持搜索、新增、重命名、归档/恢复、alias、merge 和移动 Area。Cleanup Suggestions 只展示可解释建议，merge/reclassify 必须用户确认后才执行。Archived 和旧 Primary 数据放在低频 Legacy/Advanced 区。
- Settings 顶层只保留 `Appearance` 入口；二级页提供 `System`、`Light`、`Dark` 本机外观偏好，通过 SwiftUI `preferredColorScheme` 即时覆盖 Moments App 外观；该偏好不进入 sync，也不尝试修改 iOS 设备级系统外观。
- Settings 顶层只保留 `Language` 入口；二级页只提供 App Language。AI Language 迁入 `AI & Analysis`，只影响之后生成或重新生成的 summary/title/review，不改变 App UI 语言。
- Mac Admin 只展示诊断，不作为标签内容管理入口。

AI 边界：

- 只有新 audio moment 在首次 ready AI summary 时自动应用标签。
- AI 输出在 `media-summary-v4` 结构化结果里带 `suggestedTags: { area, topics }`，不再要求或应用 primary。短音频或短 transcript 会被保守裁剪为优先 1 个 topic，只有额外 topic 代表明显不同主题时才保留；长内容最多 5 个 topic。
- 生成时会把 active topic tag/alias 词表作为组织上下文传给 provider，provider 应优先返回已有 canonical topic name；iOS/server 应用标签时也会先匹配现有 topic、alias、去标点 compact 和明显包含关系，再决定是否创建新 topic。新 topic 必须带固定 `areaId`；provider 缺失、返回旧 `uncategorized` 或未知 area 时，客户端/服务端会按 topic 名称推断到固定 Area，无法识别时保守归入 `生活记录`。
- 如果用户在单条标签编辑器中编辑过完整标签，后续 AI 不再自动覆盖该 moment 的标签。
- Summary regenerate 不重新生成或覆盖标签；历史 audio 不做回填；video/image/text 不做 AI 自动标签。

### 2.2.4 语言偏好与本地化边界

iOS 第一版语言系统使用 App 内本地化层，而不是把语言作为 server-side profile 同步。`AppLocalization.swift` 定义 `AppLanguageMode`、`AILanguageMode`、`appLanguage` SwiftUI environment 和 `L10n.t(...)` 字典。`AppSettings` 把 App Language 和 AI Language 存在本机 `UserDefaults`；已有私人安装在没有显式语言偏好时默认 English，新安装默认 System。Settings 顶层的 `Language` row 只显示当前 App Language 摘要，具体 UI 语言选项进入二级页。

App Language 只影响 iOS 主 App 的 user-visible chrome：Timeline、Calendar、Composer、Detail/Edit、Settings、Tags、Summary sheet、Search/Filter、评论 UI、弹窗和时间/日期标签。它不翻译用户正文、评论、自定义标签、主题标签、alias、历史内容、AI summary 正文、API 字段或 server/admin 文案。新增 iOS 可见文案应走 `L10n.t(...)`，避免中文模式出现新的英文漏项。

旧默认主标签仍是一组 synced tag identity，用于历史数据、导入导出和旧客户端兼容；server 仍按默认 tag ID 保护 canonical 中文名称、`isDefault` 和 `aiUsableAsPrimary`。新 iOS 普通 UI 不再展示或筛选 primary，AI 也不再应用 primary。自定义 topic tags、Areas 和 aliases 不自动翻译；Area 标题是系统固定文案，会随 App Language 显示。

AI Language 与 App Language 分离，并在 `Settings > AI & Analysis` 中设置。iOS 把 `AI Language` 作为本机 provider request 的 prompt 指令，用于新生成或重新生成的 summary/title/review。`Auto` 跟随 transcript/audio 的主导语言；`zh` 或 `en` 只影响 generated content，不改变 iOS UI，也不作为跨设备 synced preference。本机 Speech transcription 的初始 locale 也会参考 AI Language 和 App Language，并把中文/英文中的成功 locale 保存在本机；显式切换 App Language 或 AI Language 会清掉该学习值。

### 2.2.5 AI Periodic Reviews 决策

AI Periodic Reviews 是通用回看系统。第一版是 `Weekly Review`，但 schema、API 和服务层不命名为 `weekly_reviews`，而是使用 `reviews.kind`、`rangeMode`、`rangeStart` 和 `rangeEnd`，为后续 monthly/custom review 复用同一基础。

Weekly Review 放在 Calendar 的 `Reviews` 入口下，而不是 Timeline。它是 generated review artifact，不默认成为 moment；AI & Analysis 关闭且本机没有历史 review 时，Calendar 不显示 `Reviews` 入口，已有历史 review 时仍显示以保护回看连续性。用户可以通过显式 `Publish as Moment` 把 ready review 转成 moment，也可以打开 `Publish Weekly Review` 让本机 scheduled Weekly Review 生成完成后自动发布。Settings > AI & Analysis 提供 `Auto-generate Weekly Review` 和 `Publish Weekly Review`，两个默认关闭，并且它们是本机 iPhone-direct preference，不再拉取或写回 Mac/server `review_settings`；`Publish Weekly Review` 依附于 `Auto-generate Weekly Review`，不能作为独立 scheduled action 开启。新架构下 Review generation 使用 iPhone-direct text analysis provider；Mac server 端旧 review routes 和 historical artifacts 保留兼容，但不再是默认 AI 生产者。发布出的 review post 使用 `review-<reviewId>` 作为 id；旧 `Review/复盘` primary 只作为 legacy compatibility metadata 保留，iOS Timeline 对 `review-...` moment 显示独立 `AI Review` badge，不依赖 `Show Tags in Timeline`；Timeline 只展示标题和第一段核心预览，`N moments · M comments`、range、keywords、provider/model 等 metadata 只在 Moment Detail 中低权重展示。Moment Detail 会把已发布 review 的 markdown 解析成专门的 AI Review document，按 `##` section 分隔，section 默认展开但允许折叠。新生成 prompt version `weekly-review-v3` 更强调只依据输入中的文本、标签、媒体 metadata、评论、收藏和 rhythm 信号，不凭空推断完成度、效率、情绪、健康或意图。

旧 Mac server review API 为历史数据、兼容客户端和迁移期保留；新客户端不应把 Weekly Review 的生成能力解释为 Mac server 功能。Mac/server 的 `ReviewScheduler` 默认不启动，只有 operator 显式设置 legacy opt-in 环境变量时才会恢复旧自动生成行为。未来如果 Mac 重新作为 optional local worker，需要以显式 worker profile 接回 provider queue，而不是恢复上传后自动生成或默认 scheduled review。

Review 输入由 iPhone 本地构建：

- 时间范围内未删除的 post text。
- 未删除 comments。
- ready 且未删除的 audio/video AI summary generated metadata。
- tags、favorite、media kind、occurredAt。
- 每日/时段节奏统计。

为了避免长范围自定义回顾把过多私密内容一次性送到外部 provider，Review generation 仍需要输入预算：生成范围最多 35 天，provider 输入最多 240 条 moments。超过范围的生成应保存为 failed review，错误码为 `review_input_too_large`。Weekly Review 复用同一套 iPhone provider router；ready review 会保存实际 provider/model，iOS Review header 会显示 `Generated by <provider> · <model>`。

图片第一版只作为 image moment/media kind 信号，不做 OCR 或 vision analysis。普通日志和 review memory 不记录 post body、comment body、transcript body 或 summary body。

Review prompt 强制 whole-period reading：主题、关键词、状态回应、进展和节奏不绑定 per-claim evidence。只有 `notableMoments` / `Worth Revisiting` 可以携带 moment IDs 作为低权重 review anchors。iOS 点击 anchor 时在当前 Review 界面内打开 moment preview/detail sheet，不跳 Timeline，也不设置 Timeline day filter。

Review feedback 现在是“当前可切换状态”，不是一次性日志。五个标准反馈 `useful`、`too_much_inference`、`too_dry`、`missed_point`、`hide_theme` 允许在同一条 review 上同时选多个，再次点击会撤销对应类型，降低误触后遗留的影响。detail 底部还有一个自由输入框，作为 `custom_guidance` 保存，代表用户对下一次生成的强指令。server 会把这些状态写入 `review_feedback`，再重建粗粒度 `review_memory`，其中标准反馈作为 soft steering，自由输入作为 `highPriorityGuidance` 高权重提示。第一版 memory 仍不保存私人内容正文之外的历史 post/comment/transcript，只保留这些显式反馈偏好和最近上下文。下一次生成 review 时，provider prompt 会把这些 memory 当作约束读取：例如 `too_much_inference` 会压低解释性跳跃，`too_dry` 会要求更有连接感，`missed_point` 会优先抓主轴，`hide_theme` 会避免重复把同一主题放到中心，而自由输入 guidance 会被当成下一次 draft 的最高优先级风格调整。

Weekly Review 的 `keywords` 也收敛为轻量信号：生成目标是 3 到 5 个 concise keywords，detail 中只做一行轻展示，不再用大面积标签卡片抢占页面。

为了避免 SwiftUI 把长正文拆成很多独立 `Text` 节点后难以长按选择，Weekly Review detail 的 `bodyMarkdown` 现在走只读原生 `UITextView` 渲染，保留有限 Markdown 子集的视觉层次，同时允许连续选中复制。detail 右上角 menu 另外提供显式 `Copy text`，用于在 iPhone 上快速复制整篇 review 文本；`Keywords`、`Worth Revisiting` note 和 `Uncertainty` bullets 也开启文字选择。

## 2.3 Legacy Mac Admin 迁移与最小运维面

Mac Admin 定位为 legacy 低频本地运维台，不替代 iPhone 的内容编辑、回看、设置、iCloud 或日常诊断入口。当前顶层 tab 只保留 `Archive / Overview`：`Archive` 负责 restic backup/restore、promote preparation、export/import 和 repository 状态；`Overview` 只保留 runtime truth、maintenance jobs、server logs 和 device emergency。

后续设置、监控、诊断和安全修复动作默认优先迁移到 iOS Settings / Diagnostics。Mac Admin 保留为低频 Mac 本地运维面：Archive backup/restore、staged promote、export/import artifact、server logs、文件系统权限、LaunchAgent/进程状态和必须靠 Mac 文件路径完成的恢复操作。短期如果某个能力只能先放在 Admin，需要在 `docs/HANDOFF.md` 标明它是否属于后续迁移到 iOS 的候选。Admin 最小保留信息和迁移顺序记录在 `docs/ADMIN-MIGRATION.md`。

Posts 不再作为 Mac Admin 顶层内容管理页面。底层 Admin posts API 和旧 React 组件短期保留一个 checkpoint，作为紧急排障余量；后续确认不需要浏览器侧内容证据后，再单独删除或改成 hidden/debug-only。若保留 debug 能力，只允许按 ID 定位少量 post、查看 media path/status/checksum 等恢复证据、或清理明确测试设备产生的数据；不增加 Admin 内编辑、播放、批量内容整理或日常搜索体验。

历史 Posts 页面采用列表 + 右侧详情抽屉。列表用于快速扫描文字摘要、发生时间、媒体数量、创建设备、更新设备、删除状态和基础同步状态；详情抽屉用于查看完整正文、图片网格或媒体诊断、媒体状态、大小、checksum、`serverVersion`、创建/更新设备和删除时间。图片在详情抽屉内显示缩略图，点击后以全屏 lightbox 查看压缩展示图；语音/视频不在 Admin 内播放。该页面不再从顶层导航进入。

后台单条删除只放在详情抽屉内，必须二次确认。单条删除采用软删除：服务端设置 `Post.deletedAt`，将该 post 下未删除媒体和 comments 标记为 deleted，并写入 `post_deleted` server change；iPhone 下次同步后隐藏本地缓存。第一版不做软删除恢复。

设备行提供 `Clean posts` 危险操作，用于永久清理某设备创建的测试数据。该操作只匹配 `createdByDeviceId`，不匹配仅被该设备更新过的 posts。执行前必须展示候选数量和设备名，并要求输入设备名确认。执行后不自动撤销设备。

永久清理会删除匹配 posts 的数据库记录和媒体文件，Posts 管理里不再显示这些记录。为保持 iPhone 与 Mac 一致，服务端在删除数据库记录前为每个 post 写入最小 `post_deleted` server change；下次 iPhone 同步时隐藏本地缓存。后台日志记录清理操作的设备、数量和操作者。

设备绑定使用 `deviceKey` 防止重复注册。同一用户、同一平台、同一 `deviceKey` 只能对应一条 `Device`：iOS 使用 `UIDevice.identifierForVendor`，Mac Admin 浏览器使用本地 `localStorage` UUID。重复登录会更新原设备的 token、名称和 lastSeenAt，而不是插入新设备。为了兼容旧客户端，如果带 `deviceKey` 的登录找不到完全匹配记录，服务端会优先复用同名、同平台、未绑定 `deviceKey` 的旧设备记录。

## 2.4 Settings Storage 与导出决策

iOS Settings 首页按能力组织，而不是按 Mac server 或手动同步组织。根页面使用 native grouped Settings 风格，包含 `Data Storage`、`AI & Analysis`、`Organization` 和 `App Preferences`。`Data Storage` 下只有 `This iPhone`、`iCloud`、`Storage & Export`：`This iPhone` 是不可点击 local 状态；`iCloud` 只展示用户能直接理解的账号状态、默认关闭的 iCloud Sync、Sync Now 和最近同步状态；CloudKit container、smoke test 和 default-zone probe 不进入普通用户界面；`Storage & Export` 承担本机占用、完整本机 archive export 和空资料库 local archive import。Mac/server 配置、手动 legacy sync 和 Mac runtime diagnostics 不再作为日常 Settings 产品路径；已有 runtime/sync 兼容代码可以保留，但 UI 不应把 Mac 解释成默认依赖。

本机统计由 iOS 直接扫描本地文件和 SQLite 状态：

- 总占用。
- SQLite 数据库、`-wal`、`-shm`。
- 媒体缓存目录。
- 可重新下载的完整语音/视频缓存大小。
- 待同步操作数。
- 待上传 media 数。
- 失败上传数。

本机 archive export 是 migration/restore-first 格式，输出 zip 包：

- `manifest.json`：版本、导出时间、计数、隐私属性、缺失本机 media 清单。
- `data/archive.json`：moment、comment、tag、check-in、AI summary、weekly review 等结构化数据。
- `preview/moments.md`：面向人类浏览的 Markdown 预览。
- `media/`：导出时本机实际存在的 media files。
- `README.md`：格式和隐私说明。

导出包不会包含 credentials、API keys、provider configs 或 private transcript text；音视频 transcript 只以长度、状态和时间等 metadata 形式出现。导出包目前不加密，因此 UI 必须在导出前提示它可能包含私人正文、评论、AI summaries、reviews、check-ins 和 media。

iPhone local archive import 是当前 zip 格式的最小恢复闭环，只允许导入到空的本机资料库。导入会先读取 `manifest.json` 和 `data/archive.json` 做 preview，再在用户确认后把 posts、media metadata、comments、tags、tag aliases、check-ins、AI summaries 和 weekly reviews 写入本机 SQLite，并把 zip 内存在的 media files 复制到 App Support media 目录。导入前必须检查本机没有 posts、media、comments、自定义 tags、tag aliases、post-tag assignments、check-ins、AI summaries 或 outbox operations；默认 seed tags 不阻塞导入。失败时已复制的 media files 会清理。

Import 不做 merge、不覆盖已有本机资料库、不创建 sync/outbox/device runtime state、不导入 API keys/provider credentials/private transcript text，也不改变 archive package wire format 或 SQLite schema。跨设备同步收敛、非空资料库导入、覆盖式 restore 和新手机一键迁移仍属于后续单独设计。

Mac server 的 `GET /api/v1/admin/status`、maintenance state、Archive repository 和 snapshots 仍可作为低频运维/兼容能力存在，但不应重新出现在普通 Settings 根路径。后续如果需要恢复 Mac 作为 optional local worker，应作为显式 worker/profile 设计，而不是恢复 Mac-default Settings 信息架构。

## 3. 技术栈

### iOS App

- Swift。
- SwiftUI。
- 系统 SQLite3。当前先用轻量自写访问层减少外部依赖，后续如果本地查询复杂度上升，可以再替换为 GRDB。
- 本地文件目录保存压缩图、待上传原图副本、视频、视频 poster 和语音文件。
- 使用系统相册/相机能力。
- 使用 Share Extension + App Group import queue 接收外部 App 分享来的图片、视频、音频、URL 和文本；主 App 再转换为现有 composer draft。
- 本地 outbox 队列驱动同步。
- 失败同步或上传任务使用 5s、20s、60s、120s、300s 的延迟自动重试。
- 发布草稿保存文字、发生时间和已准备媒体。
- 远端同步来的压缩图和视频 poster 会下载到本地缓存后展示；完整语音/视频按播放需求下载。
- Settings 顶层按能力组织：`Data Storage`、`AI & Analysis`、`Organization`、`App Preferences`。`Storage & Export` 只展示本机 storage、完整本机 archive export 和空资料库 archive import；Mac/server diagnostics 不再是普通 Settings 产品路径。

### Legacy Mac Server

- Node.js。
- TypeScript。
- Fastify。
- Prisma。
- SQLite。
- 本地文件存储。
- launchd 登录后自动启动。
- `/api/v1/admin/status` 返回服务状态、计数、存储诊断、Sync Health、AI summary 诊断和 AI token usage。

### Legacy Mac Admin UI

- React。
- Vite。
- 构建后由 Fastify 静态托管。

### Shared Contract

- `shared/openapi.yaml` 描述 API 字段、认证和响应结构。
- `shared/sync-protocol.md` 描述同步协议语义、幂等、冲突和 cursor 规则。

## 4. Legacy Mac 数据目录

默认数据目录：

```text
~/Library/Application Support/PrivateMoments/
  manifest.json
  app.sqlite
  media/
    compressed/
    originals/
    thumbnails/
    temp/
  exports/
  archive/
    archive-config.json
    staging/
    restores/
    restic-cache/
    pending-promote.json
  logs/
```

### manifest.json

`manifest.json` 用于记录数据目录版本，支持未来迁移和备份校验。

草案：

```json
{
  "app": "PrivateMoments",
  "dataVersion": 1,
  "schemaVersion": 16,
  "createdAt": "2026-04-28T00:00:00.000Z",
  "mediaLayoutVersion": 1
}
```

## 5. 服务端数据模型

服务端使用 Prisma + SQLite。媒体二进制文件不存入 SQLite，数据库只保存元数据和文件路径。

### User

MVP 只有单用户，但保留用户表有利于认证和未来扩展。

字段草案：

```text
user
  id
  passwordHash
  createdAt
  updatedAt
```

### Device

记录已授权设备和撤销状态。

```text
device
  id
  userId
  name
  deviceKey
  tokenHash
  platform
  lastSeenAt
  revokedAt
  createdAt
  updatedAt
```

`device token` 明文只在登录时返回给 iOS。服务端保存 `tokenHash`。

`deviceKey` 用于复用同一个物理设备或同一个浏览器安装，避免重复登录时产生大量同名设备。iOS 使用 `UIDevice.identifierForVendor` 派生稳定 key；Mac Admin 浏览器使用 `localStorage` UUID。

### Post

```text
post
  id
  text
  isFavorite
  occurredAt
  createdAt
  updatedAt
  deletedAt
  clientCreatedAt
  clientUpdatedAt
  serverVersion
  createdByDeviceId
  updatedByDeviceId
```

说明：

- `occurredAt` 是用户可手动修改的发生时间，用于时间线和月份归档。
- `isFavorite` 是收藏状态，独立于编辑流同步。
- `createdAt`/`updatedAt` 是服务端记录时间。
- `deletedAt` 为软删除时间。
- `serverVersion` 用于增量同步。

### Comment

```text
comment
  id
  postId
  text
  createdAt
  updatedAt
  deletedAt
  clientCreatedAt
  clientUpdatedAt
  serverVersion
  createdByDeviceId
  updatedByDeviceId
```

评论是独立 local-first entity，但生命周期从属于 `post`。服务端拒绝给不存在或已删除 post 创建评论。删除父 post 时，服务端软删除其下未删除评论，但只发出 `post_deleted` server change，不额外发逐条 `comment_deleted`。

### Media

```text
media
  id
  postId
  kind
  status
  compressedPath
  originalPath
  thumbnailPath
  originalPreserved
  mimeType
  durationSeconds
  transcriptionText
  width
  height
  compressedSizeBytes
  originalSizeBytes
  checksum
  sortOrder
  createdAt
  updatedAt
  deletedAt
```

`kind` 支持 `image`、`video`、`audio` 和 `document`。当前 `document` 首版只支持 PDF，使用 `application/pdf` 和 `compressed` variant。`transcriptionText` 是 schema version 6 的历史兼容字段；新 iOS 的 iPhone-direct AI path 会在本机生成 private transcript metadata，但不再通过 media upload metadata 把 transcript 写入 Mac server 这一路历史字段。

`status` 可选：

```text
pending
uploaded
failed
deleted
```

### AISummary

AI 摘要是 media 的 generated metadata。每个 media 第一版最多一个当前 summary record，通过 `mediaId` 唯一约束定位。

```text
ai_summaries
  id
  postId
  mediaId
  status
  format
  language
  overview
  keyPointsJson
  sectionsJson
  summaryText
  documentTitle
  oneLiner
  documentBlocksJson
  inputTranscriptHash
  inputTranscriptLength
  inputDurationSeconds
  promptVersion
  provider
  model
  errorCode
  errorMessage
  requestedByDeviceId
  createdAt
  updatedAt
  deletedAt
```

`status` 可选：

```text
transcribing
summarizing
ready
failed
deleted
```

服务端通过 `ai_summary_updated` 和 `ai_summary_deleted` server changes 同步结果。失败状态只影响 summary record，不改变 post/media/comment 的同步状态。AI media summary job 全局串行执行，避免断网恢复或批量补传后同时启动多个本地 `mlx-whisper` 进程。`/api/v1/admin/status` 暴露轻量 AI summary diagnostics，Settings > Storage & Diagnostics 可查看 `transcribing`、`summarizing`、`ready`、`failed` 计数和非 ready 项的错误码，不暴露 transcript 或 summary 正文。

### AIUsageEvent

`ai_usage_events` 是 privacy-safe 的 AI 使用计量账本。它记录每次外部 AI provider 调用的 feature、subject、provider/model、promptVersion、请求状态、duration、token usage 和本地估算值；不记录 prompt、transcript、summary body、review input JSON 或 provider request/response 正文。provider 返回 usage 时优先使用真实 `inputTokens`、`outputTokens`、`totalTokens` 和 `cachedInputTokens`；没有 usage 时只用字符数估算，并在 Admin/iOS 诊断里计入 estimated requests。

```text
ai_usage_events
  id
  feature
  subjectType
  subjectId
  provider
  model
  promptVersion
  status
  inputChars
  outputChars
  inputTokens
  outputTokens
  totalTokens
  cachedInputTokens
  estimatedInputTokens
  estimatedOutputTokens
  estimatedTotalTokens
  durationMs
  errorCode
  createdAt
```

### SyncOperation

服务端记录设备提交过的操作，用于幂等和排查。

```text
sync_operation
  id
  opId
  deviceId
  type
  entityType
  entityId
  payloadJson
  receivedAt
  appliedAt
  rejectedAt
  rejectionReason
```

`opId` 由客户端生成，同一设备内唯一。服务端对 `(deviceId, opId)` 建唯一索引，避免重复创建。

### ServerChange

服务端变更日志，用于 sync cursor 拉取增量。

```text
server_change
  version
  entityType
  entityId
  changeType
  payloadJson
  createdAt
```

`version` 是单调递增的服务端序号。客户端的 `syncCursor` 指向最后已处理的 `version`。

### MaintenanceJob

维护任务用于 backup、restore、check、promote preparation、export、import 和 Sync Health refresh。它是浏览器刷新安全的状态记录，不是私人内容日志。

```text
maintenance_job
  id
  type
  status
  stage
  progress
  metadataJson
  artifactPath
  errorCode
  errorMessage
  createdAt
  startedAt
  finishedAt
```

`type` 当前包括：

```text
backup_create
backup_check
backup_restore
backup_promote
export_create
import_restore
sync_health_refresh
```

`status` 当前包括：

```text
queued
running
succeeded
failed
cancelled
```

server 启动时会把遗留 `running` jobs 标记为 `failed/server_restarted`，避免旧状态永久卡住。v0.1 使用 process-local serial runner，保证同一时间只执行一个 maintenance job。job metadata 只保存路径、计数、状态和错误码等安全信息，不保存 post/comment/transcript/summary 正文或媒体内容。

### Maintenance Mode

Maintenance mode 是 server 进程内状态，由 restore/promote preparation 进入和退出。它用于暂停 write-heavy routes，避免恢复/切换准备期间继续写入 archive：

- `/api/v1/sync`
- `/api/v1/media/upload`
- `/api/v1/ai/media-summary`
- `/api/v1/ai/media-summary/:summaryId`
- Admin soft delete / clean posts 等 destructive write

Health、Admin status、maintenance job list/detail 和 archive read state 保持可读。

## 5.1 Archive Backup/Restore Design

Archive backup/restore 面向自用灾难恢复，由 Mac server/Admin UI 管理，CLI/restic 只作为调试底层。

### Repository Config

Admin `Archive` tab 通过 `/api/v1/admin/archive/repository` 保存 repository path。server 在数据目录内保存：

```text
archive/archive-config.json
```

repository path 可以是本机目录，也可以是用户明确选择的 iCloud Drive 目录。server 不做云上传集成，只把 iCloud Drive 当作普通文件夹。

项目会在 repository path 下创建或复用：

```text
.private-moments-restic-key
```

这个文件作为 restic password file。用户不需要记额外密码，但谁同时拥有 repository 和 key 文件，谁就可以恢复 archive。

### Backup Source

`backup_create` job 会先构造受控 snapshot source：

```text
archive/staging/<job>/snapshot/
  app.sqlite
  manifest.json
  media/
  backup-manifest.json
```

SQLite 优先通过 `sqlite3 .backup` 生成一致副本，失败时才退回文件复制。snapshot 写入 restic 后，staging 目录会被清理。备份不包含依赖目录、build output、Python venv、运行时 temp 文件或普通日志。

### Restore

`backup_restore` job 使用 restic 把指定 snapshot 恢复到：

```text
archive/restores/<timestamp>-<snapshot>[-label]/
```

server 会扫描恢复结果中的 data directory，并验证：

- `app.sqlite` 存在且 SQLite 可读。
- `manifest.json` 存在。
- `media/` 存在。
- 未删除 media 的 `compressed_path` / `original_path` / `thumbnail_path` 都仍位于恢复目录内并且文件存在。

验证结果写入 job metadata，恢复目录写入 `artifactPath`。

### Promote Preparation

当前 v0.1 不在运行中直接替换 live SQLite database。`backup_promote` 是 promote preparation：

1. 校验确认短语必须是 `PROMOTE <restored-folder-name>`。
2. 进入 maintenance mode。
3. 再次验证 restored data directory。
4. 创建 `pre-promote` backup。
5. 写入 `archive/pending-promote.json`。
6. 退出 maintenance mode。

`pending-promote.json` 包含恢复目录、当前目录、pre-promote backup metadata，以及应写入环境的：

```text
PRIVATE_MOMENTS_DATA_DIR=<restored-data-dir>
DATABASE_URL=file:<restored-data-dir>/app.sqlite
```

Operator 需要停止 server，按该文件切换 env，再重启 server。这样避免在 Prisma 持有 SQLite 连接时热替换数据库。

## 5.2 Export/Import Design

Mac Admin 的 Export/import 是迁移和恢复辅助路径，不替代 restic backup。iPhone local export/import 是同一方向的轻量本机恢复演练包：当前 iPhone build 可以把本机 zip 导入空资料库，但不实现非空库 merge 或覆盖恢复。

`export_create` job 支持全量或 occurred date range。导出目录写入：

```text
exports/private-moments-export-<timestamp>/
  manifest.json
  archive.json
  preview.md
  media/
```

`manifest.json` 记录包类型、包版本、server/schema version、导出范围和计数。`archive.json` 是权威迁移数据，包含 posts、media metadata、comments、tags、tag aliases、post tag assignments 和 AI summaries。`preview.md` 只用于快速阅读，不作为 import source of truth。导出完成后 server 用 tar 生成：

```text
exports/private-moments-export-<timestamp>.tar.gz
```

`import_restore` job 只导入到新的 staged data directory：

```text
archive/imports/<timestamp>-<label>/data
```

导入流程会先创建新 data dir 和 SQLite DB，跑 Prisma migrations，再导入内容数据。导入会保留 post/comment/media/tag/summary IDs 和 timestamps，恢复 generated AI/tag metadata，复制媒体 payload，并重建 `server_changes`，让新设备可以从 cursor `0` 拉取内容。导入明确排除 users、devices、sync operations 和 maintenance jobs，因此不会带回旧 token、session、device cursor 或旧维护任务。

导入后会验证：

- imported database 可读。
- `devices` 为空。
- `server_changes` 已重建。
- 未删除 media 引用的文件存在且仍位于 staged data dir 内。

如果要把 imported archive 变成当前运行 archive，仍然走 promote/restart 安全流程，而不是 import job 自动替换 live database。

## 6. iOS 本地数据模型

iOS 使用 SQLite，模型与服务端接近，但增加本地状态字段。

### local_post

```text
local_post
  id
  text
  isFavorite
  occurredAt
  localCreatedAt
  localUpdatedAt
  serverVersion
  syncStatus
  deletedAt
```

`syncStatus` 可选：

```text
draft
pending
partial
synced
failed
deleted_pending
```

### local_media

```text
local_media
  id
  postId
  kind
  localCompressedPath
  localOriginalStagingPath
  localThumbnailPath
  remoteCompressedPath
  remoteOriginalPath
  remoteThumbnailPath
  originalPreserved
  uploadStatus
  mimeType
  durationSeconds
  transcriptionText
  transcriptionStatus
  transcriptionError
  transcriptionUpdatedAt
  sortOrder
  checksum
  createdAt
  updatedAt
```

### local_comment

```text
local_comment
  id
  postId
  text
  localCreatedAt
  localUpdatedAt
  serverVersion
  syncStatus
  deletedAt
```

本地评论随 timeline item 一起读取，只在主时间线展示。`syncStatus` 是 iOS 本地兼容字段，用于支持曾经安装过旧评论 schema 的设备，不作为每条评论的 UI 标识展示。删除未同步的本地新评论时，iOS 会取消对应 pending `create_comment` operation，并只做本地软删除；已提交或已同步评论删除时写入 `delete_comment` outbox operation。

### local_ai_summaries

```text
local_ai_summaries
  id
  postId
  mediaId
  status
  format
  language
  overview
  keyPointsJson
  sectionsJson
  summaryText
  documentTitle
  oneLiner
  documentBlocksJson
  inputTranscriptLength
  inputDurationSeconds
  inputTokenCount
  outputTokenCount
  totalTokenCount
  promptVersion
  provider
  model
  errorCode
  errorMessage
  createdAt
  updatedAt
  deletedAt
```

本地 AI summary 随 timeline item 一起读取。`ready` 状态在 timeline 只显示 `Summary ready`，点开 bottom sheet 才显示完整摘要；没有 ready summary 时不显示 Summary 入口，也不回退显示 transcript。新 summary 优先用 `documentTitle`、`oneLiner` 和 `documentBlocksJson` 渲染；老 summary 继续用 `overview`、`keyPointsJson` 和 `sectionsJson` 兼容显示。`inputTokenCount`、`outputTokenCount`、`totalTokenCount` 保存 provider 返回的 privacy-safe usage metadata，Summary sheet 末尾可低权重展示。新 audio 的 `documentTitle` 可以按上面的 `insert_ai_title` 规则写成 post 顶部标题；summary 正文不写回。`transcribing`、`summarizing`、`failed` 和 `deleted` 状态都不会阻塞普通 sync、media upload、评论或标题插入失败/跳过。

### outbox_operation

```text
outbox_operation
  id
  opId
  type
  entityType
  entityId
  payloadJson
  status
  attemptCount
  lastError
  createdAt
  updatedAt
  sentAt
```

`outbox_operation` 是本地优先架构的核心。UI 更新不等待网络成功，所有用户操作先写本地，再进入 outbox。

### sync_state

```text
sync_state
  key
  value
```

关键值：

```text
deviceId
lastSyncCursor
lastSuccessfulSyncAt
```

## 7. API 设计

所有 API 使用 `/api/v1` 前缀。响应中应包含 `serverVersion` 和 `schemaVersion`，至少在认证、健康检查和同步响应中提供。

### 认证

iOS API 使用 Bearer device token：

```http
Authorization: Bearer <device-token>
```

登录后返回长期 token。token 长期有效，可在后台撤销。高风险操作需要重新验证密码。

### Core Endpoints

```text
GET    /api/v1/health
POST   /api/v1/auth/login
GET    /api/v1/devices
DELETE /api/v1/devices/:deviceId
POST   /api/v1/sync
POST   /api/v1/ai/media-summary
DELETE /api/v1/ai/media-summary/:summaryId
POST   /api/v1/media/upload
POST   /api/v1/media/batch-download
GET    /api/v1/media/:mediaId
GET    /api/v1/timeline
GET    /api/v1/posts/:postId
GET    /api/v1/search?q=...
GET    /api/v1/admin/status
GET    /api/v1/admin/logs
GET    /api/v1/admin/posts
GET    /api/v1/admin/posts/:postId
DELETE /api/v1/admin/posts/:postId
GET    /api/v1/admin/devices/:deviceId/clean-posts/preview
POST   /api/v1/admin/devices/:deviceId/clean-posts
GET    /api/v1/admin/maintenance/state
GET    /api/v1/admin/maintenance/jobs
GET    /api/v1/admin/maintenance/jobs/:jobId
POST   /api/v1/admin/maintenance/jobs/sync-health-refresh
GET    /api/v1/admin/archive/repository
POST   /api/v1/admin/archive/repository
POST   /api/v1/admin/archive/repository/init
POST   /api/v1/admin/archive/schedule
GET    /api/v1/admin/archive/snapshots
POST   /api/v1/admin/archive/jobs/backup
POST   /api/v1/admin/archive/jobs/check
POST   /api/v1/admin/archive/jobs/restore
POST   /api/v1/admin/archive/jobs/promote
POST   /api/v1/admin/archive/jobs/export
POST   /api/v1/admin/archive/jobs/import
```

说明：

- `/api/v1/timeline` 和 `/api/v1/posts/:postId` 主要用于读取和调试。
- 离线创建、删除和未来编辑通过 `/api/v1/sync` 处理。
- 图片、语音和视频文件通过 `/api/v1/media/upload` 上传，避免把大文件塞进 sync JSON；新 iOS 不随 multipart metadata 带 `transcriptionText`。
- AI 摘要由 iPhone-direct AI path 触发；Mac server 上传路径不再自动 enqueue summary job。新摘要使用 `media-summary-v4` document block 模型：`documentTitle`、`oneLiner`、`documentBlocks` 是主要渲染字段，旧 `overview`、`keyPoints`、`sections` 保留作兼容；v4 会把 active topic tag/alias 词表作为上下文，用于优先复用现有 AI topic tag。历史 Mac-generated summaries 继续通过 sync/export/import 兼容显示。
- iOS 拉取远端图片缩略图和视频 poster 时优先使用 `/api/v1/media/batch-download` 获取 base64 JSON，避免真机/Tailscale 场景下多次二进制下载超时。
- Mac Admin 路由复用 Bearer device token，普通内容发布仍然只在 iOS 端进行。
- `/api/v1/admin/status` 同时给 Mac Admin 和 iOS Advanced replication diagnostics 使用；storage 字段包含 `totalBytes`、`databaseBytes`、`mediaBytes`、`logsBytes`、`availableBytes`，`sync.latestServerChangeVersion` 用于和 iPhone `lastSyncCursor` 对比，`sync.pendingOperations`、`sync.rejectedOperations`、`sync.failedMediaUploads`、`sync.aiNonReady` 和 last-sync timestamps 用于 Advanced Sync Health / Sync Doctor，`aiSummaries` 字段包含 summary 状态计数和非 ready 项的安全错误 metadata，`aiUsage` 字段包含 Today、This week、This month、All time 的 AI token usage、请求数、失败数、cached input token 和本月按 feature 聚合，`tags` 字段包含安全的标签计数和 AI/manual assignment 计数。Sync Doctor 不新增 server contract，只把现有本机和 Mac-side Sync Health 信号分类成安全恢复建议。Mac-side `sync.rejectedOperations` 是原始历史计数，Sync Doctor 只有在本机仍有 pending outbox 且最新 rejected timestamp 晚于最近 successful sync 时，才将其解释为当前 `Blocked`；否则该计数只保留在 Sync Health 原始指标中。

## 8. Sync Endpoint

`sync endpoint` 本质上是一个 HTTP API，但语义是设备与服务器对账，而不是对单一资源做 CRUD。

### 请求草案

```json
{
  "deviceId": "device-uuid",
  "lastSyncCursor": 120,
  "localChanges": [
    {
      "opId": "op-uuid-1",
      "type": "create_post",
      "entityType": "post",
      "entityId": "post-uuid",
      "clientCreatedAt": "2026-04-28T10:00:00.000Z",
      "payload": {
        "text": "去了咖啡店",
        "occurredAt": "2026-04-28T09:30:00.000Z",
        "mediaIds": ["media-uuid-1"]
      }
    },
    {
      "opId": "op-uuid-2",
      "type": "delete_post",
      "entityType": "post",
      "entityId": "post-uuid",
      "clientCreatedAt": "2026-04-28T11:00:00.000Z",
      "payload": {
        "deletedAt": "2026-04-28T11:00:00.000Z"
      }
    }
  ]
}
```

### 响应草案

```json
{
  "serverVersion": "0.1.0",
  "schemaVersion": 16,
  "acceptedOps": ["op-uuid-1", "op-uuid-2"],
  "rejectedOps": [],
  "serverChanges": [
    {
      "version": 121,
      "entityType": "post",
      "entityId": "post-uuid",
      "changeType": "post_created",
      "payload": {
        "id": "post-uuid",
        "text": "去了咖啡店",
        "occurredAt": "2026-04-28T09:30:00.000Z",
        "deletedAt": null
      }
    }
  ],
  "nextSyncCursor": 121
}
```

### 同步规则

- 客户端先写本地数据库，再写 outbox。
- App 打开后自动触发同步。
- 切到后台或锁屏后尽量继续传完当前同步任务。
- 每个操作必须有 `opId`。
- 服务端使用 `(deviceId, opId)` 保证幂等。
- `syncCursor` 表示客户端已处理到的服务端 `server_change.version`。
- 同步时客户端上传本地变化，同时拉取 `lastSyncCursor` 之后的服务端变化。
- 多设备冲突使用最后写入胜出。
- 服务端保留操作日志用于排查。
- iOS 只在成功应用全部 `serverChanges` 后推进本地 cursor。
- iOS 兼容带毫秒和不带毫秒的 ISO8601 时间；解析失败会让本轮同步失败，而不是静默跳过变更后推进 cursor。
- `didApplySyncRecoveryV1` 用于 2026-04-29 的一次性恢复：如果本地为空或旧 cursor 可能已经错误推进，启动后会把 cursor 重置为 0 从服务端完整拉取。
- 评论通过 `create_comment` 和 `delete_comment` 同步，对应 server changes 是 `comment_created` 和 `comment_deleted`。iOS 应用评论变更时如果找不到父 post，必须让本轮同步失败，不能推进 cursor。
- `update_media_transcription` / `media_transcription_updated` 保留为旧客户端兼容同步；新 iOS 不再创建本地转写 operation。
- AI 摘要通过独立 endpoint 生成，但结果仍通过 server changes 恢复和多设备同步；对应 server changes 是 `ai_summary_updated` 和 `ai_summary_deleted`。iOS 应用 AI summary 变更时如果找不到父 post 或 media，必须让本轮同步失败，不能推进 cursor。
- 标签通过 `upsert_tag`、`archive_tag`、`restore_tag`、`delete_tag`、`merge_tag`、`upsert_tag_alias`、`delete_tag_alias` 和 `set_post_tags` 同步；对应 server changes 是 `tag_updated/deleted`、`tag_alias_updated/deleted`、`post_tag_updated/deleted` 和 `post_tag_state_updated`。`delete_tag` 只允许 archived 且非 default 的 tag，用于释放错误词表项的 normalized name；server 会先发 assignment/alias 删除变更，再发 `tag_deleted`。`merge_tag` 下发的 `post_tag_updated` 可能保留原 assignment `id` 但改变 `tagId`，iOS 必须按 `id` 更新本地关联并处理 `(postId, tagId)` 冲突。iOS 应用 post tag assignment 时如果缺少本地 tag，应让本轮同步失败，不能推进 cursor。

## 9. 媒体上传与回填流程

媒体文件不直接放进 `/api/v1/sync`。

推荐流程：

1. iOS 生成 `postId` 和 `mediaId`。
2. iOS 生成压缩展示图，并移除 EXIF/GPS。
3. 如果用户选择保留原图，iOS 保留原图待上传副本。
4. iOS 本地创建 post 和 media 记录。
5. iOS 创建 `create_post` outbox operation。
6. 同步时先通过 `/api/v1/media/upload` 上传媒体文件；视频额外上传 poster 作为 `thumbnail` variant。
7. 完整 audio/video 上传成功后，Mac server 只保存媒体和同步 metadata，不自动生产 AI artifact。
8. iOS AI queue 使用本机 provider profiles 生成或重试 summary/title/tags/review；如果 artifact 同步到 iCloud 或 legacy archive，它作为 generated metadata 同步，credentials 不同步。Legacy 空闲 `/sync` 检查使用短 timeout，以便配置的 remote endpoint 不可达时快速尝试下一个 candidate；LAN、Tailscale/private VPN、Cloudflare Tunnel 或其他 HTTPS endpoint 都只是 legacy 可选网络层。恢复/本地变更同步保留更长 timeout。Storage & Diagnostics refresh 只做只读状态检查和 cursor 对比，避免进入诊断页就启动隐藏同步。
9. 媒体可以逐项成功或失败。
10. iOS 通过 `/api/v1/sync` 同步帖子、媒体元数据和 AI summary metadata。
11. 服务端记录部分同步状态。
12. 失败媒体保留在本地队列中自动重试。

iOS 在保存展示图和上传文件前都会压缩图片。当前压缩展示策略是最大边 `1600px`、JPEG 质量 `0.72`，并移除 EXIF/GPS 等隐私元数据。上传时再次走压缩路径，因此旧版本遗留的 pending 大图也会在下一次上传前被压缩。

媒体上传逐项执行；任意媒体失败不会阻塞本地时间线展示。失败后本地状态保持可重试，并由 sync retry 调度器按 5s、20s、60s、120s、300s 间隔自动重试。iOS 端上传队列优先处理新鲜 `pending` media，再处理旧 `failed` retry，避免一个早期超时音频挡住后面的语音。audio/video 上传会先写入临时 multipart 文件，再用 file-backed upload 发送，降低断网恢复和较大媒体上传时的内存压力。Settings > Storage & Diagnostics 提供 `Retry Uploads`，用于把 failed media 重新排为 pending 并立即触发同步。

远端媒体回填：

1. iOS 应用 `media_uploaded` 或远端 post 变更后，找出本地缺失的已上传图片缩略图或视频 poster。
2. iOS 调用 `POST /api/v1/media/batch-download`，默认请求 `thumbnail` variant。
3. 服务端用 macOS `sips` 按需生成最大边 800px 的 JPEG 缩略图，并把过大的旧缩略图重新压缩到目标范围。
4. 服务端返回 base64 JSON：`id`、`variant`、`contentType`、`fileName`、`base64`。
5. iOS 写入本地 media cache：图片缩略图更新 `localCompressedPath`，视频 poster 更新 `localThumbnailPath`。

语音和视频完整文件默认不自动回填；点击播放时通过 `GET /api/v1/media/:mediaId?variant=compressed` 按需下载，成功后保存在本机缓存。历史转写文本属于 legacy metadata；新 summary 结果通过 sync 回填，不依赖完整媒体文件下载。Settings > Storage & Diagnostics 的清理动作只清理这类可重新下载的完整语音/视频缓存。

保留 `GET /api/v1/media/:mediaId?variant=...` 作为单文件下载、完整音视频按需播放下载和 Admin 图片预览入口。iOS 主同步路径优先使用批量 JSON 下载缩略图/poster，因为 2026-04-29 真机验证发现多次独立二进制下载在 Tailscale/iOS 组合下更容易超时。

### 部分同步

如果文字和部分媒体已同步，但还有媒体上传失败，帖子状态为 `partial`。UI 可展示本地完整内容，设置页显示失败明细。

## 10. 删除和清理

MVP 支持删除，不支持完整回收站 UI。

删除流程：

1. 用户在 iOS 删除 post。
2. iOS 设置本地 `deletedAt`。
3. iOS 同时隐藏/软删除该 post 下本地评论。
4. iOS 创建 `delete_post` outbox operation。
5. 同步成功后服务端设置 `post.deletedAt`、相关 `media.deletedAt` 和该 post 下未删除 comments 的 `deletedAt`。
6. 服务端 30 天后永久删除数据库记录和相关媒体文件。

清理任务可由 Mac 服务端定时执行，也可在服务启动时执行一次。

当前实现会在服务启动时执行一次清理，并在服务运行中每 6 小时清理一次 30 天前软删除的帖子和媒体文件。删除文件时只允许删除数据目录内部的相对路径，避免误删数据目录外文件。

## 11. Mac 后台

后台 UI 由 React + Vite 实现，构建后作为静态资源由 Fastify 托管。

MVP 页面：

- Overview：服务状态、版本、schemaVersion。
- Devices：设备列表、撤销设备。
- Storage：数据目录、数据库大小、媒体大小。
- Sync：同步状态和失败概览。
- Logs：文件日志。
- Posts：内容运维列表、筛选、详情抽屉、图片预览、语音/视频转写查看、软删除和按设备清理测试数据。
- Archive：restic repository 配置、key 文件说明、manual backup、daily schedule、snapshot list/check、staged restore、promote preparation 和 recent maintenance jobs。
- Sync Health：最新 server change version、pending/rejected sync operations、failed media uploads、AI non-ready count 和 last sync timestamps。

后续页面：

- Trash：回收站和恢复。
- Search：独立搜索增强；当前 Posts 页已有文本搜索。

## 12. 日志

服务端写文件日志到：

```text
~/Library/Application Support/PrivateMoments/logs/
```

MVP 不强制日志轮转，但日志格式应结构化，便于后台展示和排查。

建议字段：

```json
{
  "time": "2026-04-28T10:00:00.000Z",
  "level": "info",
  "event": "sync.completed",
  "deviceId": "device-uuid",
  "acceptedOps": 3,
  "failedUploads": 1
}
```

## 13. launchd 自启动

Mac 服务端第一版使用 `launchd` 登录自启动。

设计要求：

- 服务进程读取固定数据目录。
- 配置文件可放在数据目录或 `server/config`。
- stdout/stderr 可由 launchd 接管。
- 应用自身仍写文件日志。
- 后续可增加菜单栏 App 包装启动状态。

## 14. OpenAPI 与同步协议文档

`shared/openapi.yaml` 描述：

- `/api/v1/health`
- `/api/v1/auth/login`
- `/api/v1/devices`
- `/api/v1/sync`
- `/api/v1/ai/media-summary`
- `/api/v1/media/upload`
- `/api/v1/media/batch-download`
- `/api/v1/timeline`
- `/api/v1/search`
- `/api/v1/admin/status`
- `/api/v1/admin/logs`
- `/api/v1/admin/posts`
- Admin status 的 storage diagnostics 字段。
- Media schema 的 audio/video `transcriptionText` 字段。
- AI summary request/response schema 和 `ai_summary_updated` / `ai_summary_deleted` 同步语义。
- Bearer token 认证。
- 通用错误响应。

`shared/sync-protocol.md` 描述：

- `syncCursor` 语义。
- `opId` 幂等。
- outbox 处理顺序。
- 媒体上传与帖子同步顺序。
- 图片压缩、逐项上传和失败重试。
- 旧客户端语音/视频转写 metadata 的 `update_media_transcription` 兼容同步。
- 多设备最后写入胜出。
- 删除和软删除。
- 部分同步状态。

## 15. 安全

当前安全边界：

- iPhone 本地 app container 和文件保护是默认基础。
- iCloud/CloudKit private database 是当前 opt-in 多设备同步层。
- 不实现 Ownlight 账号系统；CloudKit 依赖用户 Apple Account。
- 外部 AI API key 只放在 iPhone Keychain 中，不进入 iCloud、legacy server、本地文档示例或日志。
- legacy Server URL、Bearer device token、服务端 token hash、设备撤销和 Mac 文件权限只属于历史兼容/维护路径。

不做：

- 端到端加密。
- 应用级本地数据库加密。
- 多用户权限。
- OAuth。
- 2FA。

## 16. 性能和可靠性

### iOS

- 时间线本地优先渲染。
- 本地 SQLite 保存全部文本元数据。
- 已下载图片缩略图、视频 poster 和完整语音/视频缓存保存在本地。
- 旧图片和远端完整语音/视频按需下载。
- 同步不阻塞主 UI。
- 图片压缩在后台任务中执行。
- 失败同步和上传自动延迟重试。
- Settings > Storage & Diagnostics 可快速查看本地占用、同步健康状态、AI summary 诊断和 AI token usage。

### Legacy Mac

- SQLite 对单用户场景足够。
- 媒体文件存磁盘，数据库只存路径和元数据。
- `server_change.version` 支持增量同步。
- sync endpoint 支持批量操作和重试。
- `/api/v1/admin/status` 暴露服务端数据目录存储诊断、AI summary 诊断和 AI token usage，供 Admin 和 iOS Settings 使用。
- AI summary provider 失败只写入 `ai_summaries.status = failed`，不影响 post/media/comment sync，也不把私人 transcript 或 summary 正文写入正常日志。

## 17. 未来阶段

第二阶段：

- 回收站 UI。
- 应用内一键 zip 备份导出。
- 更完整的 storage cleanup。
- 多设备冲突提示。
- 原图保留策略和空间管理。

第三阶段：

- 多设备体验增强。
- 原生后台传输优化。
- 开源安装文档完善。

## 18. 已确认架构决策

- iOS 原生 App 是主入口。
- iPhone 本地 SQLite 是默认 source of truth。
- iCloud/CloudKit private database 是当前 opt-in 多设备同步层。
- 不需要 Ownlight 账号系统；同 Apple Account 设备通过 CloudKit 同步。
- legacy Mac server/admin 只保留兼容、archive、diagnostics 和低频维护。
- 单用户，但数据结构支持多设备。
- 多设备冲突使用最后写入胜出 + 操作日志。
- 时间线本地优先渲染 + 后台增量同步。
- iPhone 缓存全部元数据、已下载图片缩略图、视频 poster 和按需下载的完整语音/视频缓存。
- 文本搜索以 iPhone 本地为主；legacy Mac 后台搜索仅用于历史数据排障。
- MVP 做发布、iCloud opt-in 同步、详情、编辑、评论、音视频、转写、收藏、筛选、删除和必要 legacy 运维。
- 第一版 AI 只做用户手动触发的 audio/video summary；不做自动人格、评论、评测、archive-wide analysis 或语义搜索。
- 回收站 UI、备份导出、多设备冲突提示后置。
