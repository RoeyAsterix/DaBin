Historical working draft, superseded by ../README.md and final evidence receipts.

Draft for the coordinating QA task. The latest full run finished 107/110 passing, with a DailyCapture fixture failure, an ExplorerKeyboard production failure, and a deliberately terminated performance suite. The Daily background-readiness patch has been applied and awaits verification; the keyboard repair is in progress. Do not present this draft as a completed QA receipt.

Verified changes and focused evidence:

- Deleting an open attachment now prunes its deleted history entry and restores the surviving task's own draft, focus and viewport. NavigationHistory passed 47 checks, including active attachment deletion and deletion after navigating elsewhere.
- Task and note composers, task titles and comment drafts now have explicit native focus identities. The original production task editor lost its selection after a Settings round trip. The repaired DailyCapture fixture runs a real AppKit event loop and passed 181 checks, including four actual mounted editor round trips. The later full-run synthetic drop failure remains open; this earlier pass does not clear it.
- List insertion protection now survives a delayed matching layout before its bounded expiry. History restoration rejects callbacks from an obsolete view/context. The focused Search suite passed 105 native checks and ViewportLifecycle passed 10 lifecycle checks.
- Workspace zoom restores an item offset using the active scale, chooses an appropriate visible viewport for keyboard zoom, and ignores detached scroll surfaces. Weekly column widths use zoom-aware limits. WorkspaceZoomLayout passed 80 checks.
- New text captures, authored notes, tasks and recurring successors commit their already-ready text preview state once. Scoped-storage tests verify that normal preview processing adds no redundant save/publication while legacy preview failures still repair durably; 31 checks passed.
- Product, task, window and caption fixtures now assert current browser-history and Extended View behavior. These corrections retain dirty-draft, drag-payload and editor-protection checks. ProductFoundation passed 77, TaskState 131, Window 188, WorkspaceWindow 252 and CaptionDrag 139 focused checks.

Evidence boundaries:

- The frozen baseline was 102/109 passing, with seven failed suites. The first focused repair run was 11/12 passing; its remaining real-focus startup failure was fixed and checked separately. Preserve those failure receipts. Do not sum repeated suite counts as distinct checks, or substitute selected-suite passes for the pending final full run.
- The change inventory currently records 26 paths: 12 production files, 13 test files and one QA runner. Every recorded after-hash matched the files when this draft was prepared. The DailyCapture after-hash was refreshed after its background-readiness repair. Refresh affected hashes after further changes.
- Baseline offline project generation, Python tests, static packaging, metadata and whitespace checks exited successfully. They do not establish signed distribution, installation, App Store submission, sandbox enforcement or minimum-macOS runtime compatibility.
- Recorded native runs use ARM64/macOS 26.6.2 with fictional local stores and private test pasteboards. Mouse/trackpad gesture coverage is synthetic; actual device settings/drivers and external application drag completion are not established here.
- The 60-second, 5,000-record fixed-data experiment passed its correctness checks but retained performance warnings: synthetic input-to-layout p95 70.3 ms, steady-zoom main-runloop p95 77.3 ms, maximum 109.8 ms. This is not physical input-to-display latency or a smoothness acceptance result. Its RSS checkpoints stabilized near 246 MB after warm-up; they do not prove an absence of leaks. The earlier 30-second arrival run also retained timing and memory warnings. Neither is a ten-minute run.
- NSTableView reentrancy warnings remain recorded. The captured stack is in AppKit/SwiftUI estimated-row-height and key-view setup during window ordering, with no DaBin restoration callback on that stack. That attribution does not establish harmlessness or a fix.
- This evidence directory does not establish that this QA candidate was installed, signed, submitted or published.

Applied fixture repair, awaiting verification: `daily-background-readiness-proposed.patch` waits for a departing composer to unmount and explicitly establishes actual native background focus before synthetic Daily drops. It preserves all checks that reject capture drops while an editor is intentionally focused. Rerun the affected native suite in the coordinated QA pass and include its new receipt.
