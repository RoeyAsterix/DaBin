# Preview-first projects — local verification

DaBin **0.4.25 (80)** was built, installed and relaunched on 3 October 2026.
This implements the selected project-workspace concept in the native app; the
HTML concept is not embedded in the application. TestFlight remains paused.

## Results

- **16/16 focused Release suites passed**, totaling **1,630 checks**, with no
  source changes during the final run. This is selected regression coverage,
  not a claim that every registered suite was rerun.
- New workspace state: 236 checks, including 100,000-ID ordering, stable grid
  row groups, hidden-selection cleanup, legacy workspace loading, additive
  backup restoration, atomic conversion, rollback, inherited project ownership
  and guarded undo.
- New project export: 49 checks for original bytes, complete scope, exact item
  and note ordering, task/checklist metadata, missing originals, safe paths,
  no-overwrite publication, and a private test pasteboard.
- New native workspace UI: 109 checks with 1,000 synthetic text captures,
  one image and live notes; widths 320–1080; selection/filter behavior; grid and
  compact previews; four new captures while scrolled. At most **23 native rows**
  materialized at once. Existing capture snapshots and image bytes are retained.
- Existing Explorer responsiveness: 169 checks, 128 automatic captures,
  preview completion, 16 insertion bursts, resize/close/reopen and an eight-second
  run-loop watchdog; at most 20 materialized rows. Keyboard, workspace navigation,
  backup, search scope, clipboard, local-file locations and recording robot suites
  also pass.
- Generated Xcode inventory and `git diff --check` pass. Release ARM64 build,
  clean-copy and installed strict code signatures pass. Installed executable
  SHA-256 matches the build receipt:
  `43da18ec2c040419f769c5f0cc18489cd1eb51357fe35cf881b7925bffe202a9`.
- Build source fingerprint:
  `31ec0636fe41c7db96317e2ecbfc399c686cfc5d506f151e6343fffbdba11f34`.
  Build inputs were compared again after installation and remained unchanged.

## Local installation

Installed at `/Users/roeylibfeld/Applications/DaBin.app` using the repository's
guarded installer. The previous app is recoverable at
`/Users/roeylibfeld/Applications/.DaBinBackups/20261003-182628-42dabb58.app`.
The installer does not read, move or delete the capture archive.

Live accessibility checks confirmed the new Project workspace, project-wide
copy/export, filters, grid/compact control and live notes. Select all revealed
the bulk actions; Clear selection restored the unselected view. No personal
capture was converted, copied, reordered, exported or deleted during live QA.
The app was left open in Projects. Auto Capture remained paused.

## Evidence and limits

- [Final test report](native-report.json), [build receipt](build-receipt.json)
- [Project UI log](ProjectWorkspaceViewTests.log), [export log](ProjectWorkspaceExportTests.log),
  [model log](ProjectWorkspaceStateTests.log)
- [Wide native fixture](project-grid-wide@2x.png), [320-point fixture](project-grid-narrow@2x.png)

The images are real native views using fictional local fixtures, not the user's
personal archive. The live screenshot service returned blank pixels despite
working accessibility controls; live appearance was not claimed verified from
that screenshot. Native fixture renders were visually inspected instead.

AppKit still logs the previously documented non-fatal reentrant table warning
during forced fixture layout. The tested run loop and scrolling remain responsive;
this does not establish the warning is fixed or guarantee freedom from all freezes.

Earlier runs found and corrected an export-root bug, missing test accessibility
initialization, obsolete navigation assertions and a concurrent test-cache build
collision. Only the final stable-source report is the completion authority.
No remote Git push, binary publication, Apple signing/notarization or App Store
submission occurred. Existing unrelated working-tree edits were preserved.
