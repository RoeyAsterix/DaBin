# DaBin 0.4.5 (59) — Window resizing and display movement

- Inbox now contains a visible Day / Week toggle. Week opens the existing seven-day calendar directly, while To organize preserves the undated capture queue. Calendar selection, filters, drafts, weekly search/export and empty-day hiding are retained.
- Capture and task cards now include a visible trash icon, including minimized cards, Explorer and weekly view. It uses existing confirmation and recovery through Recently Deleted/Undo.
- Drag any of the four visible window corners to resize. Larger corner targets and diagonal cursors make the handles easier to find.
- Drag the top robot frame, logo, or unused header space to move DaBin, including between displays.
- Releasing a window over another display places it on that display, even when much of the window still overlaps the previous one.
- Manual size and placement remain local preferences. Content, project, selection and drafts stay mounted during resizing.
- Resizing respects the usable minimum and display safe area; moving keeps existing compact filter layouts intact.
- Display changes and dismissal cancel interrupted gestures cleanly.

The native SwiftUI/AppKit architecture, local archive, robot interactions, themes and existing actions are preserved. This is a local candidate; GitHub publication, notarization and TestFlight submission are separate release steps.

## Quiet Orbit robot — build 60

The new metallic robot has seven notch perches, quiet idle, small saved-capture eating reactions and readable confirmation/count badges. Hit targets remain usable, transparent hardware margins pass clicks through, and interrupted movement recovers cleanly. Existing native paste/drop and open commands remain available. 15 targeted suites pass; all 40 captures and 16 originals are preserved after local installation. [QA and visual evidence](qa/quiet-orbit-2026-10-01/README.md).
