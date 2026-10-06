# Candidate 4 owned-profile analysis

Recorded 2026-10-06. This is a read-only analysis of retained Release/direct QA evidence. No native process was launched, no production source was changed for this analysis, and no benchmark threshold or workload was changed.

## Result and evidence scope

Candidate 4 substantially reduces the previously observed ForEach graph work, but the original strict performance gate still fails. The accepted unsampled comparison is:

| Run | Input-to-layout p95, ms | Steady-zoom timer p95, ms | Coupled-resize p95, ms |
| --- | ---: | ---: | ---: |
| Baseline direct | 73.27 | 81.97 | 65.89 |
| Candidate 1: header/receipt | 66.72 | 77.66 | 59.22 |
| Candidate 2: equal-column rows | 63.82 | 68.12 | 50.79 |
| Candidate 3: card flow/footer | 61.14 | 70.84 | 51.46 |
| Candidate 4: stable browser/card boundary; flow/footer reverted | 53.56 | 61.80 | 44.44 |
| Required maximum | 50.00 | 33.00 | No separate gate |

The five measurements come from each corresponding `zoom-performance/performance.json` under `docs/qa/full-review-2026-10-05/`, with no sampling applied to acceptance. Candidate 3's extra card flow/footer work did not materially improve candidate 2 and was reverted in candidate 4.

The separate owned diagnostic profile in this directory reports 56.47 ms input p95, 66.90 ms steady timer p95, and 46.82 ms coupled-resize p95. Sampling adds diagnostic overhead, so those values do not replace the unsampled acceptance result. `wrapper-report.json` confirms a completed process with exit code 1, a 30-second original burst/arrival workload, and only the owned benchmark PID sampled. Maximum available native rows remained five; this does not support a claim that all 5,000 cards were instantiated.

This sample predates the subsequent non-media preview accessibility-value fix. Its exact retained inputs are:

- `ProjectWorkspaceCard.swift`: `4ccf04ee716528f650f5b8c97cf99125e1314016c1f79a581e2fc5160e2b3e2b`
- `ProjectWorkspaceView.swift`: `3cd919de983048d4f0d3c4240cfa7b07ae0f2b56fb3d83b2b3600e4669b61877`
- `owned-process-sample.txt`: `44a6ef8bdacab5237467fc6bfd9213fb9d4cec7cd90692e0c75cee6f022abb13`

Receipts, stdout/stderr, sample metadata and the native performance JSON are retained alongside this file. The fixture is an offscreen native renderer with fictional archives. It cannot measure physical input/display latency, GPU frame pacing, exhaustive leaks or the distribution sandbox.

## Main-thread attribution

`owned-process-sample.txt` records 3,691 main-thread samples. The `WorkspaceZoomSettings.update(to:)` subtrees contain 913 samples at line 1972 (through line 9095) and three at line 9096 (through line 9132). The comparison below uses only those 916 samples, not unrelated idle or seed work.

For each category, count the first matching frame on a stack path and exclude its matching descendants, avoiding repeated counting of the same samples within that category. Categories overlap with one another and must not be added or described as independent CPU percentages. Counts also depend on the sampled workload phase; they are attribution evidence rather than wall-clock acceptance measurements.

| First-match category | Candidate 3 | Candidate 4 |
| --- | ---: | ---: |
| Complete zoom-update subtrees | 1,109 | 916 |
| NSHostingView/FocusBridge preference or key-loop invalidation | 382 | 369 |
| Native table row key-loop maintenance | 356 | 334 |
| ForEachState/ForEachChild/ForEachView | 99 | 8 |
| ProjectWorkspaceCard content body | 60 | 67 |
| Receipt/NSDateFormatter work | 38 | 39 |
| ProjectWorkspaceRowLayout | 58 | 57 |
| Board/ProjectWorkspace/Library bodies | 34 | 34 |
| Explorer/WorkspaceZoom viewport methods | 0 | 1 |
| LayoutEngineBox | 122 | 90 |

The candidate 3 comparison is `layout-candidate-3/profile/owned-process-sample.txt`, zoom-update subtree lines 3133–11524. The baseline update roots total 1,326 samples, with 474 focus-preference/key-loop samples, 121 card-body samples, 95 receipt samples and 100 ForEach samples. These baseline values use `baseline-profile/owned-process-sample.txt`, beginning at line 3287; they are supporting attribution rather than normalized per-input timing.

The strongest remaining candidate 4 branch is:

1. Line 2011: 348 samples in `NSHostingView.preferencesDidChange()`.
2. Lines 2012–2014: `FocusBridge.preferencesDidChange`, `invalidateKeyViewLoop`, then `updateDefaultKeyViewLoop`.
3. Lines 2015–2021: native default-key-view-loop traversal reaches `NSTableRowData.updateKeyViewLoopForAllRows` and enumerates available row views, with 332 samples.
4. Lines 2022–2045: 276 samples recursively enter `NSView.layoutSubtreeIfNeeded` from row key-loop maintenance; 248 reach native view layout and 240 reenter hosting-view layout.

Other exact references: the main card-body branch is line 4735, receipt civil-date parsing is line 4738, project body work is line 5407, the single viewport update is lines 5890–5891, equal-row sizing is line 6208, and remaining ForEach graph branches include lines 7258 and 7385.

The fall in ForEach samples supports retaining the stable browser boundary, provided its live-content and interaction tests pass. It does not eliminate native focus maintenance or the actual font/media layout required by zoom. Parent bodies and history/viewport methods are not a dominant cost in this sample. The sample does not record proposal widths or cache misses, so it cannot justify a persistent width-only layout cache.

## Native warning comparison

These warnings were present before any layout candidate:

| Run | Project view reentrancy warnings | Project view truncation warnings | Performance reentrancy warnings | Performance truncation warnings |
| --- | ---: | ---: | ---: | ---: |
| Baseline direct | 10 | 1 | 1 | 0 |
| Candidate 1 | 10 | 1 | 1 | 0 |
| Candidate 2 | 10 | 1 | 1 | 0 |
| Candidate 3 | 10 | 1 | 1 | 0 |
| Candidate 4 initial focused run | 8 | 1 | 1 | 0 |

Candidate 4's initial project-view run stopped at the new integration fixture before the existing calendar suite. Its shorter warning count is therefore not evidence that candidate 4 fixed reentrancy. Standalone ProjectWorkspaceCardTests and WorkspaceZoomLayoutTests logs have no occurrences of either warning. The available candidate 1, 3 and 4 owned-profile stderr logs each retain one reentrancy warning and no truncation warning.

Exact original logs, relative to the DaBin repository:

| Run | Project view log | Reentrancy lines | Truncation line |
| --- | --- | --- | ---: |
| Baseline | `native/build/qa/runs/20261005T200323119330Z-direct/ProjectWorkspaceViewTests.log` | 1, 2, 7, 8, 9, 10, 13, 17, 36, 37 | 16 |
| Candidate 1 | `native/build/qa/runs/20261005T203124083382Z-direct/ProjectWorkspaceViewTests.log` | 1, 2, 7, 8, 9, 10, 13, 17, 36, 37 | 16 |
| Candidate 2 | `native/build/qa/runs/20261005T204449702635Z-direct/ProjectWorkspaceViewTests.log` | 1, 2, 7, 8, 9, 10, 13, 17, 36, 37 | 16 |
| Candidate 3 | `native/build/qa/runs/20261005T205124249037Z-direct/ProjectWorkspaceViewTests.log` | 1, 2, 7, 8, 9, 10, 13, 17, 36, 37 | 16 |
| Candidate 4 | `native/build/qa/runs/20261005T211610317127Z-direct/ProjectWorkspaceViewTests.log` | 1, 2, 7, 8, 9, 10, 13, 17 | 16 |

The performance warning is at line 2 of `WorkspaceZoomPerformanceTests.log` in each listed run directory. Every project truncation warning has the same native diagnostic: range `{0, 1006}`, count `296`. The project fixture performs actual selection, filtering, resizing, arrivals and accessibility enumeration; the warning text alone does not identify which application callback causes the nested delegate operation.

The reentrancy warning explicitly says that a future AppKit version may assert. These remain unresolved readiness findings even when functional assertions pass. They are neither new candidate 4 regressions nor proven harmless framework behavior.

## Supported next steps and limits

Existing WorkspaceZoomViewport code already coalesces restoration and history work onto a subsequent main-loop turn and checks native row counts before restoring. ExplorerViewport also defers connection/restoration and guards mutation anchoring during zoom. The sample does not implicate these callbacks. Another speculative deferral, native focus/key-loop suppression, removal of focusability, or benchmark/window-coupling changes would not be justified.

A bounded future production improvement supported by the sample is avoiding repeated DateFormatter construction and civil-date parsing for immutable receipt formatting in `CapturePresentation.swift`. Such a change must preserve capture-zone date/clock output and include explicit locale/calendar invalidation, bounded storage and concurrency safety. Receipt work is a small remaining share; this cannot honestly promise the 33 ms timer target. No receipt cache or formatter change was made for this analysis.

Before changing behavior for the native warnings, capture an owned-process stack at the warning to identify an application callback or framework path. Preserve the warnings and the strict failed performance gate in the Store/full-review record. Further validation must include current-content, replacement-identity, native keyboard/focus, drag, viewport/history and unsampled performance checks. This analysis makes no App Store approval or GPU-performance claim.
