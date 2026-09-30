# DaBin product review — 30 September 2026

[Completed report, before/after views, verification and limitations](REVIEW-RESULT.md).

## Scope and method

This review evaluates the native macOS capture, retrieval, task and workspace flows. It uses fictional records in separate application bundles, archives, preference suites and pasteboards. Synthetic experiments never seed the user's capture archive. Final local installation uses a separate verified backup and preservation check, documented in the completed report. Production screenshot privacy is unchanged; only the review wrapper permits screenshots of itself.

The baseline is the frozen build-50 testable module. Its source/resource hashes are in `baseline-provenance.json`. Forty baseline production-view renders cover compact/expanded widths, light/dark appearance, task attachments, the reminder clock, source icons and the robot frame. `baseline/live-review-events.json` records route and save events from the live native wrapper.

The wrapper hosts production SwiftUI/AppKit views but uses a standard titled window and fake permission, notification and update services. It therefore verifies content layout and ordinary native controls, not the installed application's notch placement, Spaces, native edge-resize policy, live screenshot exclusion, real notification delivery or installation/update behavior. Those require the dedicated production tests and controlled app checks.

## Baseline findings

| Priority | Observed issue | Evidence and consequence | Required change |
| --- | --- | --- | --- |
| High | Header absorbs unused height | In the live 400 × 732 outer window, approximately 312 points separate the board top and first card. A resize to roughly 400 × 465 leaves only a sliver of feed. The flexible drag handle has a minimum height but no fixed maximum. | Constrain the drag area; test the actual accessibility control envelope at compact and expanded sizes. |
| High | Search discards collection context | Library → Media → search “launch” → Back returns to Library with All selected. Observed through native accessibility actions. | Snapshot and restore route and type filter; preserve project and pin selection. |
| Medium | Calendar history also serves as the start screen and task list | An attached note appears as a receipt immediately above its parent task. Accurate activity history competes with actionable work. | Separate Inbox triage, Today planning and Workspace retrieval; keep calendar history as Activity. |
| Medium | Starting a note requires a menu detour | Add → New note → Save takes three button actions plus typing. | Place a lightweight composer in Inbox while keeping the existing detailed editor. |
| Medium | Expanded mode retains the tall header | Increasing width does not recover enough working space. | Keep chrome bounded independently of window height; use extra width for content. |
| Low | Similar navigation concepts have different names | Library/Follow-ups/Today mix storage, action and calendar metaphors. | Give the three primary destinations stable names and distinct purposes. |

Useful behaviors to preserve: new-note autofocus; conversion that retains source content; attachment paste into a task; a working hour/minute reminder mode; source application icons; accessible control labels; reversible removal; local archive ownership.

## Observed baseline interactions

These are counts of performed accessibility button actions and keyboard commands, not physical mouse telemetry. Text entry is listed separately. The event logger cannot count every accessibility press, because those can bypass `NSWindow.sendEvent`.

| Workflow | Observed actions | Result |
| --- | --- | --- |
| Search all captures | 1 field click + query entry | Results update immediately; no Return needed. |
| Save a new note from the primary view | 3 clicks + typing | Saved and returned to the day. |
| Turn the new note into a task | 1 click | Same content opens in task details. |
| Add text to a task | 1 Command-V shortcut | Private fixture clipboard becomes one task attachment. |
| Add a default 30-minute countdown | 4 clicks | Open Reminder → enable → Countdown → Save; absolute deadline persisted. |
| Enter Library | 1 click | Archive opens. |
| Return from search to Media selection | 1 Back click, then 1 repair click | Filter was lost; restoring it required selecting Media again. |
| Hide and reopen wrapper | 1 Hide + 1 fixture Show | Route preserved by wrapper. This is not a production robot-reopen test. |

Source-derived estimates, not live measurements: More → Export → choice is three menu actions; switching between three visible primary tabs is one action; placing a note directly in an Inbox composer should avoid the Add-menu/editor detour. Command-V already takes one shortcut and does not need an invented reduction.

## Performance evidence and limits

Baseline idle sampling is in `baseline/idle-samples.json`: four `ps` observations over nine seconds report 0.0% CPU, 140,048 KiB RSS (about 136.8 MiB), and unchanged cumulative CPU time while the synthetic board is visible and stationary. This is a brief local observation, not a power benchmark or a guarantee for a large archive.

Latest data-path and live-layout timings, restarted scratchpad persistence, and the repaired search-return flow are recorded separately in `latest/RESULTS.md`. The performance harness uses 10,000 generated text records and production search/repository code. It does not measure network previews, OCR, image decoding or GPU presentation. The GUI tool's initial app-selection delay is excluded from startup timing because it includes automation infrastructure.

## Review artifacts

- `baseline/`: frozen native renders, live event record and idle samples.
- `harness/ReviewFixture.swift`: baseline live wrapper.
- `harness/LatestReviewFixture.swift`: current wrapper with seeded planning and workspace data.
- `harness/ReviewPerformance.swift`: synthetic 10,000-record data-path measurement.
- `harness/build_fixture.py`: builds a separate signed review bundle against an already compiled test module; never compiles or installs production DaBin.
- `alternatives.md`: navigation alternatives and feature trade-offs.
- `latest/`: current evidence, populated only after actual verification.

The accompanying WorkInbox and HeaderInteraction suites now cover the new navigation meanings, return from global/scoped search, project/pin context, and bounded header geometry. Results are reported after the final shared module is compiled; editing an assertion is not verification.
