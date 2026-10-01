# Feature preservation and native implementation contracts

Baseline: DaBin 0.4.2 (53), frozen source snapshot supplied by the user. This is an editable design specification, not a native release or a claim of OS parity.

Every matrix row has a destination below. Browser coverage status describes evidence availability, not a claim that every scenario passed. See QA_REPORT.md for executed checks and unverified native work.

## Capture contract

Input → validation → saving → committed or recoverable failure. No success animation before persistence.

Preserve native NSItemProvider promised-file loading, supported transfers and file security scope. Reject unsupported folder/alias/symlink intake without claiming successful capture. Retain destination on interrupted saves. Browser imports keep data URLs only in isolated storage, have an explicit 8 MB per-file fixture bound and never claim native parity.

## Inbox contract

Untriaged → optional project/task/workday → kept in Workspace. No record replacement.

Keep sets protection against cleanup. A project association is optional. The original receipt, content and type remain immutable. Empty destination shows capture guidance; recovered draft discloses Inbox/project. A storage failure retains the draft and reports failure.

## Cards contract

Available → preview loading → ready, unavailable, unsupported or failed. Actions stay discoverable.

Preview fitting uses contain, not cropping. Source metadata is best effort; absent source path says not supplied. Native copy validates every grouped payload before replacing clipboard. Comment edits remain a draft until Save changes. Minimize never hides content from search or Detail. Deletion and collapse are separate named actions.

## Tasks contract

Capture → task on the same ID → planned → completed/reopened.

Plan date, deadline, reminder and receipt are independent. Priority None/Low/Medium/High; optional effort 1–10080 minutes; checklist max 100 rows of 1–500 characters. Recurrence creates one linked next occurrence using original cadence; attachments remain on the completed occurrence. Reopening cannot spawn an additional next occurrence. Attachment navigation retains the parent; ordinary unlinking is not offered.

## Reminders contract

None → date/time or countdown draft → saved target → due / canceled / delivery error.

Countdown permits 0–99 hours and 0–59 minutes, nonzero total. Its target is calculated at save, stored absolutely and never reset by opening or comment editing. First native scheduling requests notification permission. Denial exposes System Settings and retry; task completion cancels delivery. Non-task Done removes the reminder, Tomorrow reschedules without task conversion.

## Activity contract

Selected receipt day ↔ seven-date range ending on selected day → scoped search/export.

Newest receipts first. Weekly hides truly empty columns but labels the full range; whole-week empty state remains usable. Task carryover is computed presentation, never duplicated receipt storage; reminded carried tasks appear on their reminder day. Fourth successful automatic action within the same local clock hour forms a summary, 1–3 remain individual. Tasks are separated. Collapse actions retains scroll and cannot delete.

## Search contract

Focused query → scoped/refined matches → detail → Back to prior query, refinements and scroll.

All/Day/Week uses receipt dates for captures and updated dates for scratchpads. Scratchpads require All/Text and no app filter; do not invent app provenance. Nearby context is labeled separately from actual matches. Empty results can clear refinements or broaden dates without clearing text. OCR/PDF/doc indexing is local, bounded, and exposes progress/no-text/error/retry; native implementation retains source limits.

## Workspace contract

Shared optional project → Library/Clipboard/Shelf/Notes → selected resource → return.

Recent is chronological and separate from Pinned so many pins cannot bury new copies. A snippet is an alias, never replacement content. New arrivals do not reset the browsing position. Shelf membership and removal are separate from saved-record deletion; its ZIP ignores current type/app/date filters and includes the full selected project shelf with collision-safe names. Notes autosave by project/unfiled and remain after conversion; failures retain edits and expose retry.

## Export contract

Selected day/week → complete receipt payload → copy/save picker → success, neutral cancel or actionable failure.

Copy and file output use the same UTF-8 bytes, chronological original receipt order, type/time/source if known, text/OCR or an honest no-preview marker. Ignore active content filters and project refinements for a complete Activity export. Avoid carried-task duplicates and future receipts for today. Empty scope disables actions. Day name DaBin-YYYY-MM-DD.txt; week names identify both boundaries.

## Auto Capture contract

Independent off sources → explicit consent → fresh baseline → active / shared paused / excluded / permission error / failed.

Clipboard and screenshot channels remain independent. Screenshot folder selection stores a security-scoped authorization; revoked access cannot disable clipboard. DaBin is permanently excluded. Password-source exclusions are best effort, not perfect sensitive-data detection. Enable/resume never replays existing clipboard/folder content. Dedup images across channels before persistence/counting. Generic robot tokens only after successful save; no automatic website preview requests.

## Robot contract

Hidden → reveal → ready → saving → saved reaction → retreat; opening supersedes presentation.

See ROBOT_MOTION.md for all ten reactions, previous-three exclusion, exact burst counts, one bounded presenter, cancellation endpoints and reserved geometry. Native AppKit handles display safe areas, Spaces and sharing exclusion. Browser animation controls explicitly identify the simulation and cannot prove OS behavior.

## Preferences contract

Persisted preference → user change → apply/registration → effective state or recoverable error.

Source presets and custom sRGB accents resolve for contrast. Opacity 35–100% in 5% increments; system Reduce Transparency forces effective opacity 100 without erasing the preference. Navigation/cards remain opaque. Tooltips off keeps accessibility labels. Link previews are off initially and only eligible manual links may request networking. Direct updates are user initiated with verify/backup/install gates; Store build excludes the direct helper.

## Data contract

Saved → recoverable trash → restore or separately confirmed permanent deletion.

Operate on capture/task family; imported external originals are never deleted. Native journaled cleanup reports partial I/O failure without losing recovery metadata. Restore retains original content/date/project; past reminder handling is explicit. Backups include metadata, originals, projects, memberships, snippets, notes and trash, verify checksums and restore additively. Conflicts block overwrite. Corrupt packages and pending drafts block application.

## Keyboard contract

Entry shortcut/menu → focused route → innermost popover → return focus or hide.

Preserve native responder-chain cut/copy/paste/select-all/undo/redo and composition. Do not intercept paste in text editors. First launch opens Inbox; later launch is quiet; same-session reopen resumes route. Global clipboard-save explicitly selects Daily before intake. Global registration has two predefined choices and disabled/conflict states. Browser keyboard testing does not prove native menu/global registration.

## C01

**Robot direct drag and drop**

- Proposed location: Robot direct drop; Inbox and task attachment drop targets.

- Browser route: [robot.html](../../robot.html).

- Preserve: Supported native transfers including promised files; stable hover target; save before success.

- State behavior: apply the Capture contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/RobotView.swift;native/Sources/DaBin/InputService.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## C02

**Explicit robot paste**

- Proposed location: Robot Paste; active panel paste excluding editable fields.

- Browser route: [robot.html](../../robot.html).

- Preserve: Control-V and Command-V; no clipboard read merely on hover.

- State behavior: apply the Capture contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/RobotView.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## C03

**Board intake**

- Proposed location: Inbox composer and board paste/drop.

- Browser route: [inbox.html](../../inbox.html).

- Preserve: Drop/paste while retaining ordinary text-field editing behavior.

- State behavior: apply the Capture contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/DailyCaptureView.swift;native/Sources/DaBin/InboxScreen.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## C04

**Add menu**

- Proposed location: Header + menu: Paste, New note, Import files, New task.

- Browser route: [inbox.html](../../inbox.html).

- Preserve: Paste clipboard; New note; Import files; New task; importing disabled state.

- State behavior: apply the Capture contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/BoardView.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## C05

**Inline quick capture**

- Proposed location: Inbox quick composer; explicit destination and restored draft.

- Browser route: [inbox.html](../../inbox.html).

- Preserve: Multiline note/task creation; visible destination; save/error/recovery.

- State behavior: apply the Capture contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/InboxScreen.swift;native/Sources/DaBin/DraftArchive.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## C06

**Supported data and file batches**

- Proposed location: Grouped file card with clickable members; native payload contract.

- Browser route: [inbox.html](../../inbox.html).

- Preserve: Text/link/image/PDF/video/doc/generic file; managed copies; multi-file grouping and member access.

- State behavior: apply the Capture contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/InputService.swift;native/Sources/DaBin/GroupedCaptureCard.swift.

- Evidence status: PARTIAL BROWSER + NATIVE SPEC; native verification pending.

## C07

**Keep and organize**

- Proposed location: Capture actions: Keep, File to project, Turn into task, Plan for Today.

- Browser route: [inbox.html](../../inbox.html).

- Preserve: Keep in Workspace without deletion; project filing; convert task; plan Today.

- State behavior: apply the Capture contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/InboxScreen.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## V01

**Fitted previews and fallbacks**

- Proposed location: Preview-led card and capture detail original content pane.

- Browser route: [capture-detail.html](../../capture-detail.html).

- Preserve: Image/PDF/video/link/generic states; loading/error/unavailable; no stretching.

- State behavior: apply the Cards contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/CapturePreviews.swift;native/Sources/DaBin/FittedPDFPreview.swift.

- Evidence status: PARTIAL BROWSER + NATIVE SPEC; native verification pending.

## V02

**Receipt and provenance**

- Proposed location: Card receipt/source; Detail provenance block.

- Browser route: [capture-detail.html](../../capture-detail.html).

- Preserve: Immutable date/time; type; best-effort app icon/path; actual saved destination; truthful missing-source fallback.

- State behavior: apply the Cards contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/CaptureSourceView.swift;native/Sources/DaBin/Domain.swift.

- Evidence status: PARTIAL BROWSER + NATIVE SPEC; native verification pending.

## V03

**Copy individual or grouped content**

- Proposed location: Upper-right Copy; grouped native clipboard state dialog.

- Browser route: [capture-detail.html](../../capture-detail.html).

- Preserve: Native clipboard data from saved originals; complete success or failure; no partial group clipboard replacement.

- State behavior: apply the Cards contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/CaptureCopyButton.swift;native/Sources/DaBin/CaptureClipboard.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## V04

**Comment editing**

- Proposed location: Detail Comment; Save changes; recovered edit banner.

- Browser route: [capture-detail.html](../../capture-detail.html).

- Preserve: Existing content retained; explicit save; draft recovery and errors.

- State behavior: apply the Cards contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/DetailScreen.swift;native/Sources/DaBin/DraftArchive.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## V05

**Reminder editing**

- Proposed location: Detail Reminder link; separate reminder screen.

- Browser route: [capture-detail.html](../../capture-detail.html).

- Preserve: Optional reminder on any capture; accessible clock; visible scheduled/error state.

- State behavior: apply the Cards contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/DetailScreen.swift;native/Sources/DaBin/ReminderClockEditor.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## V06

**Minimize and expand**

- Proposed location: Capture Actions → Minimize / Expand preview.

- Browser route: [capture-detail.html](../../capture-detail.html).

- Preserve: Persist compact preference; full content remains in details/search.

- State behavior: apply the Cards contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/CaptureCards.swift;native/Sources/DaBin/CapturePresentation.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## V07

**Link and local file actions**

- Proposed location: Detail Open original; File location native state dialog.

- Browser route: [capture-detail.html](../../capture-detail.html).

- Preserve: Open original URL/saved file; reveal saved file/folder; copy saved path; missing file feedback.

- State behavior: apply the Cards contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/WorkspaceItemCard.swift;native/Sources/DaBin/AppState.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## V08

**Pin and project association**

- Proposed location: Detail project + pin; card action equivalents.

- Browser route: [capture-detail.html](../../capture-detail.html).

- Preserve: Persist association/pin; optional project; unfiled remains valid.

- State behavior: apply the Cards contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/DetailScreen.swift;native/Sources/DaBin/WorkspaceItemCard.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## T01

**Capture conversion**

- Proposed location: Turn into task → same record in Task Detail.

- Browser route: [task-detail.html](../../task-detail.html).

- Preserve: Same record/content/source/receipt; content filter plus Tasks; reveal work plan.

- State behavior: apply the Tasks contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/DetailScreen.swift;native/Sources/DaBin/CaptureStore.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## T02

**Task status**

- Proposed location: Today checkbox; task detail Complete/Reopen.

- Browser route: [task-detail.html](../../task-detail.html).

- Preserve: Complete/reopen; text/icon as well as color; reminders reflect completion; happy feedback only on success.

- State behavior: apply the Tasks contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/CaptureCards.swift;native/Sources/DaBin/CaptureStore.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## T03

**Today planning scopes**

- Proposed location: Today / Upcoming / Completed; unplanned, unfinished and reminders sections.

- Browser route: [today.html](../../today.html).

- Preserve: Today/Upcoming/Completed; project scope; unplanned tasks; unfinished/overdue and due reminders.

- State behavior: apply the Tasks contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/TodayPlanningScreen.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## T04

**Planned day and reschedule**

- Proposed location: Task menu Today/Tomorrow/clear; Work plan custom date.

- Browser route: [today.html](../../today.html).

- Preserve: Today/Tomorrow/Inbox/custom workday; original receipt and deadline unchanged.

- State behavior: apply the Tasks contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/TaskPlanningEditor.swift;native/Sources/DaBin/TaskPlanning.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## T05

**Priority effort and ordering**

- Proposed location: Work plan Priority/Effort; Today Move earlier/later.

- Browser route: [today.html](../../today.html).

- Preserve: None/Low/Medium/High; optional minutes and total effort; reorder; validation.

- State behavior: apply the Tasks contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/TodayPlanningScreen.swift;native/Sources/DaBin/TaskPlanningEditor.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## T06

**Separate deadline**

- Proposed location: Work plan Deadline, separate from planned date and reminder.

- Browser route: [task-detail.html](../../task-detail.html).

- Preserve: Finish-by date/time independent from workday and notification reminder.

- State behavior: apply the Tasks contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/TaskPlanningEditor.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## T07

**Recurrence**

- Proposed location: Work plan Repeat; Previous and Next occurrence links.

- Browser route: [task-detail.html](../../task-detail.html).

- Preserve: None/Daily/Weekdays/Weekly/Monthly; one linked next occurrence; original attachments remain accessible.

- State behavior: apply the Tasks contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/TaskPlanning.swift;native/Sources/DaBin/DetailScreen.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## T08

**Checklists**

- Proposed location: Checklist rows; add/remove/edit/check; explicit save.

- Browser route: [task-detail.html](../../task-detail.html).

- Preserve: Add/edit/remove/complete; count; 100 steps max and 1-500 characters; helpful validation.

- State behavior: apply the Tasks contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/TaskPlanningEditor.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## T09

**New attachments**

- Proposed location: Task Attachments → Import / Paste; task panel drop.

- Browser route: [task-detail.html](../../task-detail.html).

- Preserve: Drop/paste/import more text/files into task; count and previews; no content loss.

- State behavior: apply the Tasks contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/TaskAttachmentsView.swift;native/Sources/DaBin/DailyCaptureView.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## T10

**Existing attachments and navigation**

- Proposed location: Task Attachments → Saved item; child detail → Parent.

- Browser route: [task-detail.html](../../task-detail.html).

- Preserve: Attach saved non-task capture; attachment detail; return to parent; no ordinary unlink command in current app.

- State behavior: apply the Tasks contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/WorkspaceItemCard.swift;native/Sources/DaBin/TaskAttachmentsView.swift;native/Sources/DaBin/DetailScreen.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## T11

**New task composer**

- Proposed location: Add → New task; destination label; recovered draft.

- Browser route: [new-task.html](../../new-task.html).

- Preserve: Save/cancel/recovery; destination; optional reminder/planning; Command-Return.

- State behavior: apply the Tasks contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/TaskEditorScreen.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## R01

**Date/time and countdown**

- Proposed location: Reminder Date & time / Countdown; persisted target time.

- Browser route: [reminder.html](../../reminder.html).

- Preserve: Hours 0-99 minutes 0-59; nonzero; begins when saved; reopen never resets.

- State behavior: apply the Reminders contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/ReminderClockEditor.swift;native/Sources/DaBin/ReminderSchedule.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## R02

**Notification delivery state**

- Proposed location: Reminder and Settings → Notification status native dialog.

- Browser route: [reminder.html](../../reminder.html).

- Preserve: Permission on first reminder; denied/error/retry/system settings; completion cancellation.

- State behavior: apply the Reminders contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/ReminderService.swift;native/Sources/DaBin/SettingsScreen.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## R03

**Non-task follow-up actions**

- Proposed location: Today non-task reminder row → Done / Tomorrow.

- Browser route: [today.html](../../today.html).

- Preserve: Done and Tomorrow; separate from task completion semantics.

- State behavior: apply the Reminders contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/TodayPlanningScreen.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## H01

**Daily calendar history**

- Proposed location: Activity Day date group; previous/next/calendar/Today.

- Browser route: [activity.html](../../activity.html).

- Preserve: Calendar selection; previous/next; today; newest first; original receipt date.

- State behavior: apply the Activity contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/DailyScreen.swift;native/Sources/DaBin/BoardView.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## H02

**Weekly history**

- Proposed location: Activity Week, seven days ending on selected date.

- Browser route: [weekly.html](../../weekly.html).

- Preserve: Seven dates ending on chosen date; active days only; whole-week empty; day columns open Daily.

- State behavior: apply the Activity contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/WeeklyScreen.swift;native/Sources/DaBin/AppState.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## H03

**Task carryover**

- Proposed location: Activity Still open section; original receipt label.

- Browser route: [activity.html](../../activity.html).

- Preserve: Unfinished placement; creation-date badge/frame; reminder-day top placement; no duplicate receipt storage.

- State behavior: apply the Activity contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/CapturePresentation.swift;native/Sources/DaBin/AppState.swift.

- Evidence status: PARTIAL BROWSER + NATIVE SPEC; native verification pending.

## H04

**Content type filters**

- Proposed location: Context type strip: All, Text, Links, Files, Media, Tasks.

- Browser route: [activity.html](../../activity.html).

- Preserve: All/Text/Links/Files/Media/Tasks; text before Links; task plus original content type.

- State behavior: apply the Activity contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/CaptureFilterStrip.swift;native/Sources/DaBin/Domain.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## H05

**Automatic hourly summaries**

- Proposed location: Activity hourly summary; disclosure and named collapse action.

- Browser route: [activity.html](../../activity.html).

- Preserve: Fourth successful auto action groups fixed local hour; exact counts; task separation; expand/collapse in place.

- State behavior: apply the Activity contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/HourlyCaptureFeed.swift;native/Sources/DaBin/HourlyCaptureCard.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## H06

**Batch actions**

- Proposed location: Grouped file card → member detail; Actions minimize; native atomic copy contract.

- Browser route: [activity.html](../../activity.html).

- Preserve: Expand/minimize; members; group/member copy; grouped removal semantics.

- State behavior: apply the Activity contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/GroupedCaptureCard.swift;native/Sources/DaBin/CaptureCardGroup.swift.

- Evidence status: PARTIAL BROWSER + NATIVE SPEC; native verification pending.

## S01

**Global archive search**

- Proposed location: Header Search / ⌘K; results across text, OCR, filenames, snippets and notes.

- Browser route: [search.html](../../search.html).

- Preserve: Immediate focus; saved content/tasks/links/snippets/OCR/scratchpads; grouped dates and previews.

- State behavior: apply the Search contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/SearchScreen.swift;native/Sources/DaBin/AppState.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## S02

**Day week and all scopes**

- Proposed location: Search All/Day/Week; Activity scoped search buttons.

- Browser route: [search.html](../../search.html).

- Preserve: Clear scope/date; keyboard access; anchored dismissal; correct selected weekly day.

- State behavior: apply the Search contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/WeeklyScopeActions.swift;native/Sources/DaBin/AppState.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## S03

**Refinements and context**

- Proposed location: Search type/project/app; nearby context; Workspace refinements.

- Browser route: [search.html](../../search.html).

- Preserve: Search type/project/app and All/Day/Week; Workspace date/app/origin; Return preserves; nearby context distinguished.

- State behavior: apply the Search contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/SearchScreen.swift;native/Sources/DaBin/WorkspaceQuery.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## S04

**Empty recovery and Back**

- Proposed location: Empty Search → Clear refinements / Search all dates; Back.

- Browser route: [search.html](../../search.html).

- Preserve: Clear refinements or widen dates while retaining query; restore prior selection/route/filter/project.

- State behavior: apply the Search contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/SearchScreen.swift;native/Sources/DaBin/AppState.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## S05

**Local OCR and text indexing**

- Proposed location: Detail recognized text/status; Settings rebuild index.

- Browser route: [capture-detail.html](../../capture-detail.html).

- Preserve: Local Vision/PDFKit/text; progress/empty/failure/retry; searchable excerpt/copy; rebuild; bounded work.

- State behavior: apply the Search contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/ContentIndexService.swift;native/Sources/DaBin/DetailScreen.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## W01

**Project spaces**

- Proposed location: Shared project selector; Create project; detail association.

- Browser route: [workspace.html](../../workspace.html).

- Preserve: Create/select/associate optional project; All projects; shared context; selection restoration.

- State behavior: apply the Workspace contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/LibraryScreen.swift;native/Sources/DaBin/WorkspaceStore.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## W02

**Four connected modes**

- Proposed location: Workspace Library / Clipboard / Shelf / Notes.

- Browser route: [workspace.html](../../workspace.html).

- Preserve: Library/Clipboard/Shelf/Notes; filters and project survive mode changes.

- State behavior: apply the Workspace contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/LibraryScreen.swift;native/Sources/DaBin/WorkspaceStore.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## W03

**Library browsing**

- Proposed location: Library preview grid/list; type strip and refinement dialog.

- Browser route: [workspace.html](../../workspace.html).

- Preserve: Recognizable cards; responsive columns; pin-only; project/date/app/origin/type filters; item count.

- State behavior: apply the Workspace contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/LibraryScreen.swift;native/Sources/DaBin/WorkspaceItemCard.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## W04

**Recent copied material**

- Proposed location: Clipboard Recent, separate Pinned and Snippets views.

- Browser route: [clipboard.html](../../clipboard.html).

- Preserve: Automatic copies plus supported manual text/links; new arrivals do not disturb selection; recent not buried by pins.

- State behavior: apply the Workspace contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/WorkspaceQuery.swift;native/Sources/DaBin/LibraryScreen.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## W05

**Named reusable snippets**

- Proposed location: Capture Actions → Name / Rename / Remove snippet alias.

- Browser route: [clipboard.html](../../clipboard.html).

- Preserve: Save/rename/remove alias without changing content; alias search; pin access.

- State behavior: apply the Workspace contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/WorkspaceItemCard.swift;native/Sources/DaBin/WorkspaceStore.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## W06

**Copy as plain text**

- Proposed location: Capture Actions and Detail → Copy as plain text.

- Browser route: [clipboard.html](../../clipboard.html).

- Preserve: Text-only clipboard action; no external typing or added Accessibility permission.

- State behavior: apply the Workspace contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/WorkspaceClipboard.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## W07

**Persistent collection**

- Proposed location: Shelf Add from Library / intake; Remove from shelf; keep capture.

- Browser route: [shelf.html](../../shelf.html).

- Preserve: Add existing and import/paste/drop; membership survives restart; optional project; remove membership keeps capture.

- State behavior: apply the Workspace contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/ShelfCaptureController.swift;native/Sources/DaBin/WorkspaceStore.swift;native/Sources/DaBin/LibraryScreen.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## W08

**Project shelf ZIP**

- Proposed location: Shelf Export shelf, full selected project collection.

- Browser route: [shelf.html](../../shelf.html).

- Preserve: Entire project shelf ignores type filter; verified managed files; text/link UTF-8; unique names; no silent overwrite.

- State behavior: apply the Workspace contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/ShelfExport.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## W09

**Project and unfiled scratchpads**

- Proposed location: Notes project/unfiled scratchpads; autosave status/retry.

- Browser route: [notes.html](../../notes.html).

- Preserve: Autosave; saved/not-saved/retry; survives project switch/restart; search only All/Text without app filter; scoped by updated date; no invented source.

- State behavior: apply the Workspace contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/ScratchpadView.swift;native/Sources/DaBin/WorkspaceStore.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## W10

**Convert scratchpad**

- Proposed location: Notes Save as note / Make task; scratchpad retained.

- Browser route: [notes.html](../../notes.html).

- Preserve: New saved record with original text; scratchpad retained; project destination preserved.

- State behavior: apply the Workspace contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/ScratchpadView.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## E01

**Copy and text export day**

- Proposed location: Activity Day → Export → Copy / Text file.

- Browser route: [export.html](../../export.html).

- Preserve: Complete chosen receipt day; ignores filters; chronological; timestamp/type/source/text/OCR/placeholder; excludes future today.

- State behavior: apply the Export contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/DayExport.swift;native/Sources/DaBin/BoardView.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## E02

**Copy and text export week**

- Proposed location: Activity Week → Export → Copy / Text file.

- Browser route: [export.html?scope=Week](../../export.html?scope=Week).

- Preserve: Complete seven-day receipt range; exact same copy/file text; no carried task duplicates.

- State behavior: apply the Export contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/DayExport.swift;native/Sources/DaBin/BoardView.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## E03

**Export feedback and dialogs**

- Proposed location: Export preview; empty disabled; native save state dialog.

- Browser route: [export.html](../../export.html).

- Preserve: Empty disabled; UTF-8 named file; success/checkmark; cancellation neutral; actionable errors.

- State behavior: apply the Export contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/DayExportUI.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## A01

**Independent opt-in sources**

- Proposed location: Settings Auto capture independent source switches.

- Browser route: [settings.html](../../settings.html).

- Preserve: Clipboard and Screenshots off initially; privacy explanation; channels independent.

- State behavior: apply the Auto Capture contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/AutoCaptureSettings.swift;native/Sources/DaBin/AutoCaptureService.swift.

- Evidence status: PARTIAL BROWSER + NATIVE SPEC; native verification pending.

## A02

**Pause resume and status**

- Proposed location: Header auto status / Pause / Resume; Settings Source status.

- Browser route: [settings.html](../../settings.html).

- Preserve: Off/on/paused/excluded/permission/error distinct; immediate stop; existing captures retained.

- State behavior: apply the Auto Capture contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/AutoCaptureService.swift;native/Sources/DaBin/BoardView.swift;native/Sources/DaBin/StatusBarController.swift.

- Evidence status: PARTIAL BROWSER + NATIVE SPEC; native verification pending.

## A03

**Screenshot folder authorization**

- Proposed location: Settings Screenshot folder → Choose folder native contract.

- Browser route: [settings.html](../../settings.html).

- Preserve: Choose/change/re-authorize folder; security-scoped bookmark; monitor only authorized folder; clipboard independent.

- State behavior: apply the Auto Capture contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/ScreenshotFolderMonitor.swift;native/Sources/DaBin/SettingsScreen.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## A04

**Fresh baselines and deduplication**

- Proposed location: Auto capture native contract; fresh-baseline status copy.

- Browser route: [settings.html](../../settings.html).

- Preserve: No old clipboard/files on enable/resume/start; cross-channel duplicate suppression; timestamps/action identity.

- State behavior: apply the Auto Capture contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/AutoCaptureService.swift;native/Sources/DaBin/AutoCaptureFingerprint.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## A05

**Excluded apps**

- Proposed location: Settings Excluded apps; DaBin immutable; restore defaults.

- Browser route: [settings.html](../../settings.html).

- Preserve: Add/remove/restore defaults; DaBin cannot be removed; password defaults; best-effort origin explained.

- State behavior: apply the Auto Capture contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/AutoCaptureSettings.swift;native/Sources/DaBin/SettingsScreen.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## B01

**Home and reveal**

- Proposed location: Settings Robot home; Robot entry study; native safe-area contract.

- Browser route: [robot.html](../../robot.html).

- Preserve: Corners/compatible island; hidden rest; hover/drag; no flicker; fallback top-right; interacted display.

- State behavior: apply the Robot contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/RobotPlacementSettings.swift;native/Sources/DaBin/CornerController.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## B02

**Eating reactions**

- Proposed location: Robot reaction study with ten choices, shuffle and burst count.

- Browser route: [robot.html](../../robot.html).

- Preserve: Ten shuffled reactions; no recent-three repeat; generic token; exact burst count; one bounded popup; failures separate.

- State behavior: apply the Robot contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/AutoCaptureRobotCelebration.swift;native/Sources/DaBin/AutoCaptureRobotPresenter.swift.

- Evidence status: PARTIAL BROWSER + NATIVE SPEC; native verification pending.

## B03

**Open close transformation**

- Proposed location: Thin app frame; hide/restore; native transition storyboard.

- Browser route: [robot.html](../../robot.html).

- Preserve: Continuous body surface; reserved head/hands/feet; priority/cancellation safe; open current view; responsive close.

- State behavior: apply the Robot contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/RobotLifecycle.swift;native/Sources/DaBin/RobotAppFrameView.swift;native/Sources/DaBin/CornerController.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## B04

**Expressions and accessibility**

- Proposed location: Robot study plus Settings Quiet / Reduce Motion.

- Browser route: [robot.html](../../robot.html).

- Preserve: Clamped eased gaze; blink/bored/happy; Reduce Motion static/fade; Quiet; no hidden rendering loop or sound.

- State behavior: apply the Robot contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/RobotCharacterView.swift;native/Sources/DaBin/BoredRobotView.swift;native/Sources/DaBin/QuickAccess.swift.

- Evidence status: PARTIAL BROWSER + NATIVE SPEC; native verification pending.

## B05

**Move resize expand restore**

- Proposed location: Header drag region; outer resize handle; expand/restore.

- Browser route: [robot.html](../../robot.html).

- Preserve: Drag position; edge/corner resize; safe-area expand; compact restored; route/project/draft preserved.

- State behavior: apply the Robot contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/CornerController.swift;native/Sources/DaBin/BoardResizeGeometry.swift.

- Evidence status: PARTIAL BROWSER + NATIVE SPEC; native verification pending.

## B06

**Screens Spaces and focus**

- Proposed location: Native placement states; focus, Spaces and display contract.

- Browser route: [robot.html](../../robot.html).

- Preserve: Display changes recover; no unwanted Space switch/focus theft; decorative hit-test exclusion; screenshot sharing exclusion retained.

- State behavior: apply the Robot contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/CornerController.swift;native/Sources/DaBin/AutoCaptureRobotPresenter.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## B07

**Filter resize behavior**

- Proposed location: Bounded header and content scroll; native bottom resize contract.

- Browser route: [robot.html](../../robot.html).

- Preserve: Top stays anchored; bottom eases; screen clamp/scroll; Reduce Motion immediate.

- State behavior: apply the Robot contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/CornerController.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## P01

**Theme and appearance**

- Proposed location: Settings Appearance preset/custom/reset; light/dark.

- Browser route: [settings.html](../../settings.html).

- Preserve: Dark/light; Purple/Blue/Teal/Green/Rose/Amber; custom/reset; readable resolved accent.

- State behavior: apply the Preferences contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/ThemeSettings.swift;native/Sources/DaBin/SettingsScreen.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## P02

**Transparency and tooltip control**

- Proposed location: Settings opacity / solid reset / hover help / accessibility.

- Browser route: [settings.html](../../settings.html).

- Preserve: 35-100 percent opacity in 5 percent steps; solid reset; OS contrast/transparency override; tooltips off keeps accessible labels.

- State behavior: apply the Preferences contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/ThemeSettings.swift;native/Sources/DaBin/SettingsScreen.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## P03

**Global shortcut choices**

- Proposed location: Settings Robot & access predefined shortcuts/status.

- Browser route: [settings.html](../../settings.html).

- Preserve: Enable/disable; two modifier sets; registration errors; quiet mode; no general typing monitoring.

- State behavior: apply the Preferences contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/QuickAccess.swift;native/Sources/DaBin/SettingsScreen.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## P04

**Manual link preview consent**

- Proposed location: Settings Privacy manual link preview opt-in.

- Browser route: [settings.html](../../settings.html).

- Preserve: Off default; disclosure; earlier/new eligible manual links; turning off stops requests; automatic links never fetched.

- State behavior: apply the Preferences contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/PreviewService.swift;native/Sources/DaBin/SettingsScreen.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## P05

**Retention and clear history**

- Proposed location: Settings retention / clear eligible copies; exact count confirmation.

- Browser route: [settings.html](../../settings.html).

- Preserve: Never/7/30/90; protected work; exact confirmation; recoverable removal; progress/results/errors.

- State behavior: apply the Preferences contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/ClipboardRetentionService.swift;native/Sources/DaBin/ClipboardRetentionSettings.swift.

- Evidence status: PARTIAL BROWSER + NATIVE SPEC; native verification pending.

## P06

**Local archive privacy support**

- Proposed location: Settings archive / privacy / support / rebuild index.

- Browser route: [settings.html](../../settings.html).

- Preserve: Open archive; offline policy/data controls; configured support/policy links; rebuild search progress.

- State behavior: apply the Preferences contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/PrivacyInformation.swift;native/Sources/DaBin/SettingsScreen.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## P07

**Updates and visible version**

- Proposed location: Settings installed version / Get updates / Store-build behavior.

- Browser route: [settings.html](../../settings.html).

- Preserve: Direct Get updates/check/install/release link; truthful installed status; Store-managed alternative; no silent checks.

- State behavior: apply the Preferences contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/SoftwareUpdateService.swift;native/Sources/DaBin/SettingsScreen.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## P08

**Complete Quit**

- Proposed location: Settings Quit; neutral header X hides only.

- Browser route: [settings.html](../../settings.html).

- Preserve: Terminate process; preserve drafts; ask only if unsaved data cannot persist; hide X is different.

- State behavior: apply the Preferences contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/SettingsScreen.swift;native/Sources/DaBin/ApplicationCoordinator.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## D01

**Recently Deleted and Undo**

- Proposed location: Capture removal confirmation; toast Undo; Recently Deleted Restore.

- Browser route: [recently-deleted.html](../../recently-deleted.html).

- Preserve: Confirmation; undo latest; restore; task families/reminders; no external original deletion.

- State behavior: apply the Data contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/CaptureRemoval.swift;native/Sources/DaBin/TrashScreen.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## D02

**Permanent deletion**

- Proposed location: Recently Deleted Delete permanently separate confirmation.

- Browser route: [recently-deleted.html](../../recently-deleted.html).

- Preserve: Separate confirmation; journaled cleanup; error handling; never confused with collapse or shelf membership removal.

- State behavior: apply the Data contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/TrashScreen.swift;native/Sources/DaBin/CaptureStore.swift.

- Evidence status: BROWSER IMPLEMENTED; see QA_REPORT for scenario coverage; native verification pending.

## D03

**Verified archive backup restore**

- Proposed location: Backup & restore; fixture import/export and native conflict states.

- Browser route: [backup.html](../../backup.html).

- Preserve: Captures/originals/projects/shelf/snippets/notes/trash; checksums; additive no overwrite; conflicts/busy/draft handling.

- State behavior: apply the Data contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/ArchiveBackup.swift;native/Sources/DaBin/AppState.swift.

- Evidence status: PARTIAL BROWSER + NATIVE SPEC; native verification pending.

## D04

**Local dated archive**

- Proposed location: Settings Open local archive native contract.

- Browser route: [settings.html](../../settings.html).

- Preserve: Year/named numbered month/day folders; unique capture folder; authoritative DB; source originals kept; failed work recoverable.

- State behavior: apply the Data contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/DailyArchive.swift;native/Sources/DaBin/CaptureRepository.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## D05

**Draft and navigation recovery**

- Proposed location: Inbox/New note/New task and Detail recoverable drafts; restored route context.

- Browser route: [new-note.html](../../new-note.html).

- Preserve: Unfinished edits separate from saved captures; visible destination; route/project/selection retained; failed save reported.

- State behavior: apply the Data contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/DraftArchive.swift;native/Sources/DaBin/AppState.swift.

- Evidence status: PARTIAL BROWSER + NATIVE SPEC; native verification pending.

## K01

**Native menus and keyboard**

- Proposed location: Robot study status/application menus; in-document keyboard shortcuts.

- Browser route: [robot.html](../../robot.html).

- Preserve: Status item Open/state/Pause/Settings/Quit; app menu About/updates/Open/focus/Search/Settings/Edit/Hide/Quit; shortcuts; accessible focus.

- State behavior: apply the Keyboard contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/ApplicationMenu.swift;native/Sources/DaBin/StatusBarController.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.

## K02

**First launch and resume**

- Proposed location: Inbox first-run layout; same-session hide/reopen; native quiet launch contract.

- Browser route: [inbox.html](../../inbox.html).

- Preserve: First launch shows Inbox; later launch quiet; same-session reopen resumes route; global capture selects Daily.

- State behavior: apply the Keyboard contract above, retaining native ownership below. Initial, success, empty, failure and cancellation states must retain the last durable record; no optimistic success.

- Native ownership: native/Sources/DaBin/ApplicationCoordinator.swift;native/Sources/DaBin/CornerController.swift.

- Evidence status: NATIVE SPECIFICATION; native verification pending.
