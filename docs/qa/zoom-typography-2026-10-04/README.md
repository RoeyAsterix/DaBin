# DaBin — restrained zoom typography

## Change

Workspace zoom previously multiplied all text by the full 75–200% workspace scale. The new shared typography metric maps this range to 95–120% font sizing. Native text remains sharp; line spacing follows the same restrained factor. Geometry, previews, pointer targets, scroll anchoring and zoom preferences retain their existing behavior.

Capture detail headings and body text use the physical viewport for responsive sizing. This prevents text shrinking when zoom reduces a fixed window’s logical layout width. They remain capped at 28 and 17 points respectively.

The changes apply to captures, task cards, project cards, search results, grouped captures, weekly headings, notes and relevant editors. Default 100% font sizes are unchanged. Independent document magnification in Extended View retains its existing behavior.

## Evidence

- `before-inputs.json`: source/test hashes before this adjustment.
- `changed-files.json`: files changed during this adjustment (unrelated pre-existing changes preserved).
- `typography-migration.json`: shared font/leading call sites migrated.
- `before-*.png`: prior native-render fixtures for comparison.
- `renders/`: updated native fixtures at 75, 100, 150 and 200%, both themes; narrow 380-point cards at 200%.

## Verification

- **8/8 targeted native suites passed**: WorkspaceZoomLayoutTests, WorkspaceZoomTests, WorkspaceWindowTests, ProjectWorkspaceCardTests, TodayTaskCardTests, SearchWindowTests, WeeklyWindowTests and CaptureZoomStateTests.
- New metric coverage verifies bounded and monotonic typography through 126 zoom factors, proportional line spacing, and responsive capture-detail limits at four widths. Existing native tests check anchoring, control visibility, focus, keyboard behavior and card interactions.
- Native visual inspection: 75% and 100% light cards, 200% light cards, and 380-point dark Today cards at 200%. The narrow title now uses two lines instead of four, with visible metadata and actions.
- `git diff --check` and generated Xcode project consistency passed.
- Tests compiled the production code with warnings treated as errors. Inputs remained unchanged during the run (`sourceChangedDuringRun: false`).
- This was a focused typography regression run, not a rerun of the prior full application QA cycle.

Local ARM64 Release build passed and was installed at `~/Applications/DaBin.app`. The previous app is preserved for rollback. The app was reopened on Inbox; the running executable and embedded updater hashes match the new build, the source receipt is current, and strict signature verification passed. See `verification.json` and `build-receipt.json`.

The local app retains version 0.4.31 (86); this is a local revision identified by source fingerprint `e892b3d2e37de51cd2114e9e9731e97d7926ffa46de878ad004b3fe76bb833ef`. No public release, version bump, push or App Store submission was performed.
