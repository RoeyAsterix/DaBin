# Window resizing and display movement — DaBin 0.4.5 (57)

## Changes

The visible application surface is inset from its transparent robot frame. Previously, corner resizing required hitting a six-point outer rail, with a six-by-six point diagonal intersection. The four visible card corners now have 24-point target regions clipped to the window, while existing outer edge resizing remains available. Native diagonal cursors are used on macOS 15 and later; macOS 14 uses a vector-drawn cursor.

The reserved top robot frame can move the window on every page, including compact Explorer where the project picker uses much of the header. Content buttons retain their own hit testing. Logo and unused header dragging remain supported. Global display coordinates maintain a continuous drag across monitors.

On release, the display under the pointer wins over the old top-left anchor. The final window fits that display's usable area. A pointer in a display gap falls back to the largest window/display intersection. Manual size and placement use the existing local preferences, independent of the archive. Moving a short automatic filter layout does not enlarge it to the manual resize minimum. Display configuration changes and dismissal cancel active frame/header gestures.

## Verification

**9/9 focused suites passed** against the final source, with no changes during execution. The suite includes 83 frame/geometry checks, 37 new native resize/movement checks, 243 existing window checks, 97 weekly-layout checks, 110 filter-resize checks, 172 header interactions, 209 responsive Workspace checks, robot-window transitions and 27 update-configuration checks. Tests exercised two real attached displays, including release with most of the window still overlapping its former display.

The ARM64 Release build passes with warnings treated as errors. Generated-project validation, source packaging checks and whitespace checks pass. All 108 shared QA/build inputs match. This was a targeted regression run, not another full-application suite run.

**0.4.5 (57) is installed and running from the user's Applications folder**, with an exact executable hash match and valid strict signature. The prior app bundle and a verified private archive/preferences backup are retained. All 40 prior capture IDs, content and user metadata remain intact; all 16 original attachments are byte-identical. One existing preview completed from `idle` to `ready` during normal launch processing. The updated native window was confirmed open through its accessibility tree.

- [Focused QA report](focused-qa-report.json)
- [Build receipt](build-receipt.json)
- [Installation and preservation verification](installation.json)
- [Native corner/movement checks](WindowResizeInteractionTests.log)
- [Frame geometry checks](RobotAppFrameTests.log)

The isolated empty QA app was visually inspected. It uses the production renderer; only this temporary preview permitted screenshots. The computer-use drag API returned `AXError.notImplemented`, so pointer gestures were verified through direct AppKit mouse events in the isolated native test suites. The production screenshot privacy setting remains unchanged.

An initial test cycle caught a regression where moving a compact filtered window applied the larger manual-resize minimum, shifting its top edge. Release-time placement now preserves its existing size. The initial cycle is retained in the native build QA directory; the final report is authoritative.

## Files

- `native/Sources/DaBin/BoardResizeGeometry.swift`: corner targets, drag region, display selection and bounded placement.
- `native/Sources/DaBin/RobotAppFrameView.swift`: actual frame mouse events and resize cursors.
- `native/Sources/DaBin/WindowDragHandle.swift`: shared screen-coordinate drag session and release callback.
- `native/Sources/DaBin/CornerController.swift`: destination display selection, persistence and interruption recovery.
- `native/Sources/DaBin/AppState.swift`, `BoardView.swift`: native header gesture callbacks.
- `native/Tests/RobotAppFrameTests.swift`, `WindowResizeInteractionTests.swift`: targeted geometry and actual native mouse-handler regressions.
- Version metadata, QA registration, generated Xcode project, README and release notes.

## Privacy and limitations

Tests use isolated archives and preferences with fictional content. Live personal capture screenshots were rejected by automatic approval review; verification uses the isolated QA window instead. No user clipboard, capture contents, network services or notification permissions are needed. Real attached displays are exercised where available; physical cable disconnection, different display scaling settings and macOS 14 cursor appearance require separate hardware/OS verification.

This is a local update, not a GitHub or TestFlight publication.
