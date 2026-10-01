# DaBin redesign handoff for Open Design

Redesign DaBin into a clear, compact, friendly native macOS desktop companion **without removing any implemented feature**. Improve navigation, visual hierarchy, cards, previews, the robot frame, and responsive behavior. Deliver a complete interactive design and implementation specification.

Simplification must come from better organization and progressive disclosure. Every existing capability must still have a discoverable home, a working interaction in the prototype or a complete native state specification, and acceptance evidence.

## Baseline and authority

- Baseline: **DaBin 0.4.2, build 53**, commit `b3f8507a77107474f923d9e4af5fc8ad4efe4a00`, inspected 30 September 2026. This is the local candidate; it does not establish public download or TestFlight availability.
- Platform: **Apple Silicon macOS 14+**, SwiftUI inside AppKit panels, a Core Animation robot, local Core Data metadata and managed files. The shipping app remains native.
- Read this brief, [FEATURES.csv](FEATURES.csv), [SCREENS_AND_STATES.md](SCREENS_AND_STATES.md), [ACCEPTANCE.md](ACCEPTANCE.md), and [SOURCE_MAP.md](SOURCE_MAP.md). Inspect the included native source for exact behavior.
- This handoff supersedes earlier design briefs. Instructions saying “no tasks,” “no composer,” “Daily only,” or “each file must have a separate card” are obsolete. Do not rebuild from an old screenshot or prototype.
- Current functionality and data semantics are the preservation baseline. Design recommendations below may change presentation, not silently change persistence, date, privacy, or task behavior. Record proposed behavior changes separately.
- Use fictional client and capture data only. Do not upload the owner’s live clipboard, archive, signing credentials, or unrelated projects. Included reference screens are synthetic QA examples, not customer content.

## Product and audience

DaBin is a small metallic purple robot bin for freelancers and people working from home. It helps someone collect feedback, gather project materials, reuse copied content, capture commitments, plan work, and return after interruption.

The core loop is **capture quickly → connect to a project if useful → take the next action → retrieve later**. Organization is optional. Tasks, project memberships, and shelf membership build on saved captures without losing their original content or receipt time.

Personality belongs in short, useful robot reactions and friendly microcopy. The app should be calm during concentrated work and understandable without a tutorial.

## Redesign priorities

1. Make the main places understandable: Inbox for triage, Today for planned work, Workspace for resources, Activity for daily/weekly history. Alternative labels or grouping require an explicit old-to-new mapping.
2. Compact the header and reduce competing controls. Give content previews and the next useful action visual priority. Avoid duplicated navigation and unexplained icon rows.
3. Make compact capture/retrieval and expanded project organization feel like the same app. Preserve selection, search, project, drafts, date, and scroll context across navigation and resizing.
4. Make ordinary captures, file batches, tasks, completed tasks, and automatic hourly groups distinct but related.
5. Make the open robot body thinner and more recognizable, with its head, hands, and feet outside working content.
6. Keep privacy state, errors, settings, update status, and recovery easy to find and understand.

## Visual direction

Retain the **DaBin name, purple metal robot, expressive eyes, and purple default accent**. Preserve selectable theme colors and light/dark modes. Refine the logo and robot with vector/native shapes; do not scale up raster screenshots.

- Use calm surfaces, thin rounded card borders, restrained depth, and clear typography. No permanent sidebar, oversized mascot, simulated desktop backdrop, or generic full-screen dashboard.
- The resting buddy stays hidden until its configured corner/island interaction, except existing brief capture confirmation. No permanent drop panel. Preserve direct robot intake and the existing board/Inbox/task attachment intake.
- Compact must remain readable. Proposed starting values: 13–14 pt body, 11–12 pt secondary metadata, clear larger titles, and 28–32 pt desktop control targets. Validate at actual scale; do not simply shrink everything.
- Give icons consistent optical size, stroke, baseline, hit area, and hover/pressed/focus/selected states. Align action and filter groups on a common grid when shown together. Keep short labels where icons alone are ambiguous. Tooltips are optional; accessibility names are permanent.
- Keep Auto Capture visible near the logo, with distinct off/on/paused/problem states. The gear opens Settings directly. X is neutral and hides the board; **Quit DaBin** is a separate complete shutdown action.
- Center the date within its timeline navigation group. Make Day/Week controls consistent with the visual system. Avoid empty fixed-height header space or multiple full toolbars on every screen.
- Give previews most of a capture card’s useful area. Fit images, PDF pages, and video without distortion or obscuring controls. Include loading/unavailable/unsupported-preview fallbacks.
- Retain a small copy action near the upper-right, discoverable comment/reminder actions, readable time/type, and clear task status. Use text or shape as well as red/green for Task/Completed.
- Preserve adjustable body opacity, opaque readable navigation/cards, Increase Contrast, and Reduce Transparency behavior. Every supported theme must work in light and dark mode.

## Feature preservation requirements

The matrix is the exhaustive review checklist; the sections here describe related workflows. Features missing from a screenshot are still required.

### Capture and Inbox

Preserve robot drop/paste, hover ⌃V/⌘V, board/Inbox drop/paste, Add → Paste clipboard/New note/Import files/New task, quick Inbox composition, global search/capture shortcuts, and menu bar entry points. Accept supported text, URLs, images/screenshots, PDF/documents, video, promised files, and regular generic files. Unsupported preview formats remain importable where the importer supports them. Folder/alias/symlink import is not implemented and must not be promised.

Multi-file intake remains a grouped card with individual member access. Keep project filing, task conversion, planning Today, and **Keep in Workspace** triage without deleting the record. Show success only after persistence; animation never blocks saving. Recover unfinished drafts with their intended destination.

### Cards and details

Preserve fitted preview, title/text, original date/time, available source app/location and app icon/domain fallback, open original, saved file/path/folder actions, copy, comment, reminder, pin, project, task conversion, minimize/expand, and recoverable deletion. Minimized content remains searchable and accessible in Detail.

Source attribution is best effort. Show a supplied source path and DaBin’s actual saved destination when known. DaBin **does not observe where someone later pastes into another app**. Never invent a source path, favicon, destination, or certainty.

Task conversion updates the same record, retaining source content/type, comments, reminder, attachments, and receipt date. Reveal its work plan when it becomes a task. An image-task must remain in both Media and Tasks.

### Today and tasks

Preserve Today/Upcoming/Completed, Inbox task selection, planned workday, separate deadline and reminder, priority, effort estimate, ordering, rescheduling, checklist, recurrence, complete/reopen, and unfinished/overdue visibility.

Attachments support paste/drop/import and attaching an existing saved item; keep preview/copy/open/reveal/detail and return-to-parent actions. Ordinary attachment unlinking is not currently implemented; it may be proposed separately. Completing a task may use the existing happy-robot reaction. Recurrence creates exactly one linked next occurrence; attachments stay with the completed occurrence and remain reachable through its link.

Keep date/time reminders and hours:minutes countdown. Countdown begins at save and does not restart on reopen. Clearly distinguish workday, deadline, reminder, and original receipt date. Preserve notification permission/error states and non-task reminder Done/Tomorrow actions.

### Activity and search

Keep daily/weekly history, calendar selection, previous/next, return to today, newest-first feed, grouped files, hourly groups, capture detail, task carryover, and original creation-date badges. Preserve reminder-day placement for carried tasks. Activity carryover is separate from Today planning.

A week is the existing seven-date calendar range ending on the chosen date. Hide genuinely empty days in Weekly; retain a truthful range label and useful whole-week empty state. Keep readable horizontally navigable day columns at narrow widths.

Preserve **All, Copy/paste text, Links, Files, Media, Tasks**. Text precedes Links in a row. Header position stays stable when filtering; bottom resize remains gentle and respects Reduce Motion.

Universal search includes saved text/links/tasks/files, OCR/PDF/document text, snippet names, and scratchpad matches. Search has type/project/source-app refinements plus All/Day/Week scope; Workspace additionally offers date/app/origin filters. Preserve matching excerpts, immediate field focus, Return retaining refinements, and Back restoring context. Keep optional nearby same-day context and distinguish context from matches. Empty results can clear refinements or broaden dates without discarding the query. Scratchpad matches require All or Text and no source-app filter; scoped search uses their updated date. Never invent their source app.

Local OCR/indexing remains available in details and search, with text copy, progress, no-text/error/retry states, and Settings rebuild. This is local text search, not semantic AI search.

### Projects and Workspace

Preserve optional project selection/creation and item association, All projects, Library/Clipboard/Shelf/Notes, pins, shared project context, and restored selection. The matrix/source define the actual management actions; do not promise new project operations without implementing them.

Clipboard keeps Recent and named Snippets, naming/renaming/removing a snippet alias, pin/unpin, combined refinements, native copy and copy as plain text. Recent copies stay easy to reach regardless of pin count. New arrivals must not jump the current selection. Plain-text copy writes to the clipboard; it does not type into another app.

Shelf membership survives restart. Preserve existing-item membership, new intake, previews, task/project association, reveal/path copy, and ZIP export of the selected project’s complete shelf independent of active type filters. **Remove from shelf; keep capture** is distinct from deletion. Imports are managed local copies; external originals are untouched.

Scratchpads autosave per project and for unfiled work. Preserve saved/not-saved/retry feedback, restart recovery, save as note/make task, and the retained scratchpad after conversion. Detail drafts still require Save changes; do not imply every detail edit is committed because notes autosave.

### Auto Capture and privacy

Keep independent Clipboard and Screenshots opt-ins, both initially off, with shared Pause/Resume. Header/status/settings expose off, active, paused, excluded, permission-needed/revoked, and failed states. Pause/disable stops new intake immediately; existing records stay.

Screenshot monitoring uses a chosen folder and native authorization; it is not universal screenshot detection. Clipboard works independently. Enable/resume starts with a fresh baseline and never imports old clipboard contents/folder images. Keep exclusion editing/defaults and the permanent DaBin exclusion; do not claim perfect sensitive-source detection.

Preserve cross-channel image deduplication. One to three automatic actions per local clock hour remain individual; the fourth makes a summary. Counts/date labels stay accurate. Expand in place; the minus has accessible name **Collapse actions**, preserves position, and never means delete.

Only saved actions trigger robot confirmation. Preserve generic tokens, exact burst count, one active robot, bounded follow-up aggregation, no focus theft, and no sound. Never expose actual captured content in decoration. Manual link previews are optional/off by default; automatic links never trigger website previews.

### Robot and native window

Preserve corner/island home, reveal/peek, direct intake, hover paste, double-click/Return opening, and retreat. First launch shows Inbox; later launches remain quiet until invoked, and reopening during a session resumes its route. The global save-clipboard command explicitly selects Activity/Daily before intake. Use compatible built-in safe-area geometry; external/no-island fallback is top-right. Open on the interacted display and recover after display changes.

Refine the continuous robot-to-app transformation. Retain thin reserved head/hands/feet areas, moving and edge/corner resizing, expand/restore, compact geometry, native Spaces behavior, and no decorative click interception.

Preserve the generation-safe lifecycle: opening wins over capture, interruption resolves to a stable open/closed endpoint, shutdown never waits for animation. Current approximate timings: reveal 0.55 s, open 1.15 s, close 0.42 s, automatic eating 1.8–2.6 s. Retain ten visibly distinct reactions, shuffled rotation, previous-three exclusion, clamped/eased gaze, hidden-animation suspension, and quiet/reduced-motion alternatives.

DaBin requests exclusion from screenshots, but macOS recording APIs differ. Keep the protection and post-save trigger. Use an isolated fixture for visual review rather than disabling privacy on the installed app.

### Settings, export, recovery, and updates

Preserve every setting in the matrix, including color presets/custom/reset, light/dark, opacity/solid reset, tooltip switch, robot home, Quiet mode, shortcut choices/conflicts/disable, capture sources/exclusions, retention/clear history, link previews, archive/index, privacy/support, notification state, installed version/update controls, and complete Quit.

Retention defaults to Never and moves eligible unfiled automatic copies to recoverable trash. Tasks/attachments, reminders, projects, pins, snippets, shelf items, and Inbox-kept work stay protected. Keep Recently Deleted, Undo latest removal, Restore, and separately confirmed permanent deletion. External originals are never deleted.

Day/week Copy and Export Text File use identical UTF-8 content for their scope: chronological receipt order, date/time/type/source when available, text/OCR or a clear placeholder. Ignore active content filters and carryover duplicates. Day filenames remain `DaBin-YYYY-MM-DD.txt`; today excludes future records. Keep empty disabled, success/checkmark, cancellation, and failure states.

Preserve verified local `.dabinbackup`, additive restore, conflict protection, and recovery. Storage remains year → numbered named month → numbered named day with weekday → unique capture folder. A redesign must not replace storage, migrate data casually, or erase records.

Direct builds retain user-initiated GitHub **Get updates**, visible installed version/status, verification, backup and install. Store builds update through Apple and exclude that downloader/helper. Design both variants honestly; do not advertise an unapproved build as available.

## Open Design process and deliverables

1. Audit the included app and feature matrix. Compare two or three focused navigation/compact-view alternatives at actual scale. Select a direction using readability, discoverability, steps, interruption, and native feasibility.
2. Work in a new `open-design-v3/` or equivalent isolated design workspace. Preserve production source and design history. This assignment does not include installing, publishing, or changing live user settings/data.
3. Produce a clickable local prototype using fictional projects, long filenames, mixed-language text, and complete states. Simulate OS behavior explicitly; specify native behavior that cannot be reproduced in a browser.
4. Deliver editable components, typography/color/spacing/radius tokens, vector assets, icon states, responsive layouts, and robot motion specifications with Reduce Motion variants.
5. Fill **every feature matrix row** with its new screen/control, prototype/spec evidence, and verification status. Relocation is permitted; missing controls and unreachable stubs are not. Include a terminology/navigation change log.
6. Run the acceptance scenarios. Supply actual-scale before/after images, interaction counts, implementation file mapping, and limitations. Distinguish expert evaluation from real user research.

## Definition of done

All matrix rows have destinations and evidence. Compact mode is calm and readable; expanded mode supports organizing work; common actions are easy to find; keyboard/accessibility and all window sizes are covered; the app still feels like DaBin. Deliver enough detail for native implementation without guessing data, privacy, task, date, or animation semantics. A static mockup alone is incomplete.
