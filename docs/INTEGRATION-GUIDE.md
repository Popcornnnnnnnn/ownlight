# Ownlight 集成指南

这份指南面向需要维护 legacy Mac server/API 的开发者或未来 agent：包括旧 client、admin tool、diagnostic script、archive/recovery helper 等。当前 iPhone-first + iCloud/CloudKit 同步路径不使用这些 HTTP sync endpoints，也不要求用户配置 Server Base URL。

## Legacy Server Base URL

本地 Mac 开发：

```text
http://127.0.0.1:3210
```

如果维护 legacy iPhone-to-server path，真实 iPhone 需要一个能从手机访问 Mac server 的 URL。这个 URL 可以来自 LAN、Tailscale/private VPN、Cloudflare Tunnel、反向代理或其他受保护 HTTPS endpoint，例如：

```text
http://<mac-lan-ip>:3210
http://<mac-private-vpn-ip>:3210
https://<your-protected-endpoint>
```

iOS app 的 legacy server path 在 Settings 中保存 server URL。真实设备安装脚本可以通过 `PRIVATE_MOMENTS_DEVICE_SERVER_URL` 或 ignored `.env.local` 中的 `PRIVATE_MOMENTS_FALLBACK_SERVER_URL` 注入 fallback。当前 iCloud 同步不使用这些 URL。公开配置不要写入个人域名、tunnel id、tailnet 名称或设备名。

## Authentication

Login 会用单用户 password 换取长期 device token。

```bash
curl -X POST http://127.0.0.1:3210/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{
    "password": "your-password",
    "deviceName": "Dev iPhone",
    "platform": "ios",
    "deviceKey": "stable-device-key"
  }'
```

Authenticated requests 使用：

```http
Authorization: Bearer <device-token>
```

`deviceKey` 用于避免重复 device rows。同一物理设备或同一 browser installation 重复 login 时，应复用同一个 `deviceKey`。

## Endpoint Quick Reference

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/v1/health` | Health、schema version、data directory。 |
| `POST` | `/api/v1/auth/login` | Password login，并签发或重新绑定 device token。 |
| `GET` | `/api/v1/devices` | 列出 authorized devices。 |
| `DELETE` | `/api/v1/devices/:deviceId` | 撤销 device token。 |
| `POST` | `/api/v1/sync` | 推送 local operations，并拉取 server changes。 |
| `POST` | `/api/v1/ai/media-summary` | 为一个已上传的 audio/video media 生成或重新生成 AI summary；多段 audio 使用第一条 audio 作为 summary anchor。 |
| `DELETE` | `/api/v1/ai/media-summary/:summaryId` | 软删除一条 generated AI summary。 |
| `POST` | `/api/v1/media/upload` | 用 multipart form data 上传 image/audio/video/document media file。 |
| `POST` | `/api/v1/media/batch-download` | 以 base64 JSON 下载多个 media variants。 |
| `GET` | `/api/v1/media/:mediaId?variant=thumbnail` | 下载单个 media file。 |
| `POST` | `/api/v1/checkin-media/upload` | 上传 check-in entry 的 image/audio media。 |
| `POST` | `/api/v1/checkin-media/batch-download` | 以 base64 JSON 下载多个 check-in media。 |
| `GET` | `/api/v1/checkin-media/:mediaId` | 下载单个 check-in media 文件。 |
| `GET` | `/api/v1/timeline` | 读取 server timeline，用于 diagnostics。 |
| `GET` | `/api/v1/posts/:postId` | 读取单个 post。 |
| `GET` | `/api/v1/search?q=...` | 搜索 server archive text、comments，并兼容搜索历史 audio/video transcription metadata。 |
| `GET` | `/api/v1/admin/status` | Admin dashboard status 和 storage diagnostics。 |
| `GET` | `/api/v1/admin/logs?limit=100` | Admin dashboard logs。 |
| `GET` | `/api/v1/admin/posts` | Admin post list，支持 filters。 |
| `GET` | `/api/v1/admin/posts/:postId` | Admin post detail。 |
| `DELETE` | `/api/v1/admin/posts/:postId` | 从 Admin soft delete 单个 post。 |
| `GET` | `/api/v1/admin/devices/:deviceId/clean-posts/preview` | 预览某个 device 创建的 posts 永久清理候选。 |
| `POST` | `/api/v1/admin/devices/:deviceId/clean-posts` | 永久清理某个 device 创建的测试 posts。 |
| `GET` | `/api/v1/admin/maintenance/state` | 读取 maintenance mode 和当前 running job。 |
| `GET` | `/api/v1/admin/maintenance/jobs` | 列出最近 maintenance jobs，可按 type/status 过滤。 |
| `GET` | `/api/v1/admin/maintenance/jobs/:jobId` | 读取单个 maintenance job。 |
| `POST` | `/api/v1/admin/maintenance/jobs/sync-health-refresh` | 创建并运行一次安全 Sync Health refresh job。 |
| `GET` | `/api/v1/admin/archive/repository` | 读取 restic backup repository 状态。 |
| `POST` | `/api/v1/admin/archive/repository` | 配置 backup repository path。 |
| `POST` | `/api/v1/admin/archive/repository/init` | 初始化 restic repository。 |
| `POST` | `/api/v1/admin/archive/schedule` | 设置每日备份 schedule。 |
| `GET` | `/api/v1/admin/archive/snapshots` | 列出 restic snapshots。 |
| `POST` | `/api/v1/admin/archive/jobs/backup` | 启动手动 backup job。 |
| `POST` | `/api/v1/admin/archive/jobs/check` | 启动 repository check job。 |
| `POST` | `/api/v1/admin/archive/jobs/restore` | 把 snapshot 恢复到新的 staged data directory。 |
| `POST` | `/api/v1/admin/archive/jobs/promote` | 验证 staged restore、做 pre-promote backup，并写入 restart instructions。 |
| `POST` | `/api/v1/admin/archive/jobs/export` | 创建 migration-first export package，支持全量或日期范围。 |
| `POST` | `/api/v1/admin/archive/jobs/import` | 从 export package 导入到新的 staged data directory。 |

## Sync

`POST /api/v1/sync` 是 device/server reconciliation endpoint，不是针对单个 resource 的 CRUD endpoint。

Request shape：

```json
{
  "deviceId": "device-uuid",
  "lastSyncCursor": 0,
  "localChanges": [
    {
      "opId": "op-uuid",
      "type": "create_post",
      "entityType": "post",
      "entityId": "post-uuid",
      "clientCreatedAt": "2026-04-29T12:00:00.000Z",
      "payload": {
        "text": "记录一条动态",
        "occurredAt": "2026-04-29T11:58:00.000Z"
      }
    }
  ]
}
```

当前支持的 client operation types：

- `create_post`
- `update_post`
- `insert_ai_title`
- `update_post_favorite`
- `update_post_pin`
- `delete_post`
- `create_comment`
- `delete_comment`
- `update_media_transcription`
- `upsert_tag`
- `archive_tag`
- `restore_tag`
- `delete_tag`
- `merge_tag`
- `upsert_tag_alias`
- `delete_tag_alias`
- `set_post_tags`
- `upsert_checkin_item`
- `delete_checkin_item`
- `upsert_checkin_entry`
- `delete_checkin_entry`
- `delete_checkin_media`

Check-in operations 也使用同一个 sync endpoint。`checkin_item` 定义活动本身，`checkin_entry` 定义某一次打卡，`checkin_media` 表示 check-in entry 自己的图片或语音附件。它们不会创建 ordinary post；只有 entry payload 的 `showInTimeline` 为 `true` 时，iOS Timeline 会直接渲染 compact check-in row。Calendar 和 Day Review 会读取所有未删除 check-in entries，不受 `showInTimeline` 影响。Item payload 的 `timeVisualization` 支持 `none`、`timeLine`、`timeHeatmap`，旧 payload 缺省为 `none`；`timeLine` 只允许 `oncePerDay` item 使用。Item payload 的 `dayStartHour` 支持 `0...23`，旧 payload 缺省为 `0`，用于一天一次 item 的重置边界和 Time Line item day 聚合。Check-in audio summary 不是 client outbox operation；它由 server 在上传后异步生成，并通过 `checkin_ai_summary_updated` / `checkin_ai_summary_deleted` server changes 下发到 iPhone。

Comment operations 使用同一个 sync endpoint。`create_comment` 的 `entityType` 是 `comment`，`entityId` 是 comment id，payload 至少包含父 `postId` 和 `text`：

```json
{
  "opId": "op-comment-create",
  "type": "create_comment",
  "entityType": "comment",
  "entityId": "comment-uuid",
  "clientCreatedAt": "2026-04-30T12:00:00.000Z",
  "payload": {
    "postId": "post-uuid",
    "text": "补一句后来的想法",
    "createdAt": "2026-04-30T12:00:00.000Z"
  }
}
```

`delete_comment` payload 只需要删除时间：

```json
{
  "opId": "op-comment-delete",
  "type": "delete_comment",
  "entityType": "comment",
  "entityId": "comment-uuid",
  "clientCreatedAt": "2026-04-30T12:05:00.000Z",
  "payload": {
    "deletedAt": "2026-04-30T12:05:00.000Z"
  }
}
```

`update_media_transcription` 是 schema version 6 留下的兼容 operation，用于旧客户端把本机转写文本同步为 media metadata。新 iOS 发布路径已经停用本机转写，不再发送这个 operation，也不再通过 upload metadata 发送 `transcriptionText`。

```json
{
  "opId": "op-media-transcription",
  "type": "update_media_transcription",
  "entityType": "media",
  "entityId": "media-uuid",
  "clientCreatedAt": "2026-04-30T12:10:00.000Z",
  "payload": {
    "postId": "post-uuid",
    "transcriptionText": "本机转写出来的语音内容",
    "updatedAt": "2026-04-30T12:10:00.000Z"
  }
}
```

重要规则：

- `opId` 必须在同一 device 内唯一。Server 使用 `(deviceId, opId)` 保证 idempotency。
- `syncCursor` 表示 client 已经应用的最大 `server_changes.version`。
- Client 只能在成功应用所有返回的 `serverChanges` 后，持久化 `nextSyncCursor`。
- iOS 接受带 fractional seconds 和不带 fractional seconds 的 ISO8601 timestamps。
- 如果 local database 为空，iOS 会请求 cursor `0`，从 Mac archive 恢复数据。
- Server 会拒绝给不存在或已删除 post 创建 comment。
- 删除 post 会级联软删除 comments，但 server 只发 `post_deleted`；不会为父删除生成每条 `comment_deleted`。
- Client 应用 `comment_created` 或 `comment_deleted` 时如果找不到父 post，应让本轮 sync 失败并保留原 cursor。
- `update_media_transcription` 只作为旧客户端兼容路径更新 audio/video media 的文本 metadata；server 会发出 `media_transcription_updated` server change。
- AI summary 由独立 endpoint 触发，但同步恢复仍走 server changes：`ai_summary_updated` 和 `ai_summary_deleted`。Client 应用这些变更时如果找不到父 post 或 media，应让本轮 sync 失败并保留原 cursor。
- Smart Tags 作为一等 metadata 同步：词表 changes 是 `tag_updated` 和 `tag_alias_updated/deleted`，post 关联 changes 是 `post_tag_updated/deleted` 和 `post_tag_state_updated`。Client 应用 post tag assignment 时如果本地缺少对应 tag，应让本轮 sync 失败并保留原 cursor。

## Smart Tags Sync

Tag vocabulary 和 post assignments 分开同步。

`create_post` 可以在 payload 中带可选 `primaryTagId`：

```json
{
  "text": "今天学了一点 LLM",
  "occurredAt": "2026-05-03T12:00:00.000Z",
  "primaryTagId": "tag-primary-learning"
}
```

`set_post_tags` 用于替换一条 moment 的完整标签集合：

```json
{
  "opId": "op-set-post-tags",
  "type": "set_post_tags",
  "entityType": "post",
  "entityId": "post-uuid",
  "clientCreatedAt": "2026-05-03T12:05:00.000Z",
  "payload": {
    "primaryTagId": "tag-primary-learning",
    "topicTagIds": ["topic-llm", "topic-reinforcement-learning"],
    "updatedAt": "2026-05-03T12:05:00.000Z"
  }
}
```

词表操作：

- `upsert_tag`：`entityType: "tag"`，payload `{type, name, colorHex, isDefault, aiUsableAsPrimary, updatedAt}`。
- `archive_tag`：payload `{archivedAt}`，隐藏标签但保留历史。
- `restore_tag`：恢复 archived tag。
- `delete_tag`：payload `{deletedAt}`，仅用于 archived 且非 default 的 tag。server 会先广播活跃 assignment 的 `post_tag_deleted` 和活跃 alias 的 `tag_alias_deleted`，再广播 `tag_deleted`，并释放该 tag 的 normalized name。
- `upsert_tag_alias`：`entityType: "tag_alias"`，payload `{tagId, alias}`。
- `delete_tag_alias`：payload `{deletedAt}`。
- `merge_tag`：`entityType: "tag"`，`entityId` 是 source topic tag，payload `{targetTagId, alias, mergedAt}`；server 会把 source 的活跃关联移动到 target、保留 source name 为 target alias，并 archive source tag。

默认主标签由 server/iOS seed：`日记`、`想法`、`学习整理`、`情绪`、`碎碎念`、`复盘`。默认主标签不可重命名或归档；自定义主标签和 topic tag 通过 Settings > Tags 管理。AI 自动标签只在新 audio moment 的首次 ready summary 中应用一次；server 会把 active topic tag/alias 词表传给 summary/tag prompt，并在落库前优先复用现有 topic，只有没有可匹配 topic 时才创建新标签。

## AI Media Summary

当前 iPhone-first 路径中，AI summary 的 provider credentials 只保存在 iPhone Keychain，不进入 sync、Mac server、iCloud 或 export package。iOS 先在本机进行 audio/video transcription，再把得到的 transcript 交给已配置的 text provider 生成结构化 summary；多段 audio 会按 `sortOrder` 合并成一份 summary。失败诊断要区分两段：transcription failure 包括 on-device speech no match、音频不可读或本机权限/模型问题；text provider failure 包括 API key 错误、quota、model not found、网络超时或 provider 返回异常。Mac server 的 media summary route 仍保留为历史/运维兼容路径，不是当前单机 iPhone 的默认产品入口。

Request：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/ai/media-summary \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "postId": "post-uuid",
    "mediaId": "media-uuid",
    "forceRegenerate": false
  }'
```

Response：

```json
{
  "summary": {
    "id": "summary-uuid",
    "postId": "post-uuid",
    "mediaId": "media-uuid",
    "status": "ready",
    "format": "document",
    "language": "zh",
    "documentTitle": "面试复盘",
    "oneLiner": "这段语音主要复盘了一次面试后的感受、系统设计回答问题，以及下一次准备的重点。",
    "documentBlocks": [
      {
        "kind": "heading",
        "level": 1,
        "text": "一句话总结",
        "items": []
      },
      {
        "kind": "paragraph",
        "level": 0,
        "text": "说话者认为这次面试整体可复盘的重点在系统设计表达顺序，而不是单个知识点遗漏。",
        "items": []
      },
      {
        "kind": "heading",
        "level": 1,
        "text": "主要内容",
        "items": []
      },
      {
        "kind": "bullets",
        "level": 0,
        "text": "",
        "items": ["先讲约束再讲方案会更清楚", "需要把权衡和边界条件说得更主动"]
      },
      {
        "kind": "ai_suggested",
        "level": 0,
        "text": "下一次准备时可以先写一个 3 分钟系统设计开场模板。",
        "items": []
      }
    ],
    "overview": "这段语音主要复盘了一次面试后的感受、系统设计回答问题，以及下一次准备的重点。",
    "keyPoints": ["先讲约束再讲方案会更清楚", "需要把权衡和边界条件说得更主动"],
    "sections": [],
    "summaryText": "# 面试复盘\n\n这段语音主要复盘了一次面试后的感受、系统设计回答问题，以及下一次准备的重点。",
    "inputTranscriptLength": 320,
    "inputDurationSeconds": 86,
    "promptVersion": "media-summary-v4",
    "provider": "openai",
    "model": "gpt-5.5",
    "errorCode": null,
    "errorMessage": null,
    "createdAt": "2026-04-30T12:20:00.000Z",
    "updatedAt": "2026-04-30T12:20:10.000Z",
    "deletedAt": null
  }
}
```

常见轻量失败：

- `media_file_missing`：Mac server 上找不到该媒体文件。
- `empty_transcript`：本地转写没有返回可用文本。
- `local_transcription_timeout` / `local_transcription_failed` / `local_transcription_invalid_output`：Mac 本地转写超时、执行失败或输出无效。
- `not_configured`：server 缺少外部 AI API key 或配置。
- `provider_request_failed` / `provider_http_*` / `provider_timeout` / `invalid_output`：外部 summary provider 或结构化输出校验失败。

重新生成时设置 `forceRegenerate: true`。删除 summary 只删除 generated metadata：

```bash
curl -X DELETE http://127.0.0.1:3210/api/v1/ai/media-summary/summary-uuid \
  -H "Authorization: Bearer $TOKEN"
```

AI summary generated metadata 会进入 iPhone 本地 Timeline search；当前 server `/api/v1/search` 仍只搜索 post text、comments 和历史 media transcription metadata。`media-summary-v4` 的主内容是 `documentTitle`、`oneLiner` 和 `documentBlocks`；`overview`、`keyPoints`、`sections` 和 `summaryText` 继续保留，主要用于 copy 文本和旧客户端兼容。v4 继承 v3 的短标题要求：可识别非空音频/转录应生成 40 字符以内短标题，server 会在 provider 返回空/过长标题时从 `oneLiner` 派生 fallback。v4 额外把 active topic tag/alias 词表用于 AI topic 复用，避免近义 topic 分裂。排查时只记录 id、状态、provider/model、错误码和 transcript length；不要复制私人 transcript 或 summary 正文。`AI_TRANSCRIPTION_PROVIDER=local` 是默认路径，本地转写模型和超时可通过 `AI_LOCAL_TRANSCRIPTION_MODEL` / `AI_LOCAL_TRANSCRIPTION_TIMEOUT_MS` 覆盖。`/api/v1/admin/status` 的 `aiSummaries` 字段提供 `transcribing`、`summarizing`、`ready`、`failed` 计数和非 ready 项，供 iOS Settings > Storage & Diagnostics 显示；recent diagnostics 还包含卡住时长和 retry hint。

新 audio 的 AI 标题写回通过 `insert_ai_title` 同步，不使用普通 `update_post`。payload 只包含 `{summaryId, mediaId, insertedAt}`；server 从自己的 ready audio summary 读取 `documentTitle`，验证 post/media/summary 关系和当前 post 没有行首 `# ` / `## ` 标题后，才发出 `post_updated`，并带 `updateSource: "ai_title"`。客户端应用该 change 时不应把它当作用户手动编辑。

`ai_summary_updated` 是 server-originated change。客户端即使没有本地 outbox operation，也需要通过正常 sync pull 到这些变更；如果 Mac 上 summary 已经 ready 但 iPhone 仍不可见，先比较 iPhone `lastSyncCursor` 和 server `server_changes.version`。

## Media Upload

用 multipart form data 上传 media file；下面是 image 的最小示例：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/media/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F mediaId=media-uuid \
  -F postId=post-uuid \
  -F variant=compressed \
  -F kind=image \
  -F mimeType=image/jpeg \
  -F originalPreserved=false \
  -F sortOrder=0 \
  -F file=@image.jpg
```

Server 会把文件存到 configured data directory，只把 relative file paths 和 metadata 写入 SQLite。`kind` 支持 `image`、`video`、`audio`、`document`；当前 `document` 首版用于 PDF，使用 `mimeType=application/pdf` 和 `variant=compressed`，不使用 `thumbnail`。视频 poster 用同一 endpoint 上传为 `variant=thumbnail`，完整音频/视频用 `variant=compressed`。音频/视频可附带 `durationSeconds`。新 iOS 不再附带 `transcriptionText`。多段 audio upload 可在每段 `compressed` 上传时附带 `audioGroupCount=1...9`；iPhone-direct AI summary 不依赖 server upload 后自动排队。Admin 和 iOS timeline 会显示轻量时长。

如果上传 PDF，`kind=document`，`mimeType` 应为 `application/pdf`：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/media/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F mediaId="$(uuidgen)" \
  -F postId="$POST_ID" \
  -F variant=compressed \
  -F kind=document \
  -F mimeType=application/pdf \
  -F file=@/path/to/file.pdf
```

Check-in media 使用独立父对象，不复用 ordinary post media。下面是图片示例：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/checkin-media/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F mediaId=checkin-media-uuid \
  -F entryId=checkin-entry-uuid \
  -F variant=compressed \
  -F kind=image \
  -F mimeType=image/jpeg \
  -F sortOrder=0 \
  -F file=@meal.jpg
```

如果上传语音，`kind=audio`，`mimeType` 可以是 `audio/mp4` 或 `audio/x-m4a`，文件通常是 `.m4a`：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/checkin-media/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F mediaId=checkin-media-uuid \
  -F entryId=checkin-entry-uuid \
  -F variant=compressed \
  -F kind=audio \
  -F mimeType=audio/x-m4a \
  -F durationSeconds=93.5 \
  -F sortOrder=0 \
  -F file=@voice-note.m4a
```

Legacy check-in media server path 支持 still image 和单段 audio，不支持 video。上传成功后 server 写入 `checkin_media`，发出 `checkin_media_uploaded`；删除已上传 check-in media 用 `delete_checkin_media` sync operation。旧 audio path 可以在后台走 Mac 本地 transcription + external summary provider，并把结果写入独立 `checkin_ai_summaries`，再发出 `checkin_ai_summary_updated` / `checkin_ai_summary_deleted`。这些 summary 仍然是 check-in-owned metadata，不会触发 ordinary moment 的 AI title auto-insert、AI tags、OCR 或 ordinary media summary routes。当前 iPhone-first path 默认由 iPhone 本机生成 check-in audio summary，server route 只保留历史/运维兼容。

## Media Batch Download

iOS 使用 batch download 做 remote image thumbnail 和 video poster cache recovery：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/media/batch-download \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{
    "mediaIds": ["media-uuid-1", "media-uuid-2"],
    "variant": "thumbnail"
  }'
```

Response：

```json
{
  "media": [
    {
      "id": "media-uuid-1",
      "variant": "thumbnail",
      "contentType": "image/jpeg",
      "fileName": "media-uuid-1.jpg",
      "base64": "..."
    }
  ]
}
```

Check-in 照片恢复使用同样的 base64 JSON shape，但 endpoint 是 `/api/v1/checkin-media/batch-download`，目前只接受 `variant=compressed`。

Server 使用 `sips` 按需生成 image thumbnail variants。视频 poster 由 iOS 上传为 `thumbnail` variant。当前 image thumbnail policy 是 max edge `800px`；如果已有 thumbnail 超过 server threshold，会重新生成。

## Admin Status And Storage Diagnostics

`GET /api/v1/admin/status` 使用普通 Bearer token auth。Legacy iOS diagnostics 登录后可调用这个 endpoint；如果 Mac server offline 或请求失败，iOS UI 应隐藏 legacy Mac/server diagnostics，而不是弹 error alert。高权限 Admin 操作（posts/logs、archive mutation/jobs、maintenance 写操作等）还要求 token 对应的 `Device.adminEnabled=true`；Admin UI 的 `web` 登录和 Mac doctor/smoke 登录会获得 admin-capable session，iOS 登录保持普通同步/诊断 token。

```bash
curl -X GET http://127.0.0.1:3210/api/v1/admin/status \
  -H "Authorization: Bearer $TOKEN"
```

Response shape：

```json
{
  "serverVersion": "0.1.0",
  "schemaVersion": 17,
  "dataDir": "/path/to/PrivateMoments",
  "uptimeSeconds": 123,
  "counts": {
    "activeDevices": 1,
    "revokedDevices": 0,
    "posts": 8,
    "deletedPosts": 6,
    "media": 19
  },
  "storage": {
    "totalBytes": 29480943,
    "databaseBytes": 163840,
    "mediaBytes": 29268634,
    "logsBytes": 42996,
    "availableBytes": 143418429440
  },
  "sync": {
    "latestServerChangeVersion": 194,
    "pendingOperations": 0,
    "rejectedOperations": 0,
    "failedMediaUploads": 0,
    "aiNonReady": 0,
    "lastServerChangeAt": "2026-05-05T10:20:30.000Z",
    "lastSyncOperationAt": "2026-05-05T10:18:30.000Z",
    "lastSuccessfulSyncAt": "2026-05-05T10:18:31.000Z",
    "lastRejectedSyncAt": null
  },
  "aiSummaries": {
    "total": 10,
    "transcribing": 0,
    "summarizing": 0,
    "ready": 4,
    "failed": 6,
    "deleted": 0,
    "recent": [
      {
        "id": "summary-uuid",
        "mediaId": "media-uuid",
        "status": "failed",
        "errorCode": "local_transcription_failed",
        "inputTranscriptLength": null,
        "inputDurationSeconds": 42.5,
        "updatedAt": "2026-05-01T10:20:30.000Z"
      }
    ]
  },
  "aiUsage": {
    "today": {
      "requests": 2,
      "successfulRequests": 2,
      "failedRequests": 0,
      "totalTokens": 8200,
      "inputTokens": 6900,
      "outputTokens": 1300,
      "cachedInputTokens": 0,
      "estimatedRequests": 0
    },
    "currentWeek": {
      "requests": 24,
      "successfulRequests": 23,
      "failedRequests": 1,
      "totalTokens": 128000,
      "inputTokens": 112000,
      "outputTokens": 16000,
      "cachedInputTokens": 5000,
      "estimatedRequests": 3
    },
    "currentMonth": {
      "requests": 24,
      "successfulRequests": 23,
      "failedRequests": 1,
      "totalTokens": 128000,
      "inputTokens": 112000,
      "outputTokens": 16000,
      "cachedInputTokens": 5000,
      "estimatedRequests": 3
    },
    "allTime": {
      "requests": 24,
      "successfulRequests": 23,
      "failedRequests": 1,
      "totalTokens": 128000,
      "inputTokens": 112000,
      "outputTokens": 16000,
      "cachedInputTokens": 5000,
      "estimatedRequests": 3
    },
    "byFeatureCurrentMonth": [
      {
        "feature": "media_summary",
        "requests": 20,
        "successfulRequests": 20,
        "failedRequests": 0,
        "totalTokens": 86000,
        "inputTokens": 74000,
        "outputTokens": 12000,
        "cachedInputTokens": 0,
        "estimatedRequests": 2
      }
    ],
    "recentFailures": []
  },
  "tags": {
    "total": 18,
    "primary": 6,
    "topics": 12,
    "archived": 1,
    "aiAssignments": 4,
    "manualAssignments": 9
  }
}
```

`databaseBytes` 包含 SQLite database 以及 `-wal`、`-shm` sidecar files。`totalBytes` 是整个 configured data directory。`availableBytes` 是 data directory 所在 volume 的可用空间。`sync.latestServerChangeVersion` 是 Mac server 已写入的最大 `server_changes.version`，可和 iPhone `lastSyncCursor` 比较。`sync.pendingOperations`、`rejectedOperations`、`failedMediaUploads`、`aiNonReady` 和 timestamps 用于 Mac Admin / iOS Settings 的 Sync Health。`aiSummaries.recent` 只返回非 ready 项的状态、错误码、duration 和 transcript length，不返回 transcript 或 summary 正文。`aiUsage` 来自 `ai_usage_events`，按 Today、current week、current month、all time 聚合，并返回本月 feature breakdown；provider 没有返回 usage 时会用字符数估算并计入 `estimatedRequests`。`tags` 只返回安全计数，不返回 post text、comment text、transcript、prompt、review input 或 summary 正文。

## Maintenance Jobs And Archive API

Maintenance jobs 是 backup/restore/export/import/sync-health 的统一 job record。普通列表：

```bash
curl -X GET "http://127.0.0.1:3210/api/v1/admin/maintenance/jobs?limit=12" \
  -H "Authorization: Bearer $TOKEN"
```

Response：

```json
{
  "jobs": [
    {
      "id": "job-uuid",
      "type": "backup_create",
      "status": "succeeded",
      "stage": "completed",
      "progress": 100,
      "metadata": {
        "source": "manual",
        "snapshotId": "restic-snapshot-id"
      },
      "artifactPath": null,
      "errorCode": null,
      "errorMessage": null,
      "createdAt": "2026-05-05T10:00:00.000Z",
      "startedAt": "2026-05-05T10:00:01.000Z",
      "finishedAt": "2026-05-05T10:00:08.000Z"
    }
  ]
}
```

job metadata 只能包含安全 metadata，例如路径、状态、计数、snapshot id、verification result、错误码。不要把私人正文、comment、transcript、summary 正文或媒体内容写入 job metadata。

Export/import job 也走同一套 maintenance jobs：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/admin/archive/jobs/export \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"from":"2026-05-01T00:00:00.000Z","to":"2026-06-01T00:00:00.000Z"}'
```

`from` 和 `to` 都可省略，省略时导出全量 archive。导出完成后，job `artifactPath` 指向 `.tar.gz` package。导入时传这个 package path：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/admin/archive/jobs/import \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"packagePath":"/path/to/private-moments-export.tar.gz","importName":"migration-test"}'
```

导入目标总是新的 staged data directory；不会覆盖当前 data dir，也不会导入旧 device/session/sync operation runtime state。

配置 repository：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/admin/archive/repository \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"repositoryPath":"/Users/you/Library/Mobile Documents/com~apple~CloudDocs/PrivateMomentsBackup"}'
```

初始化并创建立即备份：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/admin/archive/repository/init \
  -H "Authorization: Bearer $TOKEN"

curl -X POST http://127.0.0.1:3210/api/v1/admin/archive/jobs/backup \
  -H "Authorization: Bearer $TOKEN"
```

设置每日备份：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/admin/archive/schedule \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enabled":true,"timeOfDay":"03:30"}'
```

列出/检查 snapshots：

```bash
curl -X GET http://127.0.0.1:3210/api/v1/admin/archive/snapshots \
  -H "Authorization: Bearer $TOKEN"

curl -X POST http://127.0.0.1:3210/api/v1/admin/archive/jobs/check \
  -H "Authorization: Bearer $TOKEN"
```

恢复 snapshot 到 staged data directory：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/admin/archive/jobs/restore \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"snapshotId":"snapshot-id","restoreName":"before-migration"}'
```

Promote 当前是 preparation，不是运行中热切换：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/admin/archive/jobs/promote \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "restoredDataDir":"/path/to/restored/data",
    "confirmation":"PROMOTE restored-folder-name"
  }'
```

成功后 job `artifactPath` 指向 `<dataDir>/archive/pending-promote.json`。operator 需要停止 server，按该 JSON 中的 `requiredEnv` 更新 `PRIVATE_MOMENTS_DATA_DIR` 和 `DATABASE_URL`，再重启 server。

## Admin Posts Filters

`GET /api/v1/admin/posts` 支持：

| Query | Values | Notes |
|---|---|---|
| `deleted` | `active`, `deleted`, `all` | UI 默认显示 active。 |
| `deviceId` | device UUID | 按 `createdByDeviceId` 过滤。 |
| `q` | text | 搜索 post text、comment text，并兼容搜索历史 media transcription text。Search 最多返回 100 rows，不使用 cursor pagination。 |
| `limit` | `1..100` | 默认 list limit 是 50。 |
| `cursor` | encoded cursor | 用于非 search list pagination。 |

`POST /api/v1/admin/devices/:deviceId/clean-posts` 需要：

```json
{
  "confirmDeviceName": "Device display name"
}
```

它会永久删除该 device 创建的 posts，并写入最小化的 `post_deleted` server changes，让 iOS caches 在下次 sync 时隐藏这些 posts。

## AI Periodic Reviews

Review routes 使用 device bearer token。第一版支持 `weekly` review，底层字段保留 `kind` 和 `rangeMode` 以便后续扩展月度或自定义时间段。当前 iPhone-direct 客户端的 Weekly Review 生成和设置已在本机完成；下面这些 server review routes 主要服务 legacy 客户端、历史数据检查和迁移期运维，不是普通 iPhone 使用的默认 AI 生产路径。

列出 reviews：

```bash
curl -X GET 'http://127.0.0.1:3210/api/v1/reviews?kind=weekly&limit=20' \
  -H "Authorization: Bearer $TOKEN"
```

手动生成最近 7 天 Weekly Review：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/reviews/generate \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"kind":"weekly","rangeMode":"rolling_7_days"}'
```

`generate` 和 `regenerate` 现在都会立即返回一条 review artifact；如果 `status` 是 `generating`，说明 server 已接单并转入后台生成，客户端应继续轮询 `GET /api/v1/reviews/$REVIEW_ID`，直到状态变成 `ready` 或 `failed`。这一步是为了避免 Cloudflare 之类的公网入口在长请求上提前超时。

也可以传入显式范围：

```json
{
  "kind": "weekly",
  "rangeMode": "rolling_7_days",
  "rangeStart": "2026-04-28T14:00:00.000Z",
  "rangeEnd": "2026-05-05T14:00:00.000Z"
}
```

Review generation 是面向私密生活数据的受控 AI provider 调用。server 会拒绝超过 35 天的生成范围；构建 provider 输入时最多读取 240 条 moments，超过后该 review 会以 `review_input_too_large` 失败，避免大范围自定义回顾造成成本、延迟或隐私暴露面失控。如果 provider 返回的是合法 JSON 但内容几乎为空，server 会重试并阻止空壳内容被标记成 `ready`。

对于 `provider_http_5xx`、`provider_timeout`、`provider_request_failed`、`invalid_json`、`empty_response`、`empty_review_content` 等 provider 不稳定或输出质量问题，server 会先重试 3 次。若某次返回的是“可解析但内容过稀”的 draft，server 会先保留最佳 draft，再用本地聚合信号补齐缺失 section，并在 `uncertainty` 中明确说明这是 partial local completion；只有完全拿不到可挽救 draft 时，才会退回整篇本地兜底版本。配置错误、认证错误、输入过大等问题仍会正常失败，不会伪装成成功。

Review generation 是全局互斥的：同一时刻 server 只允许一个 review 处于 `generating`。如果另一个客户端或另一个界面入口在生成期间再次调用 generate/regenerate，server 会返回当前 active generating review，而不会创建第二条 generated review artifact。若某条 `generating` review 超过 15 分钟仍未完成，server 会把它熔断为 `failed`，错误码为 `review_generation_timeout`，之后允许用户再次生成。

重新生成：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/reviews/$REVIEW_ID/regenerate \
  -H "Authorization: Bearer $TOKEN"
```

轮询单条 review：

```bash
curl -X GET http://127.0.0.1:3210/api/v1/reviews/$REVIEW_ID \
  -H "Authorization: Bearer $TOKEN"
```

删除一条 generated review：

```bash
curl -X DELETE http://127.0.0.1:3210/api/v1/reviews/$REVIEW_ID \
  -H "Authorization: Bearer $TOKEN"
```

删除 review 是幂等 soft delete：重复删除同一个已存在 review 不应该在客户端显示 `HTTP 404`。删除只软删除 generated review artifact，不会删除已经通过 `Publish as Moment` 创建出的 moment。

反馈：

```bash
curl -X POST http://127.0.0.1:3210/api/v1/reviews/$REVIEW_ID/feedback \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"type":"too_much_inference","note":"少做单条 moment 推断"}'
```

支持的标准 `type` 包括 `useful`、`too_much_inference`、`too_dry`、`missed_point`、`hide_theme`。另外，`custom_guidance` 用于保存自由输入的高优先级人工指导。

`feedback` route 现在既支持“开启”也支持“取消”某个 feedback：

```json
{
  "type": "too_much_inference",
  "enabled": true
}
```

再次点击同一项时，客户端会发送：

```json
{
  "type": "too_much_inference",
  "enabled": false
}
```

自由输入 guidance 通过 `custom_guidance` 保存：

```json
{
  "type": "custom_guidance",
  "enabled": true,
  "note": "下次请更强调这一周的主轴，少列零碎片段。"
}
```

这些 feedback 不会修改已经生成出的 review 或原始 moments，但 server 会把它们写入当前 review 的 feedback state，并重建粗粒度 `review_memory`，在后续 Weekly Review 生成时作为约束参考。标准 feedback 是 soft steering，例如 `too_much_inference` 会倾向减少推断，`too_dry` 会要求更有连接感，`missed_point` 会更强调主轴，`hide_theme` 会避免反复把同一主题放到中心；`custom_guidance` 则会作为高权重的下一次 draft 调整要求。

Review settings（legacy compatibility）：

```bash
curl -X GET http://127.0.0.1:3210/api/v1/reviews/settings \
  -H "Authorization: Bearer $TOKEN"

curl -X PUT http://127.0.0.1:3210/api/v1/reviews/settings \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"autoWeeklyEnabled":true,"publishWeeklyToMoments":false}'
```

`autoWeeklyEnabled` 默认 false。当前 iPhone-first 路径由 iOS 本机保存 `Auto-generate Weekly Review` / `Publish Weekly Review` 偏好并本机生成 review；新 iOS 客户端不再通过这个 endpoint 拉取或写回设置。Mac server 的自动 review setting 只保留为历史/运维兼容路径；默认 runtime 不启动 `ReviewScheduler`，只有显式设置 `PRIVATE_MOMENTS_ENABLE_LEGACY_REVIEW_SCHEDULER` 才会让 server 重新执行旧的 Sunday-evening 自动生成。
