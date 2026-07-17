# Agent Notes For Private Moments

## Scope

Work only inside `private-moments/`. Do not work directly in the parent collection root unless the user explicitly asks.

## Product Shape

Private Moments is a private, local-first personal timeline:

- iOS app is the primary capture and browsing surface.
- iPhone local SQLite is the default source of truth. The app must remain useful without iCloud, a server, or network access.
- iCloud / CloudKit private database is the current opt-in cross-device sync direction.
- `server/` and `admin/` remain in the repository as legacy compatibility, archive/diagnostics, API reference, and maintenance workspaces. Do not describe them as the default product runtime.
- Main timeline simplicity is a design constraint. Put low-frequency controls in toolbar menus, swipe actions, detail views, or settings rather than crowding the timeline.
- New settings, monitoring, diagnostics, and safe repair controls should prefer iOS Settings / diagnostics first. Legacy Admin surfaces are only for low-frequency compatibility or maintenance tasks.
- App-facing UI copy should stay primarily English unless the user explicitly requests localization.
- Timeline date/month context should stay light: use `MomentDateFormatter` for English human-friendly labels and a temporary floating month hint while scrolling.
- Timeline delete should use a centered alert, not a position-based `confirmationDialog`; keep trailing delete full-swipe disabled to avoid list jumps.

## Current Architecture

- `ios/PrivateMoments`: SwiftUI app named `Ownlight`.
- `ios/PrivateMoments/CloudKit`: iCloud / CloudKit private sync implementation.
- `server`: legacy Node.js, TypeScript, Fastify, Prisma, SQLite, and local file storage workspace.
- `admin`: legacy React + Vite Admin UI served by Fastify after build.
- `transcription-gateway`: optional authenticated OpenAI-compatible transcription helper.
- `shared/openapi.yaml`: legacy API contract.
- `shared/sync-protocol.md`: legacy sync semantics.
- `docs/INTEGRATION-GUIDE.md`: API usage and route reference.
- `docs/OPERATOR-RUNBOOK.md`: setup, operations, iPhone install, troubleshooting.
- `docs/HANDOFF.md`: current working state and follow-up notes.
- `docs/ADMIN-MIGRATION.md`: Mac Admin minimal surface and migration plan.
- `docs/WORKFLOW.md`: project workflow, documentation ownership, verification levels, and closure rules.

## Persistent Workflow

Use `.planning/` as the structured source for current project facts, requirements, decisions, roadmap, and milestone state. Use `docs/` as the stable human-facing documentation set.

The old `.planning/_legacy-gsd/` tree has been removed from the active checkout. `.planning/LEGACY-GSD-ARCHIVE.md` records the cleanup boundary. Do not recreate a second planning system at the repository root; recover old details from git history only when audit archaeology is explicitly needed.

Human-facing documentation under `docs/` should be primarily Chinese. Keep command names, API routes, field names, filenames, code symbols, and established app UI copy in English where that is clearer or source-of-truth. `AGENTS.md` may stay English-first because it primarily serves agents and tooling.

Work defaults to lightweight continuous maintenance. Upgrade to milestone/slice planning before implementation when a change can affect sync semantics, SQLite schema migrations, media storage or recovery, backup or restore, auth/security boundaries, cross-device behavior, or real-device recovery.

Every non-trivial change must close with:

- A concise change summary.
- Fresh verification evidence from the current session.
- Known issues, limitations, or next steps.
- Updates to affected `.planning` fact-source files.
- Updates to affected human-facing docs when usage, operation, architecture, or product behavior changed.
- A git commit after the feature or fix reaches a verified checkpoint, even if human UAT is still pending. Do not leave multiple completed features or milestone slices piled up as uncommitted changes; use a clear checkpoint commit message and note any remaining UAT in the docs/final response.

Keep docs single-purpose:

- `docs/PRD.md`: product intent, user stories, goals, and non-goals.
- `docs/TECH-DESIGN.md`: architecture, data flow, system design, and long-lived technical constraints.
- `docs/OPERATOR-RUNBOOK.md`: setup, operation, verification, troubleshooting, and real-device checks.
- `docs/INTEGRATION-GUIDE.md`: API route usage and integration reference.
- `docs/HANDOFF.md`: current working state, recent important fixes, known risks, and next sensible work.
- `docs/DESIGN-PRINCIPLES.md`: UI and product design principles.
- `docs/ADMIN-MIGRATION.md`: Mac Admin minimal surface, migration boundary, and shrink order.
- `docs/WORKFLOW.md`: how work is planned, verified, closed, and documented.
- `docs/RELEASE-CHECKLIST.md`: App Store and public-source release gates.
- `docs/OPEN-SOURCE-READINESS.md`: current open-source blockers, privacy review, and release risk assessment.
- `SECURITY.md`: public-facing security, privacy, AI provider, and secret-handling boundaries.

## Commands

Install and prepare:

```bash
npm install
```

Low-impact iOS verification that does not launch Simulator:

```bash
npm run verify:ios:low-impact
```

Run iOS simulator with reusable demo data for screenshots and UI review:

```bash
npm run ios:simulator:demo
npm run ios:simulator:cleanup
```

For visual iOS work, follow `.planning/SIMULATOR-UAT.md`: use an iPhone 13 Pro-class simulator, verify the real Simulator UI with screenshots, keep the reviewed screen open for UAT, then shut down simulators and quit Simulator.app when done. Do not use Simulator for non-visual verification unless the user explicitly asks for it.

Build checks:

```bash
npm run verify:ios:low-impact
cd ios && xcodegen generate && xcodebuild -project PrivateMoments.xcodeproj -scheme PrivateMoments -destination generic/platform=iOS -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Install to real iPhone after iOS changes:

```bash
npm run ios:device
```

The real-device script uses `PRIVATE_MOMENTS_DEVICE_NAME`; keep personal device names in ignored `.env.local`.

Legacy server/admin checks, only when those workspaces change:

```bash
npm run server:typecheck
npm run server:build
npm run admin:build
curl -fsS http://127.0.0.1:3210/api/v1/health
```

## Runtime Facts

- Legacy development server port: `3210`.
- Public default bundle id: `dev.privatemoments.app`; local owner builds can override it through ignored iOS config.
- App display name: `Ownlight`.
- Current legacy server schema version: `19`.
- Read the development password from `server/.env`; do not hard-code it into reusable docs or code.
- Default iOS Settings path is local iPhone storage plus optional `iCloud`. Legacy server URL settings should stay out of the ordinary product path.
- Get the current Mac Tailscale IP with `tailscale ip -4` only for legacy private-network diagnostics, not as a reusable public default.

Do not hard-code personal Cloudflare or Tailscale values into reusable code unless the user asks for a personal-only shortcut. Prefer ignored `.env.local` or script/env overrides.

## Sync, CloudKit, And Media Notes

- iCloud / CloudKit private sync is opt-in under `Settings > Data Storage > iCloud`.
- CloudKit ordinary Moment create/update/delete enqueue only when `iCloud Sync` is enabled.
- New media Moments enqueue the parent `.moment` upsert, `.media` metadata upserts, and `.media` asset uploads.
- CloudKit sync triggers on app bootstrap/foreground, enabling the switch, 5-second local content/media debounce, 1-second preference debounce, explicit `Sync Now`, and foreground low-frequency polling around every 15 seconds.
- CloudKit transient failures retry with delayed backoff. Manual `Sync Now` is a diagnostic fallback, not the default daily workflow.
- Legacy sync endpoint: `POST /api/v1/sync`.
- Client operation types currently used: `create_post`, `update_post`, `insert_ai_title`, `update_post_favorite`, `delete_post`, `create_comment`, `delete_comment`, `update_media_transcription` for legacy clients, `upsert_tag`, `archive_tag`, `restore_tag`, `delete_tag`, `merge_tag`, `upsert_tag_alias`, `delete_tag_alias`, and `set_post_tags`.
- `opId` is idempotent per device.
- `lastSyncCursor` must only advance after all returned server changes are applied.
- iOS has recovery logic via `didApplySyncRecoveryV1`; if local posts are empty, it requests cursor `0`.
- iOS must parse ISO8601 with fractional seconds; failing to parse and still advancing cursor caused data loss symptoms on 2026-04-29.
- Comments are independent local-first entities via `create_comment` / `delete_comment`; comment rows do not show per-comment sync badges.
- Media upload is multipart via `POST /api/v1/media/upload`; media `kind` supports `image`, `video`, and `audio`, with `thumbnail` used for video posters.
- iOS compresses display/upload images with max edge `1600px` and JPEG quality `0.72`; upload-time compression also covers old pending files.
- iOS prepares videos as 720p H.264 MP4 with poster thumbnails, records audio as AAC/M4A, and stores audio/video duration metadata.
- New iOS clients do not run Speech framework transcription, request speech permission, upload `transcriptionText`, or show transcript fallback/status in the timeline. `update_media_transcription` remains only for old-client compatibility and historical metadata.
- AI media summaries are generated metadata for local audio/video media. The current default path is iPhone-direct: iPhone transcription creates a private local transcript, then the user-configured text-analysis provider creates summary/title/tag artifacts. Provider credentials live in the iPhone Keychain and do not enter CloudKit, export packages, or legacy server storage.
- Legacy Mac/server generated summaries remain historical compatibility artifacts only. Do not reintroduce Mac/server AI generation as the ordinary path.
- New AI summaries use prompt version `media-summary-v4` and a native document block model (`documentTitle`, `oneLiner`, `documentBlocks`) rendered by iOS as Markdown-like headings, paragraphs, lists, and `AI suggested` callouts. For recognizable non-empty audio/transcript notes, v4 should produce a title of at most 40 characters; the server can fall back from `oneLiner` if the provider returns a blank or overlong title. v4 also sends the active topic tag vocabulary to the provider and the server reuses existing topic tags or aliases before creating new AI topic tags. Legacy `overview`/`keyPoints`/`sections` remain for compatibility; old summaries are not batch-regenerated.
- New audio moments may auto-insert the first ready summary title into `post.text` as a top `##` heading through `insert_ai_title`, if `AI Title Auto-Insert` is enabled and the user has not already written a leading `# ` or `## ` title. This operation must not set user edited metadata and must not write summary bodies into post text.
- Moment body remains Markdown source `String`. Composer/Edit are source editors; read-only Timeline/Detail/Day Review rendering supports broader safe system Markdown, with advanced math-source/remote-image/raw-HTML switches buried under Settings > Appearance > Markdown.
- Smart Tags are first-class synced metadata. Primary tags are legacy compatibility only and must not appear in ordinary Composer, Timeline Filter, Detail tag editing, or Settings > Tags. Topic tags are grouped under fixed Areas. AI topic tags must prefer existing active topic tags/aliases before new tag creation, including obvious narrower variants such as `HTTPS 中间人攻击` -> `中间人攻击`.
- The `Save to Moments` Share Extension is intentionally thin: it writes supported shared items into the App Group import inbox and opens the main app composer, which owns editing, media preparation, draft handling, database writes, upload, and sync.
- AI summary processing statuses are `transcribing`, `summarizing`, `ready`, `failed`, and `deleted`. Timeline only shows `Summary ready` for ready summaries; progress/failure diagnostics belong in Settings > Storage & Diagnostics.
- Normal AI summary logs must not contain private transcript or summary bodies; record IDs, provider/model, status, error codes, and input lengths only.
- Failed legacy sync or media upload work schedules delayed automatic retry: 5s, 20s, 60s, 120s, then 300s.
- Remote media cache recovery uses `POST /api/v1/media/batch-download`, defaulting to `thumbnail` variant as base64 JSON for image thumbnails and video posters. Full audio/video files download on play.
- Server thumbnails are generated with `sips`, max edge `800px`, with oversized thumbnails regenerated.
- `GET /api/v1/admin/status` returns legacy admin counts plus storage, `sync.latestServerChangeVersion`, and `aiSummaries` diagnostics. Treat this as an advanced compatibility/maintenance signal; ordinary Settings should not reintroduce Mac Server as a default product dependency.
- Legacy server-originated AI summary changes can exist for historical data. If legacy summaries look stale, compare iPhone `lastSyncCursor` with server `MAX(server_changes.version)` or admin status `sync.latestServerChangeVersion`.
- AI token usage is recorded server-side in `ai_usage_events` for media summary, weekly review, and tag fallback provider calls. Store only privacy-safe metadata and token counts: feature, subject type/id, provider/model, promptVersion, status, duration, provider usage, cached input tokens, local estimates, and error codes. Do not store transcript, prompt, review input JSON, generated summary/review bodies, or provider raw responses.

## Code Organization

The project has already started splitting large files:

- `TimelineStore` is split across `TimelineStore+Session`, `+Mutations`, `+Sync`, `+SyncRetry`, `+ServerChanges`, `+Media`, legacy `+Transcription`, and `+Payloads`.
- `LocalDatabase` is split across `+Schema`, `+Records`, `+Timeline`, `+Sync`, `+StorageStats`, and `+SQLite`.
- `TimelineView` is split into `TimelineView`, `TimelineRow`, `TimelineCommentsSection`, `TimelineCommentInputBar`, `MomentDateFormatter`, `MediaGalleryView`, and `ZoomableLocalImage`.
- `CheckInsView` is now split across `CheckInsView`, `CheckInHistoryViews`, `CheckInMediaViews`, and `CheckInEntryDetailView`; keep pushing extraction along those seams instead of re-growing the main file.
- `MomentDetailView.swift` is now primarily the read-only detail surface; edit flow and editable media helpers live in `EditMomentView.swift`. Keep future edit-mode changes on that side instead of re-expanding the detail file.
- `admin/src/App.tsx` is now split with `ArchiveManager`, `adminShared`, and `adminFormat`; continue slimming along overview/posts-specific seams instead of re-inlining archive or shared media helpers.
- `server/src/api/admin.ts` is now mostly route wiring; diagnostics and route helper logic live in `admin-diagnostics.ts` and `admin-helpers.ts`. Keep future admin work split along that boundary instead of re-growing the route file.
- `server/src/api/admin-maintenance.ts` is now only the top-level registrar; maintenance job state routes live in `admin-maintenance-state-routes.ts`, archive operator routes live in `admin-archive-routes.ts`, and shared auth/archive helpers live in `admin-maintenance-helpers.ts`. Keep future archive and maintenance work split along those seams instead of re-growing the route file.
- `server/src/api/media.ts` is now mostly route wiring; thumbnail generation, upload-field parsing, and media record upsert logic live in `media-storage.ts`. Keep future media IO logic split along that boundary instead of re-growing the route file.
- `server/src/api/sync.ts` is now mostly sync route wiring and server-change response shaping; operation replay/dispatch lives in `sync-route-helpers.ts`, with post/comment/media apply logic in `sync-post-operations.ts` and tag apply logic in `sync-tag-operations.ts`. Keep future sync work split along those seams instead of re-growing the route file.
- Audio/video support lives in `PreparedMomentMedia`, `MediaPreparation`, `AudioRecorderController`, and `MediaPlaybackCenter`. Server-side AI summary support lives under `server/src/ai/` plus `server/scripts/local-transcribe.py`.
- Share Extension support lives under `ios/ShareExtension/` and shared import helpers under `ios/Shared/`.
- Moment body Markdown rendering/editing lives in `MomentTextMarkdown`, `MomentTextView`, `MarkdownTextEditor`, and `PlainTextListContinuation`.
- Smart Tags support lives in `server/src/tags/`, `ios/PrivateMoments/Persistence/LocalDatabase+Tags.swift`, `TagManagementView`, and tag-related sync code.
- Storage diagnostics live in `ios/PrivateMoments/Models/StorageStats.swift`, `ios/PrivateMoments/Views/StorageSettingsView.swift`, and `server/src/storage/stats.ts`.

Before expanding large areas, prefer continuing these splits:

- `admin/src/App.tsx` (especially `Overview` and the dormant posts inspector path)
- `server/src/api/admin.ts` / `admin-helpers.ts` / `admin-diagnostics.ts`
- `server/src/api/admin-maintenance.ts` / `admin-maintenance-state-routes.ts` / `admin-archive-routes.ts` / `admin-maintenance-helpers.ts`
- `server/src/api/sync.ts` / `sync-route-helpers.ts` / `sync-post-operations.ts` / `sync-tag-operations.ts`
- `server/src/api/media.ts` / `media-storage.ts`
- `ios/PrivateMoments/Views/MomentDetailView.swift` / `EditMomentView.swift`

## Verification Habit

After server changes:

```bash
npm run server:build
curl -fsS http://127.0.0.1:3210/api/v1/health
```

After iOS changes, rebuild and install to the real iPhone when feasible:

```bash
npm run ios:device
```

For real-device data verification, copy the app Library container with `xcrun devicectl` and inspect:

```sql
SELECT COUNT(*) FROM local_posts;
SELECT COUNT(*) FROM local_posts WHERE deletedAt IS NULL;
SELECT COUNT(*) FROM local_media WHERE localCompressedPath <> '';
SELECT COUNT(*) FROM local_comments WHERE deletedAt IS NULL;
SELECT kind, transcriptionStatus, COUNT(*) FROM local_media WHERE kind IN ('audio', 'video') GROUP BY kind, transcriptionStatus;
```

For image recovery, `missing_visible_media` should be `0`; see `docs/OPERATOR-RUNBOOK.md` for the full query.
