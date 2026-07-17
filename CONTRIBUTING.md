# Contributing

Thanks for taking an interest in Ownlight.

## Before Opening A Change

- Keep the iPhone app useful without iCloud, a server, or network access.
- Do not add public social features, tracking, ads, or developer-hosted user accounts without an explicit product decision.
- Never commit private timeline data, media, credentials, device dumps, Apple signing material, or local configuration.
- Prefer focused changes that follow the existing SwiftUI, SQLite, CloudKit, and documentation boundaries.

## Local Verification

```bash
npm install
npm run doctor:release
npm run doctor:app-store
npm run verify:ios:low-impact
git diff --check
```

The low-impact iOS verification does not launch Simulator. Use Simulator only for visual changes, and never use real private data in public screenshots or fixtures.

## Pull Requests

Include a concise description, verification evidence, and any privacy, migration, CloudKit, or recovery implications. Changes to sync semantics, SQLite migrations, media storage, backup/restore, authentication, or cross-device behavior need explicit design and recovery notes.

Security issues should follow [SECURITY.md](SECURITY.md), not a public issue.
