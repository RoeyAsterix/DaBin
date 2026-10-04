# DaBin monitor dragging — 3 October 2026

The open DaBin window moves between monitors using the logo, header grip, or top chrome. Existing movement code follows global pointer coordinates and chooses the destination display from the release pointer. This change fixes expansion/restore behavior that incorrectly turned an automatically sized window into a permanently manually sized window.

`CornerController.swift` now keeps automatic sizing when dragging an expanded window or restoring it. Short automatic Daily windows retain their height, Week can return to compact width, and compact positioning stays correct even when the route changes while expanded. Deliberately resized windows retain their manual size and minimum dimensions.

## Verification

- Baseline: the new regression cases reproduced six failures; the existing 37 native movement/resize interaction checks passed across two attached displays.
- Final Release run: nine focused suites passed, with no source changes during the run. WindowTests passed 259 checks across two actual displays; WindowResizeInteractionTests passed 37 checks, including release onto a second display and position retention after layout. Weekly, Workspace, Filter, robot transition, recording robot, presenter, and sign suites also passed.
- Tests used isolated temporary archives and preferences. No global cursor synthesis, user clipboard, network, or notification permission was used.
- The completed concurrent recording-sign changes were retained. Their separate four-suite, 349-check verification is recorded in `concurrent-sign-report.json`.

`final-report.json` and the adjacent logs record the detailed results. `monitor-source-attestation.json` confirms the tested monitor-related production sources matched the installed build receipt.

## Installed copy

Installed and reopened `/Users/roeylibfeld/Applications/DaBin.app`, version 0.4.24 (79). The guarded installer preserved the previous bundle at `/Users/roeylibfeld/Applications/.DaBinBackups/20261003-163017-7c199f20.app`. Strict code-signature verification passed; installed source fingerprint and executable hash matched the pinned build receipt. The running process path was checked and the reopened Daily window was verified through native accessibility state. Auto Capture remained paused.

The installation record is in `installation.json`; `installed-build-receipt.json` pins the installed sources independently of subsequent work in other chats.

## Scope

This change concerns the open application window. The small robot's placement behavior is unchanged. Verification ran on ARM64 macOS 26.6.2 with SDK 27.0; the complete suite and macOS 14 runtime were not run for this change. No personal capture edits were made, and no full archive byte inventory was performed.
