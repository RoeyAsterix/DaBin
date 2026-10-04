# Navigation and adaptive workspace zoom

Implementation review for `docs/NAVIGATION_AND_ZOOM_HANDOFF.md`, 4 October 2026.

**Local update follow-up, 4 October:** after the user requested installation, the same tested source was rebuilt as Release, installed at `~/Applications/DaBin.app`, and relaunched. Both old running copies exited cleanly first. The installed executable hash and source fingerprint were verified; exactly one main DaBin process launched from the installed path with its 400 × 747-point window visible. The previous bundle was backed up and the archive was not modified by the installer. [Installation receipt](local-installation.json). Statements below about installation not being part of the implementation task describe the earlier verification stage.

## Implemented behavior

- One bounded, session-only Back/Forward history for compact toolbar buttons, Command–[ / Command–], supported mouse auxiliary buttons, and native page swipes. History contains route and presentation metadata, never capture bodies or draft text.
- Project, search, day/week, detail, creation, Settings and Trash return journeys preserve current selections, filters, draft owners and item-relative viewport anchors. Deleted and renamed destinations resolve against current data.
- Window-local gesture ownership preserves document zoom and horizontal scrollers. Navigation is rejected during zoom, drag/resize, modal UI, marked-text composition and unresolved validation failures.
- Workspace zoom spans 75–200%, with continuous pinch and Command–wheel input, discrete keyboard steps and explicit View menu commands. Document zoom remains independent.
- Floating-window zoom uses a stable geometry reference, respects usable screen bounds and keeps the robot and navigation controls at their original sizes. Expanded windows retain their Restore frame. Manual movement/resizing rebases subsequent zoom.
- Settings persist workspace scale, Trackpad Back and Forward, and Resize window with workspace zoom. Scale and normal geometry save at completed interaction boundaries.
- Cards, previews and content text use native layout metrics. Grid columns remain stable during a gesture and reflow on completion. The narrow project-card layout wraps metadata and titles at large zoom.

## Architecture and changed areas

| Area | Files |
| --- | --- |
| History and restoration | `NavigationHistory.swift`, `AppState.swift` |
| Native input and focus | `WorkspaceInput.swift`, `DailyCaptureView.swift`, `ApplicationMenu.swift`, `CaptureExtendedCanvas.swift` |
| Zoom state and window geometry | `WorkspaceZoom.swift`, `CornerController.swift`, `ApplicationCoordinator.swift` |
| Layout and viewport coordination | `WorkspaceZoomLayout.swift`, `WorkspaceZoomScrollAnchor.swift`, `ExplorerViewport.swift`, `SearchColumnViewport.swift` |
| Visible navigation and preferences | `BoardView.swift`, `SettingsScreen.swift`, `LibraryScreen.swift` |
| Zoom-aware workspace content | Project, Explorer, Search, Inbox, Daily, Weekly, Today, detail, note and task views; shared cards and previews; `ProjectWorkspaceState.swift` summary cache |
| Regression coverage | `NavigationHistoryTests.swift`, `WorkspaceInputTests.swift`, `WorkspaceZoomTests.swift`, `WorkspaceZoomLayoutTests.swift`, `WorkspaceZoomPerformanceTests.swift`; existing navigation/window tests; `scripts/run_qa.py` |

The working tree contained substantial earlier work. This list identifies the current feature's integration areas, not every pre-existing Git change.

## Verification status

The final [regression receipt](regression-report.json) records **23 passing functional suites**, with no source changes during the run. These cover history, commands, focus, search, project scope, task conversion, day/week state, document zoom, capture input, headers, Explorer keyboard behavior, auto-capture responsiveness, window resizing, robot transitions, zoom geometry and viewport anchoring. Production and test compilation use warnings as errors.

The receipt also contains a performance entry deliberately stopped with SIGTERM: inspection showed its initial fictional media paths rendered placeholders. Only that test fixture was changed afterward, to validate 2,000 owned originals and 1,000 thumbnail files and decode an image through the production cache before timing. The [replacement performance suite](performance-report.json) passed all **25 correctness checks** over **600.02 seconds**. The stopped run is not counted as a successful performance test. Together, the final receipts cover **24 distinct passing suites**; performance thresholds remain separate acceptance gates below.

The [focused correction run](focused-fixes-report.json) passed all four selected suites before the final batch. Regression coverage includes 50 clamped zoom round trips, Back/Forward branch behavior, stale swipe cancellation, draft preservation, failed/stale focus restoration, live insertion anchoring and explicit Explorer regrouping.

### Local build and source binding

`DABIN_SIGNING_IDENTITY=- ./scripts/build.sh` completed a Release build for `arm64-apple-macosx14.0`, with warnings as errors, an ARM64 architecture check and strict signature verification on a clean copied bundle. `git diff --check` passed for the affected native sources, tests, QA runner and generated Xcode project. The project has no separate Swift lint command; compiler diagnostics and whitespace checks are the checks performed here.

The [verification record](verification.json) confirms that all 137 production source files match both QA receipts and the built candidate, all applicable test inputs still match, and the executable SHA-256 matches the [build receipt](build-receipt.json). Only the deliberately superseded performance fixture differs from the first receipt; the replacement receipt tests its current bytes.

- Local candidate: `native/build/DaBin.app`
- Existing version/build labels: **0.4.31 (86)**; this task did not create a new release version.
- Build source fingerprint: `4edc428c70392a99c0a112c5227f2b4b02dd6a21c9f369d3040e739cd133aacd`
- Local ad-hoc signing was used. The installed app was not replaced and no release was published.

The sustained command was:

```sh
DABIN_ZOOM_PERFORMANCE_SECONDS=600 \
DABIN_ZOOM_PERFORMANCE_QA_OUTPUT='../docs/qa/navigation-zoom-2026-10-04/sustained' \
python3 scripts/run_qa.py --only WorkspaceZoomPerformanceTests --timeout 780
```

### Visual evidence

- [75%, light](layout/workspace-75-light@2x.png) · [75%, dark](layout/workspace-75-dark@2x.png)
- [100%, light](layout/workspace-100-light@2x.png) · [100%, dark](layout/workspace-100-dark@2x.png)
- [150%, light](layout/workspace-150-light@2x.png) · [150%, dark](layout/workspace-150-dark@2x.png)
- [200%, light](layout/workspace-200-light@2x.png) · [200%, dark](layout/workspace-200-dark@2x.png)
- [380-point project card at 200%](layout/project-compact-380-200@2x.png)
- [380-point Today card at 200%](layout/today-380-200@2x.png)

These are native fictional-data renders. The compact-card fix and full production-board renders were inspected; they are the developer's evaluation, not feedback collected from external users.

The completed stress fixture also rendered the real production board with local image previews: [75%](sustained/production-board-75@2x.png), [100%](sustained/production-board-100@2x.png), [150%](sustained/production-board-150@2x.png), [200%](sustained/production-board-200@2x.png). The top row is intentionally partly visible because these renders preserve a scrolled item/offset rather than returning to the top.

### Sustained performance

[Raw measurements](sustained/performance.json) retain every sampled phase, including arrivals and navigation. The fixture injected one saved capture every two seconds plus a burst of 100, ran five 32-step zoom cycles, and retained all **399 arrivals**, ending with **5,399 records**. The same anchored capture survived all five round trips. At most **three native grid rows** were materialized simultaneously. Preferences were written at completed interactions, not per magnification tick.

| Measurement | Observed | Proposed target / interpretation |
| --- | ---: | --- |
| Synthetic input → native layout, p95 | 52.34 ms | ≤50 ms: not met |
| Steady-zoom main-loop timer interval, p95 | 63.48 ms | ≤33 ms proxy: not met; not a display-frame measurement |
| Steady-zoom maximum timer interval | 75.28 ms | No interval over 100 ms within this phase |
| Whole-run maximum timer interval | 135.65 ms | 273 intervals exceeded 100 ms across arrival/burst/navigation delivery phases |
| Warm baseline timer interval, p95 | 19.77 ms | Reference only |
| Durable save, p95 | 43.49 ms | Reference only |
| RSS before interaction | 234.37 MB | Includes native application, fixture and caches |
| RSS after first / fifth cycle | 251.07 / 253.41 MB | +2.34 MB after the first cycle, with 239 more records |

The profiler identified repeated project-header counts/color lookup and project row construction, which were cached. It also showed substantial time in native window resize → SwiftUI layout. The earlier smoke measurements used placeholder media and are not a directly comparable before/after benchmark for the real-media sustained run.

**Release gates remain open:** the proposed latency targets are not met. The benchmark also logs an AppKit table reentrancy warning during initial/final layout; it does not reproduce in the focused viewport or Explorer responsiveness suites. These results do not establish stutter-free performance or eliminate a future AppKit compatibility risk. Physical display presentation timing still needs measurement.

The monotonic RSS warning was reviewed against retained state: layout caches hold at most six variants, the picker retains one project summary, and the preview cache is configured for 32 MiB / 128 images (NSCache limits are advisory). Native viewport callbacks use weak references and remove observers on teardown. The benchmark itself retains increasing capture models and duplicates timer samples in whole-run/per-phase arrays, capped at 60,000 samples. No concrete retention defect was found in that source review. The final memory checkpoint is after cycle five, around minute eight; this growing-data run is not a fixed-data heap comparison and cannot prove the absence of a leak. A fixed-data allocations run remains a release check.

## Device coverage and limitations

Reference hardware: MacBook Pro (`Mac17,9`), Apple M5 Pro, 15 CPU cores, 48 GB memory; macOS 26.6.2 (25G83), ARM64, native backing scale 2×. One physical display was attached during the window tests; additional display layouts and removal were simulated through the geometry layer.

Native AppKit tests and fictional-data renders run on that Mac. No live archive, clipboard contents or private previews are used by the stress fixture. Its window cannot become key or main and is excluded from capture.

Synthetic input and geometry tests do not establish physical trackpad or mouse-driver behavior. Natural scrolling on/off, actual page-swipe settings, physical display disconnection, VoiceOver interaction, real IME composition and non-US keyboards require device checks. Synthetic timer intervals and forced native layout timing are not physical input-to-display or frame-presentation measurements.

No installation, release publication or App Store submission is part of this task.

## Issues caught during verification

- Interrupted native page-swipe recognition retained an input owner. Cancellation now releases only the active generation, so a stale callback cannot cancel a newer pinch.
- A delayed focus restore could outlive its destination or apply selection after a failed focus transfer. Requests are now tied to the window, request generation and navigation revision, with selection applied only to the successfully focused editor.
- Synchronous native table notifications could scroll from inside a row-layout callback. Corrections are queued and coalesced; teardown cancels pending work. Recycled anchor rows use native estimated geometry without materializing offscreen rows.
- Restoring a historical Explorer offset interfered with an explicit regrouping action. Deliberate regrouping keeps the selected item visible; Back/Forward still use saved item-relative offsets.
- Compact project cards clipped project names and task titles at 200%. The narrow layout now stacks metadata and gives the title the full card width.
- Project rows, item lookup and header summaries were rebuilt during pure zoom. Bounded caches now invalidate on actual data or scope changes.

The test harness also needed two corrections: restore a trashed record using its current repository instance, and yield the main actor before asserting SwiftUI's asynchronous search focus. The native focus assertion remains required.

## Content integration file inventory

In addition to the explicitly named architecture files above, the content integration touches `CaptureCards.swift`, `CapturePreviews.swift`, `CollectionPreviewMosaic.swift`, `DailyScreen.swift`, `DetailScreen.swift`, `ExplorerItems.swift`, `ExplorerScreen.swift`, `GroupedCaptureCard.swift`, `HourlyCaptureCard.swift`, `InboxScreen.swift`, `NewNoteScreen.swift`, `ProjectWorkspaceCard.swift`, `ProjectWorkspaceView.swift`, `ScratchpadView.swift`, `SearchResultCard.swift`, `SearchScreen.swift`, `TaskEditorScreen.swift`, `TodayPlanningScreen.swift`, `WeeklyScreen.swift` and `WorkspaceItemCard.swift`.

Existing regression fixtures updated for this task include `DailyCaptureTests.swift`, `HeaderInteractionTests.swift`, `WindowResizeInteractionTests.swift` and `ProjectWorkspaceStateTests.swift`. New sources are registered in the generated `native/DaBin.xcodeproj/project.pbxproj`; the new suites are registered in `native/scripts/run_qa.py`.
