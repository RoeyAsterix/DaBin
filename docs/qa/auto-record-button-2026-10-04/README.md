# Auto Record button — DaBin 0.4.29 (84), 4 October 2026

Installed locally: the Auto Capture header now has a red record dot inside a thin ring. Idle, paused and waiting states show an 8-point dot. A running capture channel shows a 16-point dot and two gentle alternating hops over 1.6 seconds. Motion stops when paused, hidden or detached; Reduce Motion keeps the recording dot large and stationary. The red ring and subtle glow reinforce the active state. Layer animation does not run a repeating SwiftUI timeline update.

Setup/pause/resume, the 40×34 hit target, hover/focus treatment, help and accessible status remain available. Enabled-but-not-running capture never claims to be recording; a running clipboard channel remains active even if screenshot access is unavailable.

## Verification

Six focused native Release suites pass, totaling **811 checks**, with unchanged inputs: AutoRecordIndicatorTests (117), AutoCaptureServiceTests (75), TooltipBehaviorTests (158), TooltipPresentationTests (146), SearchInputTests (65), and HeaderInteractionTests (250). [Machine-readable summary](verification-summary.json).

The new fixture measures actual layer bounds and Core Animation presentation positions over real elapsed time (maximum sampled movement: 2.55 points). It verifies pause, disabled, waiting, reduced motion, hidden presentation, detach/reattach and teardown cleanup. Native header tests click both the dot center and padding outside the drawing, and exercise accessibility activation; setup opens without starting capture or changing stored items. [Indicator/capture/input run](native-indicator-regressions/report.json), [header run](native-header-regressions/report.json).

Light and dark native PNG previews were reviewed at 2×: [light](renders/auto-record-light-idle-recording@2x.png), [dark](renders/auto-record-dark-idle-recording@2x.png). The strips show the stationary idle and recording sizes; motion is verified by real compositor samples. Isolated production-header images are retained in `header-renders/`.

Source packaging and metadata checks pass, and generated Xcode files are current. The Release app builds with warnings as errors and strict code-signature validation. [Packaging](source-packaging.txt), [metadata](metadata-check.json), [build receipt](build-receipt.json).

## Installed candidate and scope

The installed bundle is `/Users/roeylibfeld/Applications/DaBin.app`, version **0.4.29 (84)**. Its source fingerprint and both app/updater executable hashes match the signed build receipt. The prior app is retained in the installer backup recorded in [installed verification](installed-verification.json).

The running app exposes Resume Auto Capture with its existing paused status. Search is empty and focused, 60 saved items remain, and the existing quick-capture draft is preserved. Capture settings were not changed. The app's screenshot exclusion produces a blank live capture, so appearance is verified through isolated native fixtures; recording was not enabled on the user's archive to demonstrate animation.

The candidate at `/private/tmp/dabin-record-control-20261004/native` starts from the previously installed, fully tested 0.4.28 baseline and adds only the two recording-control production files. Separate tutorial work in the shared workspace is preserved and excluded. [Source comparison](frozen-candidate.json), [prior full QA](../full-qa-2026-10-04/README.md). Tested changed source and tests are retained in `retained-tested-sources/`.

An initial header test copy included concurrent tutorial tests that do not belong to this frozen baseline; it failed compilation, with logs retained in `header-attempt-incompatible-concurrent-test/`. Only that unrelated block was excluded from the frozen test; the shared tutorial tests remain intact. The matching header suite passes. Xcode regeneration was rerun after adding the new test.

## Limits

These are local ARM64 checks on the macOS/SDK versions recorded in the reports, not distribution or macOS 14 runtime certification. Keyboard Space activation of the record button remains untested under the current macOS keyboard-navigation setting; native pointer and accessibility activation pass. The header fixture could not activate its process for immediate Search typing; the dedicated 65-check Search input suite passes, and installed Command-K restores query focus. No public release, upload or Store submission was performed.
