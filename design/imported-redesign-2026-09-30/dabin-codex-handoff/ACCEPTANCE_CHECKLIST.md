# DaBin implementation acceptance

Use isolated synthetic data and a development archive. Check off items only with observed evidence from the redesigned native implementation. The supplied reference checks are not a substitute. Record build/commit, OS, window size, input method, result and evidence path for each run.

## Visual and navigation

- [ ] Compact light and dark windows preserve the metallic-purple robot identity, neutral surfaces, thin frame and no-sidebar layout.
- [ ] Inbox / Today / Workspace / Activity remain labeled and reachable; current destination and project are immediately clear.
- [ ] Frequent capture/task actions are direct icons with meaningful accessible labels and visible focus; no menu is required for task conversion.
- [ ] Content previews remain fitted and readable. Long project names, filenames, URLs and mixed Hebrew/Japanese/English text do not collide with actions.
- [ ] Workspace heading shows the selected project on Library, Clipboard, Shelf and Notes. All projects / Unfiled are correct fallback scopes.
- [ ] Project search, empty results, selection, inline creation, duplicate/invalid-name feedback and cancelled creation work without losing current drafts.
- [ ] New project selection persists across navigation, collection switches, app hide/reopen and restart.
- [ ] Project panel stays in bounds at top/bottom anchors; keyboard traversal and Escape return focus correctly.

## Tasks and timing

- [ ] Convert a text capture and a media capture: each visibly becomes a task card in place with completion, duration, play/pause and schedule controls.
- [ ] Conversion retains ID, receipt day/time, content type, files, project and provenance. Undo restores prior task fields without losing original data.
- [ ] Failed conversion save leaves recoverable state and does not claim success.
- [ ] Duration accepts hours/minutes, rejects zero/invalid/over-limit totals, and offers duration setup from an unconfigured Play.
- [ ] Start → navigate away → reopen → pause → resume → reset produces the correct clock. UI updates do not persist every second.
- [ ] Sleep/wake, app restart, a delayed UI tick and system-clock adjustment follow the documented native timing policy.
- [ ] Expiry shows Time’s up while leaving the task incomplete. Restart begins the configured duration; task completion stops the timer.
- [ ] Independent task timers do not overwrite one another; recurring completion creates only one next task without inherited focus/paste history or duplicated attachments.
- [ ] Today / Tomorrow / date + optional time / Clear change the plan without changing receipt, deadline or notification reminder.
- [ ] Timer, project and schedule changes preserve unsaved title/checklist/note edits. Explicit Save commits the editor correctly; failed writes retain recoverable drafts.
- [ ] Calendar behavior is checked across month-end, DST and local time-zone changes. Never copy the fixture's fixed Today date into production.

## Content trail

- [ ] Captures, converted tasks, both detail views and robot last-saved item show source → destination logos consistently.
- [ ] History reveals product names, individual event timestamps and manual/confirmed labels; repeated pastes share a compact logo without deleting event history.
- [ ] More than three destinations collapse cleanly; unknown app/icon/source fallbacks remain truthful and accessible.
- [ ] Copy alone adds no paste event. App focus alone adds no confirmed receipt. A failed native paste adds no confirmed receipt.
- [ ] Manual recording is useful without monitoring permissions. Confirmed records exist only where a supported successful paste operation is actually verified.
- [ ] New provenance survives restart, backup/restore and conversion; old records decode without invented history. Failed saves roll back safely.
- [ ] No automatic remote icon/favicon requests or inferred document/channel names occur.

## Preserved product behavior

- [ ] Every one of the 80 rows in `open-design-v3/FEATURES.csv` is mapped to implemented native UI/service evidence, with no silent deletion.
- [ ] Original receipt-day archive, grouped-file intake/copy, hourly grouping and source-type filters remain correct for converted tasks.
- [ ] Library, Recent/Pinned/Snippets, project shelf and project/Unfiled scratchpads preserve their different purposes and persistence.
- [ ] Scratchpad conversion retains text. Removing a shelf member preserves its capture. Shelf export includes the entire selected project shelf regardless of visible filters.
- [ ] Search, local OCR/indexing, nearby context and Back retain the correct query/scope/position. Day/week exports ignore content filters as specified.
- [ ] Clipboard/screenshot opt-ins, pause, exclusions, authorization revocation, fresh baselines and deduplication retain existing semantics.
- [ ] Retention protects kept/organized/pinned captures, tasks, reminders, snippets and shelf items. Removal uses recoverable trash; permanent deletion requires its separate confirmation.
- [ ] Native backup/restore verifies integrity, handles corrupt/conflicting archives and includes new state without overwriting authored work.
- [ ] Native menus/global shortcuts, hide versus Quit, direct/Store update differences and local-only privacy behavior remain intact.

## Window, robot and accessibility gates

- [ ] Render the native 400×480 outer / 380×430 content minimum and an expanded window in both light/dark; inspect actual text and control bounds.
- [ ] Render the reference at 360×640, 390×844, 400×480, 430×360, 600×480, 768×1024, 1024×768, 1440×900 and 1920×1080. Record screenshots and actual DOM/visual issues separately from mathematical bounds tests.
- [ ] Native continuous drag/resize, expand/restore, display unplug, menu bar/Dock safe areas, Spaces and backing-scale 1×/2× preserve usable placement and content state.
- [ ] Short windows/dialogs scroll correctly. Re-rendering task/project actions does not unexpectedly reset window size or content scroll.
- [ ] Robot single-click paste and double-click Inbox are disambiguated, capture is not duplicated, and hover alone does not read the clipboard.
- [ ] Robot intake remains a stable native drop/paste target. Success feedback appears only after successful persistence; failures remain visible and recoverable.
- [ ] Ten automatic reaction variants, burst aggregation, interruption and quiet/reduced-motion behavior match `ROBOT_MOTION.md` without stealing focus.
- [ ] Full keyboard-only paths, responder-chain editing and VoiceOver work. Modals/popovers restore focus; Escape dismisses the innermost transient UI first.
- [ ] Readable contrast, increased contrast, Reduce Motion, Reduce Transparency, Quiet and hover-help preferences work in actual rendered states.
- [ ] Native file promises, binary pasteboards, security-scoped access, notification delivery and archive recovery are verified on macOS, not merely simulated.

## Reproducible validation and sign-off

Reference checks from the extracted package root (macOS required for JavaScriptCore):

```sh
python3 open-design-v3/build.py
python3 open-design-v3/verify.py
```

After implementation, run the documented equivalents in the **active native repository** from its `native/` directory, after checking its current tooling:

```sh
./scripts/test.sh --configuration Release
./scripts/build.sh
python3 scripts/generate_project.py --check
python3 scripts/app_store_preflight.py --static-only
```

Run `git diff --check` from the repository. Existing named suites include HeaderInteraction, WorkspaceWindow, ConnectedWorkflow, CaptureTaskConversion, TaskPlanning, WeeklyState/Window, DayExport/UI, LocalContentSearch, ClipboardRetention, ArchiveBackup, AutoCaptureService, HourlyGrouping, RobotLifecycle/AppFrame/WindowTransition, QuickAccess and ThemeSettings. Add tests for new timer, provenance and migration behavior at their actual native ownership boundaries.

- [ ] Provide exact commands, pass/fail results and build identity; do not reuse historical baseline counts as new results.
- [ ] Deliver screenshots for Inbox, converted task, Today timer, project picker/creation, content history and minimum-size dark mode, plus resolved issue notes.
- [ ] Separate implemented, automated-checked, visually-reviewed and native-verified status. All remaining release gates are explicit.
- [ ] No production archive, installed application, release channel or public binary was modified by accident.
