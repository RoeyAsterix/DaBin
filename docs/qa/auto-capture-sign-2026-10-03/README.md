# Auto Capture confirmation signs

## Behavior

After a successfully persisted automatic action, DaBin uses one passive robot-and-sign panel. Screenshots say **Screenshot saved!**; clipboard actions say **Copied!**. Mixed bursts say **Captures saved!** with their exact count. A grouped multi-file paste counts as one action. No screenshot preview, copied text, filename, source application, or project name enters the sign model.

The existing project-recording placard remains a separate feature. Manual capture feedback keeps its existing behavior. Auto Capture pause, disable, service stop, and Quiet mode suppress these automatic signs immediately.

Normal performances last 1.805–1.997 seconds with at least 0.685 seconds of front-facing, readable text. Reduce Motion uses a static, approximately one-second peek/fade, with at least 0.652 seconds of readable text. No sound is added.

## Architecture and changed implementation

- `native/Sources/DaBin/AutoCaptureSignMotion.swift`: closed receipt vocabulary, saturated counts, twelve-reaction shuffled rotation, previous-three exclusion, timing and value keyframes.
- `native/Sources/DaBin/AutoCaptureSignRouting.swift`: successful automatic action to safe receipt mapping; best-effort system screenshot tool detection.
- `native/Sources/DaBin/AutoCaptureSignView.swift`: existing vector robot artwork, held sign, connected arms, native twelve-point type/SF Symbols, theme treatment and finite compositor animation.
- `native/Sources/DaBin/RobotCharacterView.swift`: additive body-part pose hooks for the confirmation scene.
- `native/Sources/DaBin/AutoCaptureRobotPresenter.swift`: one nonactivating, click-through panel, exact current/pending counts, one pending aggregate, interruption recovery, primary-display geometry and low-priority accessibility status.
- `native/Sources/DaBin/ApplicationCoordinator.swift`: successful-save wiring, enablement/Quiet mode gating, screenshot-tool observer cleanup, existing board/timer/interaction coordination.
- Three new suites: `AutoCaptureSignMotionTests`, `AutoCaptureSignPresenterTests`, `AutoCaptureSignRenderTests`; registration in `native/scripts/run_qa.py` and generated Xcode source inventory.

All motion finishes or is canceled; hidden signs have no continuing animation loop. Board opening, robot interaction and task timers own the robot while active. An unread sign is retained as one exact pending aggregate and resumes after the owner releases it. Display loss hides the panel and retains unread receipts. A replacement primary display uses its own geometry.

## Reaction library

1. Proud raise
2. Oversized unfold
3. Heavy pull downward and recovery
4. Wrong-side flip
5. Spin to face the user
6. Gentle head bonk
7. Hang and climb
8. Checkmark stamp
9. Slide with overshoot
10. Proud bow
11. Mechanical billboard
12. Last-moment catch

Timing, gaze and entrance offsets vary within fixed bounds. Burst-friendly choices remain subject to the same shuffled rotation and previous-three exclusion.

## Verification

**Passed: 9 targeted native Release suites, 4,663 checks, and an ARM64 Release build with strict local code-signature verification.** The final build uses the workspace's existing 0.4.27 (82) metadata. No version was bumped by this feature.

Final verification results are recorded in [verification.json](verification.json), with the [test report](native-test-report.json) and [build receipt](build-receipt.json). Tests use isolated stores, private named pasteboards, synthetic screenshots and injected displays/clocks. The 79 native render fixtures contain only generic receipt text and robot artwork; no personal captures are inspected.

Visual review: [twelve reaction poses](renders/light-reaction-contact-sheet.png), [dark readable holds](renders/dark-hold-contact-sheet.png), and [Reduce Motion](renders/external-reduced-motion.png). A 1,001-sample geometry check per reaction keeps visible signs within the small panel and below the notch.

Commands passed: `./scripts/test.sh` selecting the three new sign suites plus `ApplicationLifecycleTests`, `AutoCaptureServiceTests`, `AutoCaptureRobotPresenterTests`, `AutoCaptureRobotCelebrationTests`, `RobotLifecycleTests`, and `ProjectRecordingRobotTests`; `DABIN_SIGNING_IDENTITY=- ./scripts/build.sh`; `python3 scripts/generate_project.py --check`; `plutil -lint` for Info, entitlements and privacy manifests; and `git diff --check`. Swift compilation treats warnings as errors. No separate Swift linter is configured.

The build and tests used the same frozen source snapshot. All sign implementation/test files still match the working tree. A concurrent change to `NativeContentDrag.swift` occurred after the snapshot and is outside this feature's verification; see the exact hashes in the reports.

Issues discovered during this cycle and covered by regressions:

- Early count updates could shorten the readable deadline and lose an interrupted, unread confirmation.
- Native view layout could reset the sign transform independently from its animated hands.
- Ordering out a window could detach view layers from the root traversal and leave animation tracks running.
- A late burst could update the visible count after the single accessibility announcement.
- Disabling automatic signs could also clear unrelated legacy feedback.
- Wide and spinning reactions could clip against the small overlay; their authored poses now stay within its visible bounds.

## Platform limits

The sign for a screenshot starts only after that image is complete and durably saved. It cannot appear retroactively in that image. DaBin also suspends signs when it detects Apple's screenshot UI.

**Exclusion from every subsequent screenshot is not guaranteed.** Current macOS treats `NSWindow.SharingType.none` as a legacy hint and does not provide a public application-level veto over capture by other applications. An already visible sign can appear in a second screenshot, particularly one taken through another tool or API. [Apple's documentation](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none).

Injected display tests cover notch geometry, negative-coordinate external displays, loss and reconnection. Physical monitor unplugging, a real camera cutout and VoiceOver listening remain separate hardware/session checks. No new Screen Recording or Accessibility permission is requested by the confirmation feature.

This is a source/build validation cycle. Publishing and installation remain on hold; there is no GitHub release, notarization or TestFlight upload from this work.
