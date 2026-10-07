**DaBin 0.4.49 (104): full speed and stability campaign, 7 October 2026**

The full registered native Release App Store run completed with **130 of 131 suites passing**. WorkspaceZoomPerformanceTests failed the original steady-zoom timer p95 limit of 33 ms. The separate 600-second workload failed the same limit. Both input-to-layout p95 measurements passed their original 50 ms limit. Overall QA remains failed; no timing limit or failed check was waived.

| Check | Result |
|---|---|
| Full registered native suites | 130 passed, 1 failed; all 131 requested |
| Separate sustained zoom/arrivals workload | Failed steady-zoom timer gate; same compiled test/module reused |
| Python tooling tests | 60 passed, 3 failed out of 63 |
| Offline App Store preflight unit tests | 33 passed out of 33 |
| Deterministic Xcode project check | Failed: two test references missing |
| 10,000-record data-path benchmark | Exact search/load counts passed; timings are observations |

| Measurement | Full-run 30-second workload | Separate 600-second workload | Existing limit |
|---|---:|---:|---:|
| Synthetic input-to-layout p95 | 42.724 ms | 42.718 ms | 50 ms |
| Steady-zoom run-loop timer p95 | 34.158 ms, failed | 35.677 ms, failed | 33 ms |
| Maximum whole-run timer interval | 113.672 ms | 110.544 ms | Observation |
| Whole-run intervals above 100 ms | 8 | 18 | Observation |
| Durable save p95 | 26.499 ms | 30.538 ms | Observation |
| Initial/final retained records | 5,000 / 5,114 | 5,000 / 5,399 | Exact fixture assertions |

Each workload performs five 32-step zoom cycles and 160 synthetic inputs. The longer run sustains arrivals over 600 seconds; it is not 600 seconds of continuous zoom. Timer phase labels describe callback delivery and may include preceding operations. Idle-inclusive whole-run percentiles do not replace the failed steady-zoom gate. Marginal stage percentiles cannot be summed or used as causal profiler evidence. Metrics were written before the timing assertions; the four final post-gate visual renders did not execute in either failed run.

DurabilityStressTests passed 8,586 checks over 1,000 records, 320 mixed operations, 25 restarts and four real SIGKILL/recovery boundaries in 32.296 seconds. FlowActionStressTests passed 11,674 checks, including 6,134 handler invocations and 72 restart checks, in 8.602 seconds. These elapsed times have no speed gate. Graphics stress passed 93,867 geometry, interruption, control and disposal checks, including four controller disposals without stale completions. Preview decode/cache, rollback, lifecycle cancellation, video decoded-frame advancement and window responsiveness suites passed.

The 10,000-record benchmark used twelve production searches, each returning exactly 100 matches, and reopened all 10,000 saved records. Search median/max were 47.659/52.856 ms, metadata save 203.486 ms, deferred metadata reopening 284.804 ms and subsequent metadata reopening 289.094 ms. Explicit eager initializer/mirror synchronization attempts took 23.994 seconds. Production foreground initialization requests deferred repair; the eager value is not foreground startup latency. The unmodified benchmark does not assert every readable folder or per-record mirror error. It excludes thumbnails, OCR, UI latency and personal archives, and has no timing threshold.

Additional findings remain open:

- Ten NSTableView reentrancy warnings: seven in ProjectWorkspaceViewTests, two in SearchWindowTests and one in CaptionSelectionTests. All three suites passed. The framework warns about future assertions; these logs do not establish the cause.
- Three actor-isolation compiler warnings occurred in TaskPriorityTagTests' test Fixture.close(). Its compilation and 464 checks passed. Production module compiler output was empty.
- Metadata is still candidate 0.4.45 (100), while Info.plist is 0.4.49 (104). That shared identity mismatch causes all three Python metadata failures; they do not establish separate description-length or owner-field defects.
- The generated Xcode project lacks references/group entries for ColdVideoControllerTests.swift and WeeklyPresentationCacheTests.swift. Both suites were executed by the native runner. In-memory generator comparison found no production reference, resource, build-setting, linker or target difference.
- Physical cross-display dragging was skipped with one attached display. Video's eight Play/Pause accessibility attempts used direct AVPlayer fallback, with zero actual native button presses. Native playback controls, audio, AirPlay, PiP and decoder/OS variants remain unverified.
- Graphics fixtures validate offscreen behavior with explicit settings; actual OS accessibility settings remained false. Offscreen rendering and synthetic inputs do not measure physical presentation, GPU frame-rate or device latency. RSS includes fixture growth/caches and does not establish a heap-leak diagnosis.

The campaign ran on one arm64 Mac, macOS 26.6.2 (25G83), Apple Swift 6.4, SDK 27.0, target arm64-apple-macosx14.0. The 144-source optimized test core excludes the app main entrypoint; registered native coverage is distinct from eight additional render/manual/sandbox/Xcode entrypoints. Native test executables and offline policy fixtures do not establish signed sandbox, installer, upgrade, TestFlight upload or email readiness.

Production fingerprint: `85d7f1546715936c17e9867d0acf952459cfc98702faec5ebc12b5f7aca2e24f`. The frozen working-tree snapshot contains 406 pinned files. All production/QA inputs still matched the live source at final verification; source was not changed. All 132 compiled module/executable receipts verified output hashes after the full and sustained runs, with identical receipts across both. The benchmark verified unchanged module and executable hashes before/after execution. This is a QA freeze; no publication release freeze was established. The tested working tree contains uncommitted production changes. The recorded Git HEAD is its ancestry baseline; reconstructing this exact tested tree requires the pinned working-tree bytes retained in the isolated snapshot.

`source-freeze.json`, stage launch receipts, command logs, full/selected native reports, compiled-output verifications and `final-source-verification.json` pin the campaign. `raw-native-evidence.zip` retains exact native logs and generated JSON reports; its index lists individual byte hashes. Current durability output was generated inside the isolated snapshot despite the suite's historical hardcoded output-folder date. Stage logs and reports remain separate, so the later selected run cannot replace the full-run result. The frozen snapshot is retained at `/private/tmp/dabin-speed-stability-20261007-070033/snapshot`. The two recorded harness scripts retain the exact sequential commands and controlled environment. No inherited DABIN/DYLD overrides, keyboard skips, fixed-data override, signing authentication or archive/upload operation was used.
