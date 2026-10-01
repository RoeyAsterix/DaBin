# Feature preservation and usability acceptance

This is the acceptance plan for the redesign, not a claim that the redesign has already passed. Complete every FEATURES.csv row with a proposed destination, evidence link, and verification status. An intentionally simulated native interaction must say so.

## End to end scenarios

| ID | Scenario | Expected result |
|---|---|---|
| A01 | Reach a corner carrying text or a file, drop directly on the robot; then try unreadable input. | Robot remains reachable; saved content is retained with receipt time; only success gets celebration; failure is visible and recoverable. |
| A02 | Capture client feedback in Inbox, file to a project, convert to task, attach a PDF, add comment and reminder. | Same original feedback and provenance remain; task actions appear; attachment is accessible; dates have separate meanings. |
| A03 | Paste/drop several files at once, expand the batch, copy the group and one member, minimize and reopen. | One grouped card; members retained; complete native clipboard payload or a clear failure; no lost data. |
| A04 | Collect text, URL and files into a project Shelf; filter to links; export ZIP; remove one shelf membership. | ZIP includes the complete project shelf, names are disambiguated, original files untouched; removed member remains in Library. |
| A05 | Find an earlier copy using source/date/project/type, use Copy as plain text, return to the task. | Correct text on clipboard; no simulated external typing; selected task and workspace context restored. |
| A06 | Pin many items, name/rename a snippet, search its alias; receive a new copy while browsing older copies. | Recent remains reachable; alias search works; original content unchanged; browsing position is stable. |
| A07 | Write notes for two clients; switch projects; save a note as capture and turn another into a task; restart. | Correct separate scratchpads, selected project and saved records recover; conversion retains scratchpad text. |
| A08 | Plan tasks Today, reorder, set deadline and separate reminder, reschedule Tomorrow, complete/reopen. | Order and effort clear; deadline never silently schedules an alert; completion/reminders/unfinished views stay consistent. |
| A09 | Complete recurring monthly task with checklist and attachment. | One next occurrence; no backlog explosion or month drift; completed attachment remains accessible through previous occurrence. |
| A10 | Set countdown, close/reopen detail, edit comment, navigate away, restart and return. | Countdown not restarted; unsaved draft and destination recover; Save changes explicitly commits detail edits. |
| A11 | Browse a sparse week; search a day, week, all dates; filter results; press Return; Back. | No empty day columns; range is accurate; scoped query is visible; refinements persist; working context returns. |
| A12 | Search recognized screenshot/PDF text and project scratchpad, then enable nearby context. | Matches and context distinguished; only real metadata shown; scratchpad only matches All/Text without app filter and uses updated date for date scope; no invented source; text copy works. |
| A13 | Filter to Links, then copy/export an entire day and week. | Export ignores filters; selected scope is correct; both methods match; chronological original receipts without carried-task duplicates. Empty/cancel/error states are accurate. |
| A14 | Enable Clipboard only, then Screenshots with a chosen folder; pause during activity; revoke folder access. | Independent channels, clear consent/state, no existing-content import; clipboard not disabled by missing screenshot access; pause stops new records. |
| A15 | Save four automatic actions in one hour, expand/collapse; send rapid captures including cross-channel same image. | Fourth forms summary; count/dedup correct; collapse retains position; one robot with exact aggregate count, no success on failed saves. |
| A16 | Remove capture/task family, Undo, remove again, restore from Recently Deleted; test permanent delete cancellation. | Recoverable deletion preserves content/date/project; original files untouched; pending reminders handled; permanent action separately confirmed. |
| A17 | Set retention and clear unfiled copies while tasks/pins/snippets/shelf/project work exist. | Accurate confirmation; protected work retained; candidates move to recoverable trash; errors reported. |
| A18 | Back up and restore to an isolated store; test corrupt package and conflicting scratchpad. | Verified additive restore; conflicts stop without overwriting authored work; real user archive never used for fixtures. |
| A19 | Resize continuously between compact and expanded; change filters; switch displays/unplug external monitor. | No clipped tools/content, stable header, preserved state, recoverable safe-area placement and compact geometry. |
| A20 | Open via shortcut, robot and menu bar; Escape/back through popovers; hide, then Quit. | Predictable focus, text editing intact, no Space switch; close hides; Quit terminates rather than leaving invisible work. |
| A21 | Inspect direct-build and Store-build Settings. | Installed version/status visible; functional direct Get updates only where compiled; Store path truthful; redesign never implies a published build exists. |
| A22 | Use Reduce Motion, Reduce Transparency, Increase Contrast, Quiet mode, and tooltips off. | Workflows unchanged; contrast readable; quiet/static alternatives; accessibility labels survive tooltip setting. |

## Readability and interaction review

- Inspect minimum 380 × 430 pt content, 380 × 680, 760 × 680 and large workspace, both appearances, every preset/custom accent extremes, and 1×/2× scale.
- Try long filenames/URLs/project names, mixed right-to-left/left-to-right text, lengthy comments and scratchpads, empty collections, missing saved files, many pinned items, large history, denied permissions, and interrupted saves.
- Check keyboard order, visible focus, names/roles/states, menu/popover Escape/outside click, return focus, and native text editing. Test VoiceOver where native environment permits; otherwise mark pending.
- Target at least 4.5:1 for ordinary text and 3:1 for meaningful non-text UI. Measure resolved colors against actual surfaces; color alone must not carry state. These are design acceptance targets, not certification claims.
- Measure steps for capture, turn into task, search/reuse, project switch, reminder, export, and settings. Compare identical tasks and input; distinguish text entry from clicks. Justify any increase in frequent-flow steps.
- Judge the actual-size view as well as enlarged detail. Compact chrome cannot consume most of a short window. Test target spacing and discoverability, not only visual alignment.

## Native engineering gates after implementation

The design-only prototype does not satisfy native release gates. Implementation must preserve the existing test inventory and add focused coverage for changed interactions. From `native/` use:

```sh
./scripts/test.sh --configuration Release
./scripts/build.sh
python3 scripts/generate_project.py --check
python3 scripts/app_store_preflight.py --static-only
```

Also run `git diff --check` from the repository root. There is no separately configured Swift lint task; the build treats warnings as errors. Do not report invented lint/type-check commands. Native build/test needs Apple tooling and GUI checks need an unlocked macOS session.

Baseline build 53 recorded 50/50 native suites passing, 26 static Store checks, and 66 synthetic renders. These are historical baseline results, not results for future redesign code. Priority regressions: HeaderInteraction, WorkspaceWindow, ConnectedWorkflow, ProductFoundation, CaptureTaskConversion, TaskPlanning, WeeklyState/Window, DayExport/UI, LocalContentSearch, ClipboardRetention, ArchiveBackup, AutoCaptureService/HourlyGrouping, RobotLifecycle/AppFrame/WindowTransition, QuickAccess, ThemeSettings, and update configuration.

Verify real native drag/drop, pasteboard content, file dialogs, focus return, safe areas, notch/external fallback, display changes, screenshot exclusion limitations, notifications, and restart recovery separately. Use isolated stores/private pasteboards for automated fixtures. No personal archive changes for QA.

## Final deliverable review

Return the prototype entry point; editable design files; component/token kit; screen/state index; completed feature matrix; old-to-new navigation map; robot motion specification; native source mapping; actual-scale before/after screens; scenario and accessibility results; and an honest limitations list.

If a feature cannot be demonstrated, supply a complete state/interaction specification and mark native verification pending. Do not delete it, label it done, or hide it behind an unimplemented control.
