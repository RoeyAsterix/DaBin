# Changelog

## 0.3.10 — 2026-09-24

- Added a dedicated **Text** filter immediately before Links in the centered filter row.
- Used DaBin's existing aligned-text SF Symbol and purple filter treatment, with the tooltip and accessible name **Copy/paste text**.
- Limited the filter to copied, pasted or dragged plain text, excluding links, tasks and document files.
- Applied the filter consistently to Daily, contextual Search, Weekly and automatic hourly groups without changing active Weekly dates.

## 0.3.9 — 2026-09-24

- Removed empty dates from Weekly while preserving the complete seven-date navigation range.
- Counted carried tasks and reminder-day tasks as activity so the dates where they appear remain visible.
- Sized the Weekly panel to its active date columns and kept a completely empty range at the compact bored-robot view.

## 0.3.8 — 2026-09-24

- Added **Export Day** between Search and Notifications with **Copy Day** and **Export Text File** actions.
- Exported the complete selected calendar date in chronological order, independently of the active content filter, with timestamps, types, source applications and available text.
- Preserved multi-item capture boundaries in the export, added clear image placeholders when no caption or OCR text exists, and made clipboard and file output byte-for-byte equivalent UTF-8 text.
- Added empty, success, cancellation and failure handling, plus keyboard shortcuts, focus treatment, accessible labels, Escape dismissal and outside-click dismissal for the export popover.
- Rebuilt Daily and Weekly navigation as three compact rows for navigation, primary actions and filters, removing the previous vertical dead space while retaining narrow-window behavior.
- Restyled Add, Search, Export Day, Notifications and Settings with the filter icon language, kept their rows centered on one axis, and preserved the neutral independent window-close control.

## 0.3.7 — 2026-09-24

- Replaced the Daily and Weekly header's three-dot options icon with an outline settings wheel.
- Matched the wheel's size, colour and hit area to the adjacent task, search and reminder icons.
- Renamed the control's help and accessibility label to **Settings and options** while preserving its existing menu actions.

## 0.3.6 — 2026-09-24

- Replaced flat separators on individual caption cards with thin, continuous rounded frames in Daily, Search and Reminders.
- Kept the stronger theme-colour outline for carried tasks while giving ordinary cards a quiet neutral frame in light and dark appearances.
- Preserved the existing hourly-action frame without adding a competing nested outline, and adjusted compact panel sizing for the new card spacing.

## 0.3.5 — 2026-09-23

- Added opt-in **Auto Capture** under Settings → Capture, off by default, for future clipboard changes and new screenshots written to a user-selected folder.
- Added visible enabled, paused, permission and exclusion states; a quick Pause command; and default exclusions for DaBin and common password managers.
- Stored automatic action origin, timestamp, content and best-effort source-application metadata in the existing local archive, with cross-channel image duplicate suppression and no automatic website-preview requests.
- Grouped the fourth successful automatic action in a fixed local clock hour into one expandable summary with a stable count and accessible minus control.
- Added a passive success robot on the hardware primary display, with safe-area placement, burst counting, screen-capture exclusion and Reduce Motion support.
- Preserved immediate cancellation on Pause or Off, prevented pre-existing clipboard and folder contents from importing, and withheld success confirmation for failed or partly failed actions.

## 0.3.4 — 2026-09-23

- Superseded 0.3.3 and carried forward its compact **Daily / Weekly** segmented control, selected-date anchoring, filter and scroll continuity, drafts, panel transition and Reduce Motion behavior.
- Replaced the sandbox-incompatible updater launch-argument handoff with a private, one-use document beside the verified ZIP.
- Made the installer validate the document owner, permissions, schema, package name, location and SHA-256 before consuming it and independently checking the package as before.
- Kept the local capture archive outside the update flow and unchanged during installation.

## 0.3.3 — 2026-09-23

- Replaced the separate Today and This Week actions with one compact **Daily / Weekly** segmented control.
- Anchored Daily → Weekly to the selected day and made Weekly → Daily return without resetting the selected date, type filter, Daily scroll position or unsaved drafts.

This release is superseded by 0.3.4 because its direct updater still relied on launch arguments that macOS does not deliver from the sandboxed caller.

## 0.3.2 — 2026-09-23

- Requested a fresh embedded-updater instance to avoid helper-process reuse; later live QA showed that sandboxed LaunchServices still discarded the ZIP path and SHA-256 arguments, so 0.3.4 replaces this transport.
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
