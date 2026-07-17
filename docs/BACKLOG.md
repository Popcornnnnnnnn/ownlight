# Ownlight Backlog

这个文件记录暂不进入当前开发主线、但后续可能有价值的想法。进入正式开发前再补充需求细节、交互方案和验收标准。

## v0.1 上架前判断

2026-06-08 复核：本文件中的条目均不阻塞 v0.1 App Store 准备。它们是上架后观察真实使用习惯、内容规模和 AI 使用意愿后再决定是否投入的增强方向。当前上架收口以 `docs/RELEASE-CHECKLIST.md`、`docs/APP-PRIVACY-DATA-INVENTORY.md`、`docs/APP-STORE-READINESS.md` 和 `npm run doctor:app-store` 为准。

## AI 私人小社会 / 作品评测

状态：暂缓

背景：用户希望后续让 AI 对自己发表的内容进行评测、回应，甚至引入一些随机性，形成一种私人的小社会感。这个方向有产品潜力，但它和第一版 AI 摘要的“安静整理工具”定位不同。

可能功能：

- AI reviewer：对某条 moment 做作品式反馈或评论。
- 多种 AI 视角：温和总结者、挑剔评论者、未来的自己、随机观察者等。
- 可控随机性：用户主动触发，或在明确开关打开后偶发生成。
- 独立 AI reflections 区域：避免直接混进普通 comments，保持人写内容和 AI 生成内容边界清楚。

暂缓原因：先完成 M005 AI Media Summaries，建立 server-side 外部 AI 调用、生成结果存储、sync/recovery、隐私日志和基础评估。等工具型 AI 稳定后，再决定 AI persona 是否进入主线。

## AI 文字 Moment 总结

状态：候选（v0.1 后评估，不阻塞上架）

背景：当前 AI summary 重点服务语音和视频媒体。后续如果长文字 moment、网页摘录、会议记录、学习笔记变多，可以考虑对正文文本本身生成结构化摘要。

可能功能：

- 长文字摘要：对正文较长的 moment 生成一句话总结、重点条目、后续行动或主题标签建议。
- 手动触发优先：避免短文字和普通日常记录被过度 AI 化。
- Summary 独立展示：摘要作为辅助信息存在，不自动覆盖用户正文，也不默认插入 timeline 主体。
- 与搜索/回顾联动：让长文字内容更容易被 Timeline Search、Weekly/Monthly Review 和未来聊天界面引用。

暂缓原因：先稳定 iCloud Sync、Weekly Review、媒体 summary 和 Markdown 阅读体验。文字 summary 是否高频、有无付费或留存价值，需要真实使用后再判断。

## 个人时间线聊天 / LLM Chat

状态：候选（v0.1 后评估，不阻塞上架）

背景：未来可以把 moments、comments、tags、check-ins、AI summaries 和 periodic reviews 作为个人知识库，让用户在 App 内和 LLM 聊天，查询过去记录、总结阶段变化、寻找线索或做复盘。这个方向可以接入 OpenAI-compatible API、本地 LLM、OpenClaw 等外部能力，但需要明确隐私和配置边界。

可能功能：

- Chat with timeline：用户用自然语言询问自己的记录，例如“最近我反复在关注什么？”、“上个月有哪些产品想法？”。
- 检索增强：先本地检索相关 moments，再把必要片段发送给用户配置的 AI provider。
- 可配置 provider：沿用 BYOK 思路，让用户选择 Base URL、API Key、模型和是否启用联网/外部 agent。
- 引用来源：回答中必须能跳回具体 moment、comment 或 review，避免 AI 编造。
- 隐私开关：默认关闭，清楚说明哪些内容会被发送到外部 provider。

暂缓原因：这是比 AI reviewer 更大的能力，需要先有稳定同步、可靠本地检索、明确隐私说明和足够多真实数据后再投入。

## On This Date / 历史浮现

状态：已完成

背景：用户希望未来可以像一些日记或相册类 App 一样，偶尔看到过去同一天、过去某个月或过去某个阶段的记录自动浮现，形成一种“历史感”和回看生活的触发。

可能功能：

- `On This Date`：在今天展示一年前、半年前、一个月前或历史同日的 moment。
- 随机历史浮现：从过去较久的内容中抽取一条或一组，作为轻量回看入口。
- 可控入口：默认不打扰主时间线，可以放在 Archive/Calendar 页、首页顶部轻量卡片或 Settings 可关闭模块。
- 过滤规则：避免显示已删除、failed、无媒体且过短的低价值内容；优先显示收藏、有评论、有 AI summary、有标签或媒体丰富的 moment。

当前状态：已实现轻量 Timeline Memory Links / 历史浮现机制。后续只保留小范围体验调整，例如频率、筛选质量和提示文案，不再作为大功能候选项反复讨论。

## 周期性 AI 总结

状态：部分完成（Weekly Review 已完成；Monthly Review 为 v0.1 后增强，不阻塞上架）

背景：用户希望后续可以按周或按月把一段时间内的 moments 汇总成结构化回顾，例如本周记录了什么、学习了什么、情绪和关注点有什么变化。但目前内容量还没大到必须做自动周期总结。

可能功能：

- Weekly Review：按自然周总结这一周的主要事件、学习整理、想法、情绪变化和待跟进事项。已实现。
- Monthly Review：按月份生成更长周期的生活回顾和主题脉络。未完成，是后续主要缺口。
- 标签维度总结：只总结 `学习整理`、`日记`、`复盘` 等特定主标签下的内容。
- 可手动触发：先不做自动推送，用户在 Calendar/Archive 页选择某一周或某一月后主动生成。
- 隐私边界：当前默认由 iPhone 本机准备 bounded input 后调用用户配置的 AI provider；provider credentials 保存在 iPhone Keychain，日志不记录正文、summary body 或私人内容。

当前状态：Weekly Review 已进入主功能；Monthly Review 仍待设计和实现。后续不要再把“周期性 AI 总结”整体当作未开始功能，而应只讨论月度总结、标签维度总结和更高级的回顾分析。
