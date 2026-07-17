# Security And Privacy

Ownlight is designed for private, local-first personal use. The current product path is iPhone local storage plus optional iCloud/CloudKit private sync. Legacy Mac server/admin code remains in the repository for compatibility, diagnostics, archive, and maintenance; do not expose that legacy server directly to the public internet unless you have added a stronger security boundary yourself.

## Recommended Boundary

- Keep ordinary product use on `This iPhone` and optional iCloud.
- CloudKit data lives in the user's private iCloud database under their Apple Account.
- The app does not require a separate Ownlight account system for CloudKit sync.
- Tailscale, Cloudflare Tunnel, and other VPN/tunnel products are optional network layers for legacy server/admin or local gateway access, not required Ownlight components.
- If you use Cloudflare Tunnel or another public HTTPS endpoint for a legacy server or local gateway, add your own access controls and avoid exposing the full Admin UI without additional protection.
- Keep legacy `HOST=127.0.0.1` for purely local development.

See `docs/NETWORKING.md` for the supported configuration model.

## Secrets

Never commit these files or values:

- `server/.env`
- `server/data/`
- SQLite database files
- Media uploads or thumbnails
- External AI provider API keys
- Real device container dumps

Use `server/.env.example` as the only committed environment template.

## AI Generated Metadata

AI media summaries and periodic reviews are optional generated metadata. The default product path is iPhone-direct: audio/video uses iPhone on-device transcription first, then sends the private local transcript to the user's configured text-analysis provider when AI generation is enabled. Periodic reviews are generated from a bounded local input pack that can include moment text, comments, safe metadata, tags, and ready audio/video summary metadata. Mac server AI routes and environment variables are retained for historical compatibility and diagnostics, not as the default credential or generation layer.

This means:

- iPhone provider API keys stay in the iPhone Keychain and must not be synced to iCloud, legacy Mac server, export packages, or tracked files.
- Legacy Mac/server provider credentials, if used, stay in `server/.env`.
- Prepared media assets can enter CloudKit private sync when `iCloud Sync` is enabled. Raw transcripts and provider credentials must not.
- Private transcript text can be sent to the configured AI provider when summary generation is enabled.
- Moment text, comments, and ready summary metadata can be sent to the configured AI provider when periodic review generation is enabled.
- Turn off `AI & Analysis` or remove provider credentials if you do not want external AI calls.
- iPhone archive exports are not encrypted in the first implementation. They may contain private text, comments, generated summaries, reviews, check-ins, and media, but must not contain API credentials, provider keys, provider configs, or private transcript text; transcript data is limited to metadata such as status and length.

Operational logs should record IDs, status, provider/model names, error codes, and input lengths only. They should not include transcript, summary, review, post, or comment bodies.

## Backup And Restore

The iPhone-first recovery path is iCloud plus local archive export/import for empty-library recovery drills. Legacy Mac Admin Archive uses restic snapshots for historical/server archive recovery. The project creates a `.private-moments-restic-key` next to the configured repository so the owner does not need to remember a separate backup password.

Security implication:

- The repository and `.private-moments-restic-key` together are enough to restore the archive.
- iCloud Drive can be used as a user-selected folder, but the app does not provide a separate encrypted cloud-backup product.
- Do not publish or share the repository, key file, restored data directories, `archive/pending-promote.json`, or maintenance job artifacts if they include local paths.
- Backup/restore logs and job metadata should contain paths, IDs, counts, statuses, and error codes only, not private post text, comments, transcripts, summaries, or media bodies.

## Reporting Issues

Do not include private timeline content, media files, credentials, device names, CloudKit operation IDs, tunnel IDs, or legacy server logs with sensitive payloads in issue reports.

Report security issues privately through [GitHub Security Advisories](https://github.com/Popcornnnnnnnn/ownlight/security/advisories/new) or email `support@popcornnn.xyz`. Please do not open a public issue for a vulnerability.
