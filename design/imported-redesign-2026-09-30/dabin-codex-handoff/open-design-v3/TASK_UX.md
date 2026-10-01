# DaBin task interaction handoff

## Surfaces

- inbox.html / workspace.html / activity.html / weekly.html: capture footer exposes Copy, Project, Turn into task and Keep. Conversion retains the same record and its original filter/source type, replacing its appearance with a task card. Undo restores the prior task fields.
- today.html: task cards with completion, duration, play/pause and calendar. Planned, unfinished and unplanned tasks remain separate sections.
- task-detail.html: task heading, icon priority, timer, calendar, checklist. Notes, original content/attachments, repeat and deadline stay in compact disclosure sections. No select controls in this task editor.
- new-task.html: title/context, day with optional time, hours/minutes and duration presets.
- Shared project scope: named icon choices instead of a select.

## State and persistence

Existing `effort` remains total minutes; UI converts it to hours/minutes. `scheduledTime` is an optional local HH:MM paired with `planned` (YYYY-MM-DD). These fields do not modify receipt `date` or notification `reminder`.

Focus state is optional `focus: {remaining: seconds, endAt?: epochMilliseconds}`. Running countdowns derive from endAt rather than decrementing persisted counters. Pause stores the exact remaining seconds. Resume creates a new endAt. Reset clears focus state to the configured duration. Timer expiry persists remaining=0 and announces completion inside the open browser. It does not complete the task or schedule an OS notification. Task completion stops its running timer; recurrence clones omit focus/countdown state.

Duration accepts positive integer minutes up to 10,080 (168 hours); minutes input is 0–59. An unconfigured task opens duration setup from Play. Starting a finished session restarts the configured full duration. Multiple tasks can retain independent timers.

Timer, project and schedule writes use the existing rollback-aware persistence function. Open title/checklist/note drafts survive these changes. No per-second storage writes occur while a timer is running. Window style, expanded state and content scroll survive render updates.

## Native implementation boundary

The browser timer and schedule controls are new UX behavior in this refinement. Port them to the native task data model and lifecycle before treating them as shipping macOS functionality. Persist the end timestamp, handle sleep/wake and clock changes, and keep focus completion separate from task completion and notification reminders. System notification delivery, closed-app behavior and native accessibility remain unverified. The frozen source/native folder is unchanged.

## Verification

253 syntax, structure, route, state, form, export and contrast checks pass via verify.py. Focus assertions cover pause/resume, persistence, background delay, expiry, restart, completion, recurrence and failed saves. Conversion checks cover appearance, identity, media retention, Undo and failed persistence. Duration and schedule submissions are exercised directly.

HTMLParser checks verify balanced Inbox/Today/task/new-task markup and form containment. These are not rendered browser tests. The installed project renderer is unavailable; compact/expanded visual QA and native validation remain pending.
