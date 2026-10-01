# DaBin 0.4.6 (61) - reviewed testing candidate

## Included in this candidate

- Inbox has a visible Day / Week calendar toggle, alongside the all-date To organize queue. Empty dates stay hidden in Week; date browsing, filters, drafts and weekly search/export remain available.
- Quiet Orbit uses the supplied metallic robot design, seven small positions around the built-in camera island, quiet idle, ten capture reactions and readable success/count feedback. Existing paste/drop and external-display behavior are retained.
- Visible trash controls, four-corner resizing, cross-display movement and responsive Explorer/detail previews remain included.

## Review fixes

- The robot's saved/error receipt badge now follows it when it moves to another island position.
- Recovering a comment draft after a completed or snoozed reminder no longer reinstates the old reminder. Legacy drafts and pending countdown edits remain recoverable.
- Explicitly shelved task attachments remain visible. Shelf browsing and ZIP exports share project ownership, including inherited parent projects; unsupported refile/reattach actions are hidden on attachments.
- Public packaging now binds both the main app and embedded updater executable to the source-bound build receipt before signing. Missing or changed updater bytes stop packaging.
- The resize interaction fixture now uses AppKit's actual whole-point window placement; exact size and opposite-edge assertions remain intact.
- The one-page guide covers Inbox, Today, Workspace, Explorer, reusable clipboard content, task planning, focus and archive recovery. The bundled privacy text explains optional clipboard retention and screen-capture exclusion limits accurately.

## Verification and distribution

See [review and QA evidence](qa/release-review-2026-10-01/README.md). Local installation is separate from a distributable installer.

The testing release is **not yet published**. A Developer ID certificate is installed, but the documented `DaBin-notary` credential profile is missing and signing did not complete during this session. Apple notarization, stapling, Gatekeeper acceptance, public ZIP verification and signed-upgrade migration must pass before this candidate is offered to another Mac. The current public GitHub release remains 0.3.18; its old download links do not contain these changes.
