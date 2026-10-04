# Distinct project card types — 0.4.27 (82)

Tasks, project notes and saved captures have separate, restrained treatments while retaining large previews and their project-colored outer frame:

- Tasks: checklist badge, slim status rail, square completion control, and an explicit Done state with struck-through text. Image/PDF/file tasks retain their original preview and subtype.
- Project notes: warm paper, faint ruling, pencil badge and serif text.
- Captures: neutral preview surface, Capture badge and quotation styling for saved text. Media previews remain prominent.

Type labels remain visible in compact view and expose their role/status to accessibility. Color is supplementary, not the only distinction. Project membership, original bytes, receipt dates, filtering, selection and opening behavior are unchanged.

Classification uses `capture.isTask`, including converted items. Only the live project scratchpad is unambiguously a Note; the archive does not distinguish an authored `.text` capture from manually pasted text, so no origin is invented. These saved items display Capture / Text in the project grid.

## Verification

Four existing focused Release suites pass, 852 checks, with unchanged run inputs: CaptureTaskConversionTests (173), ProjectWorkspaceStateTests (253), ProjectWorkspaceViewTests (185), WorkspaceWindowTests (241). The 1,002-item synthetic project retains at most 25 materialized native rows. Report: `native/build/qa/runs/20261003T162619727270Z/report.json`.

Wide/light and narrow/dark production project fixtures were visually reviewed. The existing non-fatal AppKit reentrant table-layout warning appears in the synthetic view test; this change does not claim to resolve it. This is focused UI regression coverage, not full-suite, minimum-OS or Store distribution validation.

## Dedicated card checks

`ProjectWorkspaceCardTests` passes **263 checks** against the exact retained Release module from the passing four-suite run. Its 117 production-source hashes match the report, and the current card source still matches. The suite checks all capture kinds and task precedence, manual/automatic text classification, live image conversion, completion/reopening, independent open/selection actions, unchanged original PNG bytes and visible thumbnail colors, and light/dark/grid/320-point compact layouts. Comparative native PNGs are included here.

The initial test assumed static SwiftUI labels always expose a separate AXValue. AppKit may omit it. The corrected test requires an explicit role label, checks for conflicting values, and verifies completion through the preview announcement and the real completion/reopen action labels. Production card behavior was unchanged by this test correction.

The direct test used the retained `DaBinTestCore` module at `native/build/qa-cache/1bdd49d432c58268636f439418b0d837d4662900deb652d31c2c1446f1252663`, with Swift 5 mode, ARM64 macOS 14 target, Release optimization, whole-module optimization and warnings-as-errors. `retained-module-receipt.json` preserves its input/output hashes. Its dylib SHA-256 is `59d8c00bc5cb7ec1a5a4be3968febec06beab1190f97b66417bfa8c4eb6aec60`.

## Local installation blocked by concurrent work

The build stopped because `AutoCaptureRobotPresenter.swift` changed during compilation. `RobotCharacterView.swift` and new robot-sign sources are also being edited in the active **DaBin personal daily board** chat. Those changes were preserved, not reverted or silently included in an unverified release. The retained-module card checks do **not** validate the newer robot code.

The installed application remains **0.4.26 (81)**. It was not quit or replaced, and no user archive, clipboard, capture preference or personal capture was changed. Combined-source QA, a fresh source-bound build, and local installation remain pending coordination with that chat; permission to coordinate was requested. No remote release or TestFlight/App Store submission was performed.
