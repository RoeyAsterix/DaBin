# DaBin 0.4.5 (58) — Window resizing and display movement

- Capture and task cards now include a visible trash icon, including minimized cards, Explorer and weekly view. It uses existing confirmation and recovery through Recently Deleted/Undo.
- Drag any of the four visible window corners to resize. Larger corner targets and diagonal cursors make the handles easier to find.
- Drag the top robot frame, logo, or unused header space to move DaBin, including between displays.
- Releasing a window over another display places it on that display, even when much of the window still overlaps the previous one.
- Manual size and placement remain local preferences. Content, project, selection and drafts stay mounted during resizing.
- Resizing respects the usable minimum and display safe area; moving keeps existing compact filter layouts intact.
- Display changes and dismissal cancel interrupted gestures cleanly.

The native SwiftUI/AppKit architecture, local archive, robot interactions, themes and existing actions are preserved. This is a local candidate; GitHub publication, notarization and TestFlight submission are separate release steps.
