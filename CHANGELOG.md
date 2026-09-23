# Changelog

## 0.3.3 — 2026-09-23

- Replaced the separate Today and This Week actions with one compact **Daily / Weekly** segmented control.
- Anchored Daily → Weekly to the selected day and made Weekly → Daily return without resetting the selected date, type filter, Daily scroll position or unsaved drafts.

## 0.3.2 — 2026-09-23

- Forced the embedded updater to open as a fresh LaunchServices instance so the verified ZIP path and SHA-256 arguments always reach it.
- Added the underlying updater error to the native failure alert instead of showing only a generic heading.

## 0.3.1 — 2026-09-23

- Added **Settings → Your quiet corner → Below camera island** for Macs with a built-in camera island.
- Used macOS screen safe-area and auxiliary top-region geometry to place the robot below the real camera cutout; displays without that geometry continue using their corners.
- Rebuilt the transient robot as a native character that peeks in, follows the pointer, welcomes a drop, digests a capture and reacts to successful, partial and failed saves.
- Added quiet idle blinks, glances and shrugs while the robot is visible, with animation work stopped when it hides.
- Respected the macOS Reduce Motion setting by keeping the robot's expressions while removing positional, repeated and keyframed movement.
- Kept the robot-home choice in a local app preference, separate from captures and the movable Daily-board position.

## 0.3.0 — 2026-09-23

- Added a user-initiated GitHub Releases update check in Settings and the app menu.
- Added verified in-app download using a fixed HTTPS origin, exact size and SHA-256 checksum.
- Embedded a signed update helper in direct builds; it confirms, re-verifies, backs up, replaces and relaunches DaBin while preserving the local capture archive.
- Kept the direct update downloader and helper out of the Mac App Store build path.
- Added dark mode and transparency controls.
- Grouped files received in one paste or drop into one caption card.
- Updated the one-page PDF guide and privacy documentation.

## 0.2.2 — 2026-09-23

- Added dark mode and board opacity settings.
- Added grouped multi-file capture cards.
- Completed the local update package and expanded release QA.

Earlier implementation history is recorded in [native/IMPLEMENTATION_NOTES.md](native/IMPLEMENTATION_NOTES.md) and [native/QA_RESULTS.md](native/QA_RESULTS.md).
