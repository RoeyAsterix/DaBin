The refactor's sustained run newly fails the original 50 ms input gate. That failure remains material; the current records do not establish its cause. Both prior and current runs also fail the original 33 ms steady-runloop gate. Short diagnostic comparisons must remain separate from the full and sustained outcomes.

Provenance: prior production fingerprint `85d7f1546715936c17e9867d0acf952459cfc98702faec5ebc12b5f7aca2e24f`; current frozen refactor fingerprint `45414902e2ea23bd50bb9ce02eb76a5d6cc4576c98193f576e634549a91bee24`. Both use app-store Release, Swift 6.4, macOS 26.6.2, SDK 27.0 and arm64-apple-macosx14.0. `WorkspaceZoomPerformanceTests.swift` is byte-identical, SHA-256 `9cdff65ddc4a949a10cd925adcdfedb214d6d04f65f6a00f10d1ef3410a19bf3`. Current native receipts report no source changes during either run.

| Metric (ms unless stated) | Prior 30 s | Current 30 s | Prior 600 s | Current 600 s |
| --- | ---: | ---: | ---: | ---: |
| Input-to-layout p95 | 42.724 | 42.028 | 42.718 | 52.772 |
| Steady timer p95 | 34.158 | 35.688 | 35.677 | 36.192 |
| Warm baseline timer p95 | 16.946 | 16.722 | 17.226 | 17.690 |
| Whole-run timer p95 | 31.871 | 32.906 | 20.343 | 19.423 |
| Durable save p95 | 26.499 | 24.921 | 30.538 | 30.482 |
| Automatic arrivals (count) | 114 | 114 | 399 | 399 |
| Maximum available native rows (count) | 5 | 5 | 5 | 4 |

| Sustained input stage | Prior median / p95 (ms) | Current median / p95 (ms) |
| --- | ---: | ---: |
| update.total | 15.590 / 21.057 | 14.998 / 25.422 |
| update.coupledResize | 15.547 / 21.017 | 14.947 / 25.361 |
| update.excludingCoupledResize | 0.042 / 0.063 | 0.044 / 0.063 |
| firstLayout | 0.012 / 0.022 | 0.013 / 0.025 |
| schedulingWait | 2.096 / 24.287 | 2.055 / 24.176 |
| secondLayout | 13.277 / 20.093 | 14.337 / 20.459 |

The largest stage-tail increase is coupled resize (+4.344 ms p95); the second-layout median is about 1.060 ms higher. Non-resize publication and scheduling-wait p95 are essentially unchanged. The current 30-second input p95 improves despite a coupled-resize p95 increase from 20.681 to 23.482 ms. Stage percentiles cannot be added to explain the total p95: the reports do not retain paired per-step samples or identify the slowest cycle/step.

Sustained cycles 2-5 take 2.010, 1.984, 1.970 and 2.008 seconds, versus prior 1.900, 1.890, 1.883 and 1.917 seconds. Their average increase is about 95 ms per complete cycle, including settle and other cycle work. Cycle 1 grows from 3.743 to 4.355 seconds. The burst phase has 17 timer intervals above 100 ms versus zero previously, and its timer p95 rises from 99.328 to 133.553 ms. Crossing the four-second arrival boundary adds one earlier capture; total arrivals still equal 399. This is broader than a clearly isolated steady-renderer change. Phase labels describe callback delivery and can contain preceding work.

UI byte review:

- ProjectWorkspaceView's actual view implementation is unchanged; toolbar, busy/navigation predicates, content/action-context preparation and sheets remain identical.
- Native retained-row scheduling, generation/lifecycle guards, root assignment, sizing, focus traversal and completion receipts are unchanged. Copy moved to stable actions and removes one per-root closure; Copy is not invoked by this workload.
- WorkspaceZoomViewport implementation is an exact move. WorkspaceZoom, ExplorerViewport, RobotAppFrameView, ProjectWorkspaceCard and CapturePreviews match the previous frozen baseline byte-for-byte.
- The tutorial implementation is an exact move, but BoardView now mounts it through an extra ViewModifier with an ObservedObject tutorial controller. The tutorial stays inactive in this workload; its hierarchy/dependency boundary is an introduced candidate, not proven attribution.
- Card equality now receives a smaller presentation value. Its construction adds a second `item.id` formatting expression per rendered card and moves own selection/focus checks before equality. No new native host, observer, queued work, row measurement or offscreen row creation is introduced. The magnitude of any construction cost is unmeasured.

Existing native discovery and linear anchor-row lookup remain potential repeated work, but their implementations did not change and cannot alone establish an introduced regression. Existing whole-environment card dependencies and native automatic-row-height warnings likewise require attribution, not suppression. The recorded baseline/idle metrics do not show uniform system degradation; environmental variability remains possible but unrecorded. Neither explanation is established by one sustained pair.

The ABBA diagnostic driver was reviewed read-only at `/private/tmp/dabin-modularity-20261007/run_comparison.py`. It uses a nonblocking shared QA lock, verifies frozen input hashes and identical harness bytes, removes inherited DABIN_/DYLD_ overrides, runs baseline/refactor/refactor/baseline serially with original 30-second arrivals and gates, creates fresh output directories, and preserves each native report/log plus distinct diagnostic scope. It does not overwrite the full/sustained evidence copies. Hash matching covers known frozen files; it does not independently reject extra source files, so runner input inventories and source-change receipts still need review. An interrupted series remains incomplete and must not be presented as a four-run result.

The completed unprofiled ABBA30 result is `/private/tmp/dabin-modularity-comparison-20261007/comparison-result.json`, SHA-256 `248eb7acaf3e8508d564204ecd93fa4df2b2abea62894bca912de842da37a2a1`, finished at `2026-10-07T08:57:16.118739+00:00`. All four frozen-source checks pass, all native receipts report `sourceChangedDuringRun: false`, and the identical harness SHA is recorded. Individual metrics and native reports are preserved under `1-baseline`, `2-refactor`, `3-refactor` and `4-baseline` in that separate comparison directory.

| ABBA30 run | Input p95 (ms) | Steady timer p95 (ms) | Original gates |
| --- | ---: | ---: | --- |
| 1 baseline | 47.121 | 38.504 | input pass; timer fail |
| 2 refactor | 48.687 | 37.454 | input pass; timer fail |
| 3 refactor | 42.555 | 37.008 | input pass; timer fail |
| 4 baseline | 42.600 | 36.905 | input pass; timer fail |

The short-run input ranges overlap: baseline 42.600-47.121 ms, refactor 42.555-48.687 ms. There is no established repeatable short-run input regression in this four-run diagnostic; all timer gates continue to fail. Run-order changes occur in both variants, and two samples per variant cannot identify their cause. This comparison neither exonerates nor qualifies the newly failed 600-second input gate, and it does not replace any original campaign result. No additional workloads are requested or launched by this review.

If future attribution work is authorized, the smallest additional diagnostic is exporting the already-collected raw input totals and six stage arrays after measurement in a separate harness copy. Samples map to cycle `index / 32` and step `index % 32`; no additional input-time work, yield, layout or drain is needed. Keep gates and fixture unchanged, separate the diagnostic harness hash, and compare paired before/after runs without concurrent builds. A profiler attachment, if then needed, targets only the owned harness PID and makes its timing noncertifying. ABBA30 cannot resolve sustained600 qualification.

Metric records (documentation baseline copies were verified byte-identical to these frozen outputs):

- Prior30: `/private/tmp/dabin-speed-stability-20261007-070033/outputs/full-native/zoom_performance_qa_output/performance.json`, SHA-256 `f4bcee8d011fa116d4caa794b84e36ca51aaefa59d1eeaf38606c5ec82b38359`.
- Prior600: `/private/tmp/dabin-speed-stability-20261007-070033/outputs/sustained-speed/zoom_performance_qa_output/performance.json`, SHA-256 `c24afbc60a51d17adf220f7f74d7ea7c0a7d711287df7e04e82344a4b9c49893`.
- Current30: `/private/tmp/dabin-modularity-20261007/outputs/full-native/zoom_performance_qa_output/performance.json`, SHA-256 `d9cda2001385f9170e9c7ffe27a72fda9ca476d397f6cd59ccdb41397d4b7c3a`.
- Current600: `/private/tmp/dabin-modularity-20261007/outputs/sustained-speed/zoom_performance_qa_output/performance.json`, SHA-256 `e42fe83d6bfbeb547ca6f588abf69a66140a30eb6d21e337466e4b91b3deeb29`.
