# Card deletion — 2026-10-05

Every saved content card exposes its Delete action through an existing Trash control or visible More menu. Added the missing actions for live notes, saved comments, Search results, automatic hour groups and daily action groups. Imported batches keep one Trash action. [Action coverage](action-coverage.json) records each card family, deletion scope and recovery path.

Live notes move to persistent Recently Deleted and support Undo. Restore preserves later saved or pending text by refusing an occupied note. Saved comments delete by exact ID and support additive Undo without losing later replies, unfinished composer text or task plans. Group confirmations freeze visible capture IDs, preserving hidden items, tasks and captures arriving afterward. Permanent deletion is separately confirmed. Original source files remain at their original locations.

## Verification

The affected 24-suite campaign and scoped rechecks validate 24 distinct suites across the campaign. Ten suites passed on the final production source; the new native deletion fixture completed all 152 checks and cleanup. The earlier broad campaign differs by two accessibility-only source changes in comment and removed-note cards, with unchanged deletion business logic. This was not a full run of all 124 registered suites. Initial failures and exact rechecks are preserved under runs/ rather than overwritten. See [verification.json](verification.json) for the per-suite evidence and source scope.

Native flows cover real More-menu dispatch, confirmations, Cancel, Delete, Undo, Recently Deleted Restore/permanent deletion, Project notes sheets, preservation of unsaved comment drafts, and deletion while new automatic captures arrive. Workspace interactions, project cards, search, tasks, backup/restart, failed-save rollback and stress coverage also passed. Durability exercised 1,000 seeded records, 320 mixed operations, 25 restart comparisons and four real SIGKILL boundaries; flow/action stress completed 11,674 checks.

The deterministic Xcode project check and 32 packaging unit tests passed. A fresh unsigned ARM64 App Store Release compiled and passed packaging checks. Its actual bundle metadata is 0.4.33 (88), com.dabin.mac, with production fingerprint `6b013ca1385c4aaf1d837e924e12eaa9bbeeba5ad3544fea2ede31b88f83d909`. The executable SHA256 and unchanged build inputs are verified in [store-candidate-receipt.json](store-candidate-receipt.json). This is compilation evidence, not a signed archive or upload.

## Remaining limits

The earlier strict zoom latency failure and native framework table warnings remain open; they were not retested or claimed fixed by this change. Human VoiceOver/physical inputs, extended OS/hardware soak, distribution sandbox runtime, signing, installation and Apple processing remain unverified. TestFlight publication still requires the current source-guarded human signing handoff recorded in [publication status](../testflight-internal-0.4.33-2026-10-05/status.json).

## Renders

Fictional isolated fixtures were visually inspected: [Project notes](renders/project-note-delete.png), [Search notes](renders/search-note-delete.png), [saved comments](renders/comment-delete.png), [hour group](renders/hour-delete.png). No personal captures, clipboard contents or private signing material are included.
