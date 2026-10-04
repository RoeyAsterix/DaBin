# DaBin 0.4.22 (77): Auto Capture / Explorer responsiveness

This local update addresses the Explorer layout path found busy in the frozen app while Auto Capture was being used.

- Explorer now gives each section heading and capture its own stable lazy-list identity. Incoming captures no longer change the number of sibling views belonging to a section identity.
- Card footers measure and place one set of actions, preserving a single content-trail/popover instance when the available width changes.
- Dismissing already-empty feedback no longer publishes redundant changes back into disappearing cards. Real feedback still expires after two seconds, and cancellation cannot hide a newer message.
- Capture storage, opt-in monitoring, local indexing, clipboard permissions and the robot's appearance are unchanged by this fix.

## Evidence and limitations

The five-second sample of the actual frozen 0.4.21 process found its main thread continuously in SwiftUI graph updates and lazy Explorer layout, with the process using approximately one CPU core. The sample did not show a blocked archive write or a robot animation loop. It is retained locally in `native/build/qa/autocapture-freeze-2026-10-02/frozen-process.sample.txt` and is not published with source.

The initial synthetic baseline and expanded pre-fix BoardView baseline both passed. The exact live hang therefore has **not** been deterministically reproduced. These changes remove concrete invalidation/identity hazards from the sampled path; passing tests are not a guarantee that the app can never freeze.

The [12-suite Release run](../native/build/qa/runs/20261002T082359108448Z/report.json) passes: automatic capture service, robot presenter, Explorer queries, workspace interactions, window transitions, timestamps, preview caching, card presentation, tooltips, notifications, configuration, and the new live Explorer stress test. That stress test saves 128 fictional automatic captures, loads delayed local previews, retains a selected image, and repeatedly scrolls/resizes with task cards, paste trails and tooltips present. An independent background watchdog fails a stalled main thread. Reopening the isolated archive verifies all capture IDs remain durable. The original private archive and system clipboard are not test fixtures.

Native card renders at narrow and normal widths retain complete previews, date/category labels and controls. The stress fixture was then extended to production `DailyCaptureHostingView` inside `RobotAppFrameView`, including captures during closing, reversal, and full close/reopen. The [final run](../native/build/qa/runs/20261002T082948691261Z/report.json) passes **114 checks**. The twelve-suite report's earlier stress fixture is superseded by this stronger passing version; the other eleven suites and all production inputs are unchanged.

## Local recovery and installation

**0.4.22 (77) is installed and running locally.** After the unresponsive process could not answer a native UI request, its exact executable/PID was checked and it was stopped with SIGTERM for replacement. The guarded installer preserved the previous bundle at `/Users/roeylibfeld/Applications/.DaBinBackups/20261002-112816-f4e2f4d4.app`. Strict signatures, version, embedded source fingerprint and both executable hashes match the Release receipt; all 138 build inputs still match current files.

Live Settings confirms the version and existing preferences. Explorer opens the existing project, scrolls, expands to show its inspector, and restores to compact without hanging. The relaunched process idles normally rather than consuming a full CPU core. Auto Capture is **left paused as found**; clipboard/screenshot choices and tooltips are retained. No personal capture was opened, copied, edited or generated for testing. The installer replaces app bundles, not the archive; the archive was not independently byte-inventoried. Any capture interrupted before its durable save may need to be taken again.

This is a local stability candidate, not App Store approval or a public release. No commit or push was made. [Verification receipt](qa/autocapture-freeze-0.4.22-2026-10-02/verification.json).
