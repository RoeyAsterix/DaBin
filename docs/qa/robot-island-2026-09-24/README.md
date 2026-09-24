# Robot island, eating and application transformation

This change extends the existing native AppKit/Core Animation character. It adds
no animation dependency, audio, capture preview storage, network request or archive
schema change.

## Behavior

- Ten generic-token eating styles use a shuffled rotation excluding the previous
  three. One grouped automatic receipt counts as one action, even if it contains
  several files. Failed saves never invoke the success presenter.
- Counts aggregate in constant memory. Captures received during manual interaction,
  the open board, late retreat or display loss are retained for one later aggregate.
- Opening has priority. The live Daily hosting view stays mounted while its robot
  frame climbs/braces, splits and expands in 1.15 seconds. Reversal starts from the
  current presentation pose. X, Escape and Command W close in 0.42 seconds.
- Head, hands and feet have dedicated layout space. The original content remains
  380 points wide. Its theme and transparency remain authoritative. Gaze is clamped
  and eased using the existing controller pointer tick; hidden views stop motion.
- Reduce Motion uses a 0.14-second application fade, a static frame and the short
  success peek/check/fade. Compatible laptop notch geometry comes from macOS safe
  areas; the no-notch/external fallback is top-right.
- Display changes settle interrupted transitions and reposition silently. Shutdown
  removes all owned panels and pending animation work immediately.

## Verification

The accompanying full run report identifies every source/test input by SHA-256.
Native tests use isolated archives, private pasteboards and fake reminder services.
Visual files contain the code-drawn robot and an empty fictional board, not user
captures. The screenshot date comes from the test machine's clock.

- Full optimized Release suite: **36/36 passed**, with unchanged inputs during the run; see `full-run-report.json`.
- A subsequent visual alignment correction to the application frame passed **7/7 focused suites** against the final sources; see `final-window-frame-report.json`. Storage and capture logic did not change in that correction.
- Native robot renders: 39 Retina-scale renders; ten distinct eating peak rasters,
  light/dark appearance, Reduce Motion static frames and motion cleanup. The final
  run passed after correcting the snapshot context scaling and phase sampling;
  see `robot-personality-renders.json` and `robot-render-checks.log`.
- Native window transition suite: **27 checks**; frame geometry, transparency and lifecycle: **31 checks**; AppKit event loop, actual mounting/layout,
  interruption/reversal, close commands, screen-configuration notification and
  shutdown. The general window suite exercises two attached displays.
- Xcode Release build with code signing disabled passed.
- Deterministic Xcode inventory and `git diff --check` passed.

Commands: `./scripts/test.sh`, the seven-suite focused run listed in its report,
`./scripts/render_qa.sh --robot-personality`,
`xcodebuild -quiet -project DaBin.xcodeproj -scheme DaBin -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build/xcode-animation-qa CODE_SIGNING_ALLOWED=NO build`,
and `python3 scripts/generate_project.py --check` (from `native/`).

## Practical limits

The app keeps its established compact/full-view window rather than entering a
native macOS fullscreen Space. Physical display unplugging was simulated through
screen providers and configuration events; geometry was also checked on the two
connected displays. A real unplug/replug session and macOS 14 hardware check are
still useful release validation.

The success sequence starts only after a stable screenshot/clipboard import has
saved. Decorative panels request `NSWindow.sharingType = .none`. macOS has no
universal public notification before every external screenshot, and some modern
capture APIs can include such panels. DaBin does not initiate the system screenshot,
so it cannot guarantee hiding an already visible overlay from every other tool.

This is implementation and QA evidence. It does not create a signed/notarized
installer, update an installed application, or publish a GitHub Release.

## Changed files

- Motion policy and rendering: `native/Sources/DaBin/RobotLifecycle.swift`,
  `AutoCaptureRobotCelebration.swift`, `AutoCaptureRobotPresenter.swift`,
  `RobotCharacterView.swift`, `RobotAppFrameView.swift` and `RobotView.swift`.
- Integration: `CornerController.swift`, `DailyCaptureView.swift`,
  `ApplicationCoordinator.swift` in that same source directory.
- New tests: `RobotLifecycleTests.swift`, `RobotAppFrameTests.swift`,
  `RobotWindowTransitionTests.swift` under `native/Tests`.
- Updated tests: `AutoCaptureRobotCelebrationTests.swift`,
  `AutoCaptureRobotPresenterTests.swift`, `DailyCaptureTests.swift`,
  `FilterResizeTests.swift`, `NativeRenderTests.swift`, `RobotDropTests.swift`,
  `WeeklyWindowTests.swift`, `WindowTests.swift`.
- Inventory and documentation: `native/scripts/project_inventory.py`,
  `native/scripts/run_qa.py`, `native/DaBin.xcodeproj/project.pbxproj`, root/native
  README files, `native/ARCHITECTURE.md`, `native/QA_RESULTS.md`, and this folder.

## Visual review

- [Final app frame](robot-full-view.png)
- [Opening seam](opening-seam@2x.png)
- [Opening body and live content](opening-body@2x.png)
- [Eating motion contact sheet](eating-contact-sheet.png)
- [Eyes-first anticipation](native-robot-personality-auto-phase-anticipation@2x.png)
- [Climbing entrance](native-robot-personality-auto-phase-entrance@2x.png)
- [Grouped capture token](native-auto-capture-island-burst-dark@2x.png)

The frame snapshots are local presentation-layer captures. The host display's
backing scale determines SwiftUI text raster resolution inside the 2x canvas.
