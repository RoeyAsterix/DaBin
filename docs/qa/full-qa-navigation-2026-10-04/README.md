# DaBin full QA and repair cycle — 4 October 2026

**Completed:** 110 native suites passed against the current reconciled source; 90 Python tests, 39 media checks and two Xcode smoke tests passed. Direct Release and unsigned Store Release builds pass their applicable checks. The repaired local app is installed and running. Large-archive zoom performance remains below the proposed target.

## Repairs

- Preserve a surviving task’s own history, draft, focus and viewport when its displayed attachment is deleted. Background deletion does not navigate away from another view.
- Restore the actual native editor and caret/selection after navigation for task and note composers, task titles and comment composers. Stable typed editor regions avoid matching user text or translated labels.
- Keep Search and Explorer in place when incoming captures trigger slow native list layout. Start the bounded settling interval after the matching update, cancel on user input, and prevent intermediate offsets from replacing saved history.
- Keep arrow-key selection in control of Explorer scrolling. Selection changes cancel insertion anchoring but do not replay a previous navigation offset.
- Restore a project’s selected item when switching projects, while Back/Forward restore their own saved item and offset.
- Anchor Week zoom on the relevant column and horizontal day position. Ignore callbacks from replaced zoom sessions or detached/reparented scroll views.
- Commit already-ready text previews with new text captures, notes, tasks and recurring successors; avoid the redundant second durable save. Legacy preview repair remains supported.

## Regression coverage

Tests cover deleted attachment history, four mounted native editors and their selected ranges, delayed list insertions, stale query callbacks, keyboard navigation through recycled rows, project switching, both Week scroll axes, detached views, and single-commit text capture. Existing draft, archive recovery, private clipboard, drag payload and editor-protection assertions remain.

Some old fixtures described pre-redesign behavior. They now check actual current history, Extended View and drag/navigation rules. The Daily native test runs a real AppKit loop and waits for a departing editor to unmount before simulating a background drop. An intermediate full run caught a real keyboard regression; it was repaired before the final run.

## Evidence

- `qa-change-inventory.json`: hashes for the 26 native source/test/runner files changed during this QA cycle. The Xcode project was also regenerated for the new registered test. Other pre-existing working-tree changes were preserved.
- `baseline-report.json`: 102/109 suites passed before repairs; seven failures are retained.
- `intermediate-full-report.json` and `intermediate-full-note.json`: 107/110 before the final keyboard and fixture repairs; the obsolete long performance child was deliberately stopped, not treated as a completed measurement.
- `final-focused-report.json`: all five focused repaired suites passed, including Daily Capture 186, Workspace Window 252, Explorer Keyboard 75, Search Window 105 and Viewport Lifecycle 16 checks. These counts are not added to full-run totals.
- `offline-final/report.json`: 90 Python tests, source packaging, metadata draft validation, deterministic project generation and whitespace checks passed.
- `diagnostics/current-reentrancy-stack.log`: diagnostic-only attribution for the nonfatal AppKit estimated-row-height warning. No diagnostic interposer is shipped.

## Final native run and source reconciliation

`final-native-report.json` records **110/110 passing suites and zero failed suites**, including the 600-second stress run. Its raw aggregate status is intentionally preserved as `invalidated_by_source_changes`: a new extra file, `Sources/DaBin/CaptureStore 2.swift`, appeared while the run was in progress. Its bytes exactly matched the pre-QA version of CaptureStore. No original recorded input changed.

The extra old copy was preserved at `diagnostics/CaptureStore-conflicting-old-copy.swift.txt` and removed from the source directory. `source-reconciliation.json` independently verifies that the current inventory of **all 257 QA inputs exactly matches the run-start inventory**. The canonical tested files were not changed during reconciliation. A second old duplicate, `Tests/QAStorageScopedSaveTests 2.swift`, later caused the Store packaging check to flag an out-of-date generated project inventory. It also exactly matched the pre-QA test and was preserved outside Tests; the canonical project needed no change and its generator check passed again (`project-reconciliation.json`). The cause of these extra copies’ appearance is unknown. The raw failure flag has not been edited or hidden; this is a reconciled passing suite result, not an unqualified successful runner exit.

## Performance interpretation

The 60-second fixed-data experiment kept 5,000 records and no incoming captures. Memory largely plateaued after warm-up (about 246 MB); this does not prove absence of leaks. Synthetic input-to-forced-layout p95 was 70.3 ms and steady-zoom main-runloop p95 was 77.3 ms, exceeding the proposed 50/33 ms targets. The probe forces native resize and two layout flushes and bypasses production input coalescing; it is not physical input-to-display latency. Idle timing was about 17 ms. The earlier stress workload differs, so these numbers do not establish a controlled performance regression.

The final 600.016-second stress run saved **399/399 incoming captures**, including a 100-item burst, and completed five zoom/project cycles with **5,399 total records**. Selection, project, anchor and transient-gesture cleanup checks passed. At most three native rows were materialized. Synthetic input-to-layout p95 was **56.1 ms**, steady-zoom runloop p95 **71.0 ms**, and maximum steady interval **85.1 ms**. The 50/33 ms targets remain unmet. Whole-run runloop p95 was 21.3 ms, maximum 136.2 ms, and durable-save p95 28.8 ms. Phase labels are assigned when callbacks arrive and may include time from a preceding phase. RSS grew from 235.2 MB to 253.6 MB alongside the growing archive and retained timing samples; the separate fixed-data result above supplies a different, bounded-warmup observation.

## Limits

Tested on Apple Silicon, macOS 26.6.2, with one attached display and isolated fictional archives/private test pasteboards. Physical mouse-driver/page-swipe settings, a second real display/disconnection, VoiceOver, and the minimum supported macOS 14 runtime were not verified. Cross-process drag payload availability is covered; physical drops into arbitrary third-party browsers are not. AppKit/SwiftUI estimated-row-height warnings remain in diagnostic output. The captured stack contained no DaBin restoration callback; that observation is not proof the platform warning is harmless.

Large-archive zoom smoothness remains an unmet performance target. This QA cycle is not Apple review, notarization or publication. Core tests do not exercise remote services or use the user’s private captures as fixtures.

## Build and local launch

The final unsigned Store Release compiled and passed packaging validation with unchanged inputs. Its initial packaging failure and the test-copy reconciliation are retained. The direct ARM64 Release built with warnings treated as errors and passed strict signature checks. This locally signed bundle is not a notarized/public release.

Installed at `/Users/roeylibfeld/Applications/DaBin.app`, retaining the previous bundle in `/Users/roeylibfeld/Applications/.DaBinBackups/20261004-153541-4a096b9b.app`. Version remains **0.4.31 (86)**; this QA patch is identified by source fingerprint `82e8c05cd9c454b716ddd72ffe91cacbd3f423dbd894b24a18a68545a2aced98`. Both the installed main executable and embedded updater match the build receipt. The desktop shortcut resolves to the installed app, and exactly one main DaBin instance is running from that path.

Live UI verification opened Settings, confirmed the navigation/zoom controls, and used Command–[ / Command–] to return between Inbox and Settings. DaBin is left running on Inbox. No preferences or saved captures were intentionally changed during this live check. The installer does not modify the archive; archive byte equality was not audited after normal app startup. Nothing was committed, pushed or published during this cycle.

## Visual evidence

Representative native renders inspected: narrow dark Search, wide light Search with preview, compact light Search, light workspace at 75%, compact dark project card at 200%, and Today card at 200%. Native interaction tests exercise the corresponding controls and accessible labels; this is an assistant review, not external user research.

- [Compact Search](final-search/renders/global-date-search-compact-short-light-380x520@2x.png)
- [Today at 200%](final-layout/today-380-200@2x.png)
- [Native robot opening QA clip](DaBin-Animation-QA.mp4) — fictional content; test evidence, not a marketing walkthrough.
- [Machine-readable final verification](verification.json)
- [Independent source/artifact audit](source-artifact-audit.json)
