# Required screens and interaction states

Create a screen/state index linking each item below to editable artboards and prototype routes. Map every FEATURES.csv ID to this index. Screens may share components; every workflow must remain reachable.

## Compact and expanded layouts

Use the current **380 × 430 pt content minimum** as a regression constraint. The current robot frame adds 20 × 50 pt, giving approximately 400 × 480 pt overall. Also design content at 380 × 680, 760 × 680, and a larger laptop/desktop workspace. Show the actual outer frame and content dimensions separately.

Show the interface at 1× and 2× backing scale. Include continuous resizing, tall/short windows, 13-inch laptop context, large external-display context, long titles/project names, and Hebrew/Japanese/Latin text. Do not call an upscaled 1× bitmap a Retina render.

Header height must remain bounded when window height grows. Keep content usable at the minimum; allow internal scrolling. Reduce spacing before wrapping or hiding controls. Advanced options may move to a meaningful menu, but keyboard access and all matrix functions must survive.

Compare at least two compact header approaches: labeled primary navigation with contextual tools, and a compact destination switcher with clear current location. Evaluate discoverability and action count. No permanent sidebar. A dense icon wall is not an acceptable substitute for hierarchy.

## Screen checklist

| Screen | Required contents and states |
|---|---|
| First run | First launch shows Inbox; later launches stay quiet until invoked; same-session reopen resumes route. Explain optional projects and capture entry points. No pre-enabled monitoring or permission wall. |
| Hidden and robot entry | Hidden desktop; each corner; compatible notch; external top-right; hover; carrying a drag; valid/invalid drop; explicit paste; saving; saved; failed; retreat. |
| Inbox | Empty, populated, inline draft, saving/error/recovered draft, destination label, filtering, keep/file/plan/convert, batch of files. |
| Today | Today/Upcoming/Completed, project filter, planned order and effort, unplanned Inbox tasks, overdue/unfinished group, due non-task reminders, empty and completed states. |
| Activity Daily | Centered date navigation, date picker, filters, newest-first items, carried task with creation date, reminded task placement, minimized items, grouped batch, hourly summary and expansion. |
| Activity Weekly | Seven-date range; only active days; one and many active days; no active days; narrow horizontal navigation; day/week search and export scope; transition direction and reduced-motion variant. |
| Search | Immediate focus, global/day/week scope, type/project/app refinements, recognized-text match, snippet alias, scratchpad match, nearby context, no results with two recovery actions, loading/error, Back preserving context. |
| Workspace Library | All projects, selected project, project creation, pins, content filters, extended date/app/origin filters, selection, compact and expanded previews, no resources. |
| Clipboard | Recent, pinned, named snippets, rename/remove alias, native copy/plain text, copy success/failure, many pins plus recent copies, new item while selection is scrolled. |
| Shelf | Empty instructions, existing capture added, multiple new files, project association, attachment to existing task, remove membership versus delete, missing file, exporting full project shelf to ZIP, cancelled/failed export. |
| Notes | Unfiled and project scratchpads, saved/saving/not-saved/retry, lengthy note, make task/save note, retained scratchpad, project switch and recovered edits. |
| Capture detail | Text, URL preview/fallback, image, PDF, video, generic file; available/unavailable source; saved destination; copy; project/pin; comment; reminder; recognized text pending/empty/failed/retry; minimize and trash. |
| Task detail | Converted capture retaining preview, Task/Completed, workday versus deadline/reminder, priority, effort, repeat, checklist/limits, attachment actions, previous occurrence, unsaved/saved/error. |
| Reminder | Date/time clock, countdown hours:minutes, zero/invalid input, due time before saving, existing timer reopening without reset, notification denied/retry/system settings. |
| New note and task | Destination disclosure, autofocus, save/cancel, recovered draft, title/content validation, planned day, optional reminder, Back without losing edits. |
| Export | Scope/date explicit, Copy and Text file actions, empty disabled, brief checkmark/success, Save panel cancellation, disk/clipboard error, complete-day export despite filters. |
| Settings | All groups in FEATURES.csv. Direct-build update card and Store-managed variant; visible version, all capture/privacy controls, theme, shortcuts, archive/index, notification state, support, complete Quit. |
| Recently Deleted | Empty/populated, restore, task family, restored reminder behavior, permanent-delete confirmation, failure, undo latest removal from active feed. |
| Backup and restore | Picker, progress/busy, verified success, cancellation, existing identical record, conflicting capture/scratchpad, corrupt/unavailable file, unsaved work blocking operation. |
| Status item menu | Open DaBin, automatic state, Pause/Resume when enabled, Settings, Quit. |
| Native application menu | About, update check, Open, Focus robot for paste, Search, automatic state/pause, Settings, Hide/Show, Quit and native Edit commands. Keep global search/save shortcuts distinct. |

## Component kit

Provide tokens and state variants for typography, surfaces, accents, semantic status, separators, spacing, corner radii, shadows, focus outlines, icons, tooltips, chips, tabs/switchers, menus, anchored popovers, cards, preview containers, inline editors, clocks/date pickers, checklist rows, banners, empty states, and safe destructive dialogs.

Each icon-only control needs visible hover help when enabled, a programmatic name, selected/disabled states, a visible focus ring, and adequate target area. Keep destructive actions separated from collapse/minimize. Use “capture” consistently; distinguish a comment from a new note, a reminder from a deadline, and a shelf membership from the saved record.

Native editing must retain select all, cut/copy/paste, undo/redo and composition behavior. Do not capture a paste intended for an active text field as a new unrelated item.

## Motion deliverables

Provide a storyboard or inspectable timeline for hidden → eyes → climb → generic token → eat/reaction → retreat; one of the ten reactions is not enough. Cover all ten existing reactions plus burst count, opening taking priority, close during animation, error, task-complete happiness, no-work/bored state, and disconnected display recovery.

The live rotation contains Quick Bite and Satisfied Blink; Oversized Bite and Recoil; Capture Noodle Slurp; Nibble the Corners; Toss and Mouth Catch; Oversized Swallow; Chase the Escaping Capture; Suspicious Inspection; Stacked Capture Snack; and Digital Hiccups. Legacy celebration names in source remain compatible identifiers, not additional required live rotation entries.

For opening, show the robot torso continuously becoming the surface, then reverse on close. Head/hands/feet must reserve space. Document transforms, easing, opacity, timing, hit testing, cancellation endpoints, and reduced-motion/quiet variants. Prefer GPU-friendly transforms and opacity over per-frame layout changes. Preserve the existing state machine rather than using unrelated animation timers.

Prototype animations may simulate native placement. Explicitly label browser corner/notch simulations; they do not prove safe areas, focus behavior, Spaces, capture exclusion, or multi-display correctness.

## Evidence labeling

Reference screens under `reference-screens/current-build53/` are the current production-view QA renders with synthetic content. `reference-screens/historical-build50/` illustrates details/robot/timeline behavior before the compact header and new navigation. Historical images must never override current source or feature requirements.

The original robot SVG and logo PNG are identity references. `DaBinLogo.swift`, `RobotCharacterView.swift`, and `RobotAppFrameView.swift` describe the current native implementation. The logo reference bitmap is not a finished scalable deliverable.
