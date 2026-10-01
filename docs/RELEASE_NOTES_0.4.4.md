# DaBin 0.4.4 · build 56

Local implementation of the supplied Open Design handoff, including Explorer. This is not a published GitHub or TestFlight release.

## Interface

- Neutral light/dark surfaces, thin rounded cards, fitted previews and a compact labeled Inbox / Today / Workspace / Activity navigation row.
- Shared searchable project picker with inline creation, validation, Unfiled and All projects scopes. Explorer, Clipboard, Shelf and Notes share the active project heading.
- Explorer keeps native copy, drag, import, file reveal, ZIP export, dated project documents and the responsive preview pane. Weekly columns use available width when fewer days contain captures.
- Source and manually recorded paste destinations use local application artwork with accessible fallbacks. History retains individual timestamps and clearly labels manual records.

## Tasks

- Convert a capture to a task in place. Its ID, receipt day, content, files and provenance remain intact. Undo is available until later task work makes conversion unsafe to undo.
- Edit task titles without replacing the original capture. Unfinished titles, notes and checklists recover with other drafts.
- Independent focus sessions support hours/minutes, start, pause, resume, reset and restart. Finishing a session leaves its task incomplete.
- Optional local planned time stays separate from receipt dates, deadlines and notification reminders.
- Immediate timer, schedule and project actions preserve unsaved editor changes. Recurring tasks retain their original source while starting with fresh timer and paste history.

## Local storage and privacy

Capture schema 10 adds optional timing and provenance fields; older captures continue to decode. Backup/restore and readable day/project files include the new metadata. App icons come from installed applications. Copy, app focus and file opening do not create paste receipts. No automatic cross-application paste monitoring or remote icon service was added.

Focus sessions store an end timestamp and remaining duration at transitions, not every second. Sleep, restart and forward clock changes follow that timestamp; a backward clock change cannot increase the displayed remainder above the amount last started. Planned HH:MM follows the local time zone; daylight-saving gaps resolve to the next valid local time.

## Verification

See `docs/qa/open-design-2026-09-30/` for the final native QA report, screen renders and the 80-feature preservation map. The supplied design bundle is retained with its verified checksum under `design/imported-redesign-2026-09-30/`; its older bundled source was used as reference only.
