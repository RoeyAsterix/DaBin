# DaBin modularity refactor — 0.4.49 (104), 7 October 2026

The refactor is applied to the working source. Draft sessions, durable import operations, readable-archive maintenance, workspace composition/native hosting and tutorials now have explicit collaborators. The existing single production Swift app module and system-framework dependencies are retained. This improves responsibility boundaries; it does **not** establish a smaller binary or faster execution.

The production freeze is `45414902e2ea23bd50bb9ce02eb76a5d6cc4576c98193f576e634549a91bee24`. Version/build remain **0.4.49 (104)**. All code, tests and build configuration matched the frozen inputs through verification. Five stale architecture descriptions were corrected afterward; their separate receipt confirms unchanged production/test/configuration inputs.

## Implemented ownership

- `State/AppDraftSession` owns stable draft identities, recovery persistence, debounce scheduling and per-editor subscriptions. Removed editors and shutdown cancel their observation work. AppState retains presentation, routing and command coordination; its note/error publishers remain facade state.
- `Storage/CaptureImportJournalService` owns verified file staging, journals, compensation and interrupted-import recovery. `CaptureArchiveMaintenance` owns repair scheduling, failure state and generation cancellation. CaptureStore retains canonical models, metadata commits and publication order; collaborators reuse the same repository/archive objects.
- `Interface/Workspace` separates browser content, current command context, native retained-row hosting and viewport anchors. Cards receive their own selection/focus presentation instead of a whole selection set. Native Copy uses the current command snapshot after row reuse. Existing row-refresh completeness, focus, cancellation and measurement guards remain.
- `Interface/Tutorial` owns tutorial definitions, controller and overlay presentation. BoardView retains the board shell.
- Recursive deterministic inventory covers nested sources, rejects filename collisions and feeds compilation, fingerprints and Xcode layer groups. No package dependency or extra production target was introduced.

| Main file | Before lines | After lines |
| --- | ---: | ---: |
| AppState.swift | 2,797 | 2,318 |
| CaptureStore.swift | 1,460 | 1,290 |
| ProjectWorkspaceView.swift | 1,382 | 408 |
| BoardView.swift | 1,011 | 544 |
| WorkspaceZoomLayout.swift | 318 | 64 |

Those five files shrink from 6,968 to 4,624 physical lines. Thirteen new production collaborators add 2,624 lines, so touched production text totals **7,248 (+280)**, including comments and spacing. Production source files increase from 145 to 158; these are components in one Swift module, not thirteen separate modules.

## Verification

| Check | Result |
| --- | --- |
| Focused Release App Store regression | **23/23 passed** |
| Full registered Release App Store native campaign | **131/132 passed**; WorkspaceZoomPerformanceTests failed |
| Separate 600-second strict workload | **Failed both original timing limits** |
| Python tooling | **66/69 passed**; three existing metadata identity failures |
| New inventory tests | **6/6 passed**, included in Python total |
| Offline packaging/preflight tests | **33/33 passed** |
| Unsigned arm64 Store Release build | **Passed**; embedded metadata/fingerprint and executable hash verified |
| Unsigned packaging inspection | **51 checks passed** |
| Deterministic Xcode project check | **Passed** |
| Final evidence integrity | **133/133 required compiled receipts verified**; no missing artifacts or input/hash mismatches |

The full campaign includes 8,586 durability checks with 1,000 seeded records, 320 mixed operations, 25 restart comparisons and four actual SIGKILL boundaries. Flow/action stress passes 11,674 checks; graphics/animation stress passes 93,867. New regressions cover draft ownership/cancellation/recovery and current-selection Copy after native-row reuse. ProjectWorkspaceViewTests passes 1,042 checks with at most five materialized rows browsing the synthetic 1,000-capture fixture.

## Performance remains unqualified

| Frozen refactor workload | Input/layout p95, limit 50 ms | Steady timer p95, limit 33 ms |
| --- | ---: | ---: |
| 30 seconds | **42.03 ms — pass** | **35.69 ms — fail** |
| 600 seconds | **52.77 ms — fail** | **36.19 ms — fail** |

The timer gate already failed before the refactor. The sustained input failure is new relative to the previous recorded run and remains unresolved; its cause is not established. A separate unchanged short ABBA comparison used baseline/refactor/refactor/baseline sources with identical harness bytes. All four input gates passed and all timer gates failed. Baseline input p95 ranged 42.60–47.12 ms; refactor ranged 42.55–48.69 ms. These overlapping short-run timings do not establish a repeatable short-run regression, do not exonerate the sustained failure, and do not replace either original result. Exact distributions, source review and uncertainty are in [performance-review.md](performance-review.md).

Both original timing limits and the arrival workload remain unchanged. Each measured run has five cycles of 32 synthetic inputs; the 600-second run spaces those cycles over ten minutes. It is not continuous ten-minute zoom input. The fixture starts with 5,000 captures and grows to 5,114/5,399 with 114/399 durable automatic arrivals, including a 100-arrival burst. RSS includes growing data, caches and measurement arrays; it does not prove or disprove a leak.

## Retained findings and coverage boundaries

The full run retains **ten NSTableView delegate reentrancy warnings**: seven in ProjectWorkspaceViewTests, two in SearchWindowTests and one in CaptionSelectionTests. Focused regression also records seven; they are separate observations of the same exercised path. The framework says this condition will become an assertion. Three existing actor-isolation diagnostics in TaskPriorityTagTestsFixture.close are represented by six warning lines. Xcode also reports its App Intents metadata-extraction notice; no new Swift production warning was accepted by the warnings-as-errors builds.

The optional whitespace diff scan reports one extra blank line at the end of WorkspaceZoomLayout.swift; the tested source bytes remain unchanged. Its exact exit status is retained separately.

The three metadata checks still fail because the existing Store metadata draft describes **0.4.45 (100)** while current source is **0.4.49 (104)**. This refactor preserves that unrelated draft. Source-version changes, production installation, distribution signing, archives and uploads were not performed.

Fixtures exercise native components and synthetic input; they do not certify physical trackpad/mouse latency or input-to-display presentation time. Only one attached display was available. VoiceOver, supported older OS/hardware variants and signed sandbox behavior remain separate coverage. Video checks exercised actual AVPlayer transport with eight API fallbacks and **zero native AX Play/Pause button activations**; audio, slider dragging, AirPlay/PiP and decoder variants remain unasserted. Requested contrast/Reduce Motion profiles do not certify the corresponding OS setting transitions.

## Evidence and working-tree scope

[verification-summary.json](verification-summary.json) distinguishes evidence integrity from workload acceptance. [full-campaign-result.json](full-campaign-result.json), native reports, strict metric JSON and [comparison-result.json](comparison-result.json) retain original failures. [raw-evidence.zip](raw-evidence.zip) preserves hash-indexed text reports/logs/cache receipts and the twelve original touched files; [comparison-evidence.zip](comparison-evidence.zip) preserves separate diagnostic records. Binary/image fixture outputs are excluded; compiled bytes remain identifiable through verified output hashes.

[refactor.patch](refactor.patch) and [owned-changes.json](owned-changes.json) describe **27 owned paths against the preexisting working-tree bytes**, not against Git HEAD. [applied-refactor.json](applied-refactor.json) records guarded application. The separate documentation patch/receipt and [final-live-verification.json](final-live-verification.json) describe the later prose corrections. Existing source/UI/docs changes and unrelated untracked folders are preserved. Source changes remain in the shared working tree; an evidence-only commit does not commit or publish those source changes.

This record does not qualify TestFlight or a Store release. Current-source performance acceptance, a publication freeze, distribution signing, sandbox/archive validation, upload, processing and tester availability/email request remain separate gates.
