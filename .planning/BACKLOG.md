# Backlog

<!-- Append-only. Record deferred engineering work here when a decision is intentionally postponed.
     Do not leave future work only in chat or long-form handoff text. -->

## v0.1 Release Triage

2026-06-08: no active item in this backlog blocks App Store v0.1 preparation. `B001` and `B002` are post-v0.1 enhancement candidates. Release readiness work is tracked in `docs/RELEASE-CHECKLIST.md`, `docs/APP-PRIVACY-DATA-INVENTORY.md`, and `docs/APP-STORE-READINESS.md`.

| ID | When | Area | Item | Trigger | Notes |
|---|---|---|---|---|---|
| B001 | 2026-05-30 | local transcription | SenseVoice/FunASR local transcription adapter | Consider after the MLX local transcription gateway is proven in real-device UAT and Chinese/Cantonese accuracy or latency is still not good enough. | Keep it as a second adapter behind the same gateway API. Do not add it to the first MLX gateway slice. |
| B002 | 2026-06-07 | CloudKit sync | Push-assisted near-realtime sync | Consider after M017 CloudKit cross-device UAT closes for the current debounce/polling sync model and the remaining release-critical gates are stable. | Use CloudKit subscriptions plus silent remote notifications only as wakeups, then pull changes through the existing sync runner. Keep foreground polling and `Sync Now` as fallbacks because silent pushes can be delayed, coalesced, or dropped. Do not market this as hard realtime. |
