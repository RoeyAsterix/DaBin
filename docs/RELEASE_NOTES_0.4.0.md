# DaBin 0.4.0 — local candidate

Version **0.4.0**, build **48**. This is a local candidate, not a publication, TestFlight delivery or Apple acceptance announcement. See [native QA results](../native/QA_RESULTS.md) for checks actually completed and remaining verification.

DaBin now centers on saving, finding and resuming work. The native robot remains available, while a simpler main window gives saved content more space and makes common actions explicit.

## A more playful camera island

The robot now treats the laptop's physical camera island as a ledge. It hooks its hands over the edge, lowers itself, swings one-handed while eating a capture, catches a small slip, shuffles sideways, and pulls itself back up. Occasional idle invitations peek upside down and wave. The existing capture styles select among these three physical acts; the previous-three reaction exclusion and exact burst counts remain.

Hands stay attached to the edge while the body moves. The real island occludes the robot; an artificial housing is no longer drawn. A wider transparent animation stage leaves the surrounding desktop click-through, while the central robot remains a stable drop and click target. Opening the board starts from that central body. Displays without an island retain their compact corner behavior.

macOS Reduce Motion uses a short static confirmation. Quiet mode suppresses idle invitations and automatic celebrations. In Settings, **Below camera island** selects the manual robot's home on compatible hardware; existing placement preferences remain in place.

[Watch the native animation preview](qa/island-playground-2026-09-29/DaBin-Island-Playground.mp4). It uses the production character renderer over a fictional desktop; it is not a recording of an installed update.

## Find your way around

- **Today** shows captures received on the selected day. Older unfinished tasks move out of this feed into Follow-ups; their receipt dates stay unchanged. Automatic hourly batches remain expandable.
- **Library** covers the archive across dates. Pin useful captures and optionally assign projects. A project's pinned references, next actions and recent captures provide a place to resume work without requiring every capture to be filed.
- **Follow-ups** combines unfinished tasks and reminders in Due now, Later and Anytime. Complete finishes the task or clears the reminder; Snooze moves it to tomorrow at 9:00 in the current time zone.

Persistent **Search all captures** and **⌘K** use the full archive, including when invoked from Week or a project. Results show matches first; nearby same-day captures are optional. Type filters are labeled. Local OCR and document text indexing remain available, with matched text shown on results.

**Timeline → Day / Week** preserves date browsing. The date button opens a calendar in either mode. Weekly retains its existing active-date columns and task continuity behavior.

## Capture and act

**Add** now offers Paste clipboard, New note, Import files and New task. Compact capture cards show their content, saved notes and reminders, with Copy and More actions. Detail supports pinning, project selection and creating a project name. **More** holds Settings, day/week text export, Recently Deleted and archive backup/restore.

Automatic **Clipboard** and **Screenshots** capture have separate opt-in switches. Both default off. Clipboard capture does not require screenshot-folder permission, and a screenshot permission problem does not stop the clipboard channel. Pause/Resume controls the selected channels together, with visible status.

Global shortcuts default to **⌃⌥Space** for Search and **⌃⌥V** to save the clipboard. Settings can disable them or use Control + Option + Shift instead; shortcut registration conflicts are reported. **Quiet mode** skips automatic capture celebrations and opens the board promptly. macOS Reduce Motion remains respected.

## Recover and back up

Removal now moves a capture to **Recently Deleted**. Undo restores the latest removal; the deleted-items view supports restoration and separately confirmed permanent deletion. Original source files stay untouched.

A local `.dabinbackup` directory package stores capture metadata, saved originals, readable records, saved local edits, available previews, pins/projects and Recently Deleted. Preferences, credentials, the live database and transient import jobs are excluded. Restore verifies the package and adds missing captures. Identical existing captures remain; metadata or file conflicts stop restoration without replacing them.

## Compatibility and limits

- New appearance preferences default to an opaque board. Existing installations retain their saved transparency setting.
- Screenshot capture watches only new image files in the chosen Mac folder. It does not import that folder's existing contents or discover screenshots saved elsewhere. Clipboard monitoring likewise does not import its pre-enable contents.
- Search is local text/OCR search; semantic search and cloud sync are not included.
- Backup is an explicit local operation. Keep the complete directory package together; it does not transfer application preferences.
- Existing dated archives, source content, notes, tasks, reminders and optional link-preview behavior remain supported. No user captures are included in review fixtures.
