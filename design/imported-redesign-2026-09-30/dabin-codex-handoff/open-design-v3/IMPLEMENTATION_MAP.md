# Native source mapping

Do not copy browser storage into the shipping architecture. Source ownership stays unchanged. HTML/JS are interaction references.

| Feature | Proposed location | Existing source owner |
|---|---|---|
| C01 Robot direct drag and drop | Robot direct drop; Inbox and task attachment drop targets | RobotView.swift; InputService.swift |
| C02 Explicit robot paste | Robot Paste; active panel paste excluding editable fields | RobotView.swift |
| C03 Board intake | Inbox composer and board paste/drop | DailyCaptureView.swift; InboxScreen.swift |
| C04 Add menu | Header + menu: Paste, New note, Import files, New task | BoardView.swift |
| C05 Inline quick capture | Inbox quick composer; explicit destination and restored draft | InboxScreen.swift; DraftArchive.swift |
| C06 Supported data and file batches | Grouped file card with clickable members; native payload contract | InputService.swift; GroupedCaptureCard.swift |
| C07 Keep and organize | Capture actions: Keep, File to project, Turn into task, Plan for Today | InboxScreen.swift |
| V01 Fitted previews and fallbacks | Preview-led card and capture detail original content pane | CapturePreviews.swift; FittedPDFPreview.swift |
| V02 Receipt and provenance | Card receipt/source; Detail provenance block | CaptureSourceView.swift; Domain.swift |
| V03 Copy individual or grouped content | Upper-right Copy; grouped native clipboard state dialog | CaptureCopyButton.swift; CaptureClipboard.swift |
| V04 Comment editing | Detail Comment; Save changes; recovered edit banner | DetailScreen.swift; DraftArchive.swift |
| V05 Reminder editing | Detail Reminder link; separate reminder screen | DetailScreen.swift; ReminderClockEditor.swift |
| V06 Minimize and expand | Capture Actions → Minimize / Expand preview | CaptureCards.swift; CapturePresentation.swift |
| V07 Link and local file actions | Detail Open original; File location native state dialog | WorkspaceItemCard.swift; AppState.swift |
| V08 Pin and project association | Detail project + pin; card action equivalents | DetailScreen.swift; WorkspaceItemCard.swift |
| T01 Capture conversion | Turn into task → same record in Task Detail | DetailScreen.swift; CaptureStore.swift |
| T02 Task status | Today checkbox; task detail Complete/Reopen | CaptureCards.swift; CaptureStore.swift |
| T03 Today planning scopes | Today / Upcoming / Completed; unplanned, unfinished and reminders sections | TodayPlanningScreen.swift |
| T04 Planned day and reschedule | Task menu Today/Tomorrow/clear; Work plan custom date | TaskPlanningEditor.swift; TaskPlanning.swift |
| T05 Priority effort and ordering | Work plan Priority/Effort; Today Move earlier/later | TodayPlanningScreen.swift; TaskPlanningEditor.swift |
| T06 Separate deadline | Work plan Deadline, separate from planned date and reminder | TaskPlanningEditor.swift |
| T07 Recurrence | Work plan Repeat; Previous and Next occurrence links | TaskPlanning.swift; DetailScreen.swift |
| T08 Checklists | Checklist rows; add/remove/edit/check; explicit save | TaskPlanningEditor.swift |
| T09 New attachments | Task Attachments → Import / Paste; task panel drop | TaskAttachmentsView.swift; DailyCaptureView.swift |
| T10 Existing attachments and navigation | Task Attachments → Saved item; child detail → Parent | WorkspaceItemCard.swift; TaskAttachmentsView.swift; DetailScreen.swift |
| T11 New task composer | Add → New task; destination label; recovered draft | TaskEditorScreen.swift |
| R01 Date/time and countdown | Reminder Date & time / Countdown; persisted target time | ReminderClockEditor.swift; ReminderSchedule.swift |
| R02 Notification delivery state | Reminder and Settings → Notification status native dialog | ReminderService.swift; SettingsScreen.swift |
| R03 Non-task follow-up actions | Today non-task reminder row → Done / Tomorrow | TodayPlanningScreen.swift |
| H01 Daily calendar history | Activity Day date group; previous/next/calendar/Today | DailyScreen.swift; BoardView.swift |
| H02 Weekly history | Activity Week, seven days ending on selected date | WeeklyScreen.swift; AppState.swift |
| H03 Task carryover | Activity Still open section; original receipt label | CapturePresentation.swift; AppState.swift |
| H04 Content type filters | Context type strip: All, Text, Links, Files, Media, Tasks | CaptureFilterStrip.swift; Domain.swift |
| H05 Automatic hourly summaries | Activity hourly summary; disclosure and named collapse action | HourlyCaptureFeed.swift; HourlyCaptureCard.swift |
| H06 Batch actions | Grouped file card → member detail; Actions minimize; native atomic copy contract | GroupedCaptureCard.swift; CaptureCardGroup.swift |
| S01 Global archive search | Header Search / ⌘K; results across text, OCR, filenames, snippets and notes | SearchScreen.swift; AppState.swift |
| S02 Day week and all scopes | Search All/Day/Week; Activity scoped search buttons | WeeklyScopeActions.swift; AppState.swift |
| S03 Refinements and context | Search type/project/app; nearby context; Workspace refinements | SearchScreen.swift; WorkspaceQuery.swift |
| S04 Empty recovery and Back | Empty Search → Clear refinements / Search all dates; Back | SearchScreen.swift; AppState.swift |
| S05 Local OCR and text indexing | Detail recognized text/status; Settings rebuild index | ContentIndexService.swift; DetailScreen.swift |
| W01 Project spaces | Shared project selector; Create project; detail association | LibraryScreen.swift; WorkspaceStore.swift |
| W02 Four connected modes | Workspace Library / Clipboard / Shelf / Notes | LibraryScreen.swift; WorkspaceStore.swift |
| W03 Library browsing | Library preview grid/list; type strip and refinement dialog | LibraryScreen.swift; WorkspaceItemCard.swift |
| W04 Recent copied material | Clipboard Recent, separate Pinned and Snippets views | WorkspaceQuery.swift; LibraryScreen.swift |
| W05 Named reusable snippets | Capture Actions → Name / Rename / Remove snippet alias | WorkspaceItemCard.swift; WorkspaceStore.swift |
| W06 Copy as plain text | Capture Actions and Detail → Copy as plain text | WorkspaceClipboard.swift |
| W07 Persistent collection | Shelf Add from Library / intake; Remove from shelf; keep capture | ShelfCaptureController.swift; WorkspaceStore.swift; LibraryScreen.swift |
| W08 Project shelf ZIP | Shelf Export shelf, full selected project collection | ShelfExport.swift |
| W09 Project and unfiled scratchpads | Notes project/unfiled scratchpads; autosave status/retry | ScratchpadView.swift; WorkspaceStore.swift |
| W10 Convert scratchpad | Notes Save as note / Make task; scratchpad retained | ScratchpadView.swift |
| E01 Copy and text export day | Activity Day → Export → Copy / Text file | DayExport.swift; BoardView.swift |
| E02 Copy and text export week | Activity Week → Export → Copy / Text file | DayExport.swift; BoardView.swift |
| E03 Export feedback and dialogs | Export preview; empty disabled; native save state dialog | DayExportUI.swift |
| A01 Independent opt-in sources | Settings Auto capture independent source switches | AutoCaptureSettings.swift; AutoCaptureService.swift |
| A02 Pause resume and status | Header auto status / Pause / Resume; Settings Source status | AutoCaptureService.swift; BoardView.swift; StatusBarController.swift |
| A03 Screenshot folder authorization | Settings Screenshot folder → Choose folder native contract | ScreenshotFolderMonitor.swift; SettingsScreen.swift |
| A04 Fresh baselines and deduplication | Auto capture native contract; fresh-baseline status copy | AutoCaptureService.swift; AutoCaptureFingerprint.swift |
| A05 Excluded apps | Settings Excluded apps; DaBin immutable; restore defaults | AutoCaptureSettings.swift; SettingsScreen.swift |
| B01 Home and reveal | Settings Robot home; Robot entry study; native safe-area contract | RobotPlacementSettings.swift; CornerController.swift |
| B02 Eating reactions | Robot reaction study with ten choices, shuffle and burst count | AutoCaptureRobotCelebration.swift; AutoCaptureRobotPresenter.swift |
| B03 Open close transformation | Thin app frame; hide/restore; native transition storyboard | RobotLifecycle.swift; RobotAppFrameView.swift; CornerController.swift |
| B04 Expressions and accessibility | Robot study plus Settings Quiet / Reduce Motion | RobotCharacterView.swift; BoredRobotView.swift; QuickAccess.swift |
| B05 Move resize expand restore | Header drag region; outer resize handle; expand/restore | CornerController.swift; BoardResizeGeometry.swift |
| B06 Screens Spaces and focus | Native placement states; focus, Spaces and display contract | CornerController.swift; AutoCaptureRobotPresenter.swift |
| B07 Filter resize behavior | Bounded header and content scroll; native bottom resize contract | CornerController.swift |
| P01 Theme and appearance | Settings Appearance preset/custom/reset; light/dark | ThemeSettings.swift; SettingsScreen.swift |
| P02 Transparency and tooltip control | Settings opacity / solid reset / hover help / accessibility | ThemeSettings.swift; SettingsScreen.swift |
| P03 Global shortcut choices | Settings Robot & access predefined shortcuts/status | QuickAccess.swift; SettingsScreen.swift |
| P04 Manual link preview consent | Settings Privacy manual link preview opt-in | PreviewService.swift; SettingsScreen.swift |
| P05 Retention and clear history | Settings retention / clear eligible copies; exact count confirmation | ClipboardRetentionService.swift; ClipboardRetentionSettings.swift |
| P06 Local archive privacy support | Settings archive / privacy / support / rebuild index | PrivacyInformation.swift; SettingsScreen.swift |
| P07 Updates and visible version | Settings installed version / Get updates / Store-build behavior | SoftwareUpdateService.swift; SettingsScreen.swift |
| P08 Complete Quit | Settings Quit; neutral header X hides only | SettingsScreen.swift; ApplicationCoordinator.swift |
| D01 Recently Deleted and Undo | Capture removal confirmation; toast Undo; Recently Deleted Restore | CaptureRemoval.swift; TrashScreen.swift |
| D02 Permanent deletion | Recently Deleted Delete permanently separate confirmation | TrashScreen.swift; CaptureStore.swift |
| D03 Verified archive backup restore | Backup & restore; fixture import/export and native conflict states | ArchiveBackup.swift; AppState.swift |
| D04 Local dated archive | Settings Open local archive native contract | DailyArchive.swift; CaptureRepository.swift |
| D05 Draft and navigation recovery | Inbox/New note/New task and Detail recoverable drafts; restored route context | DraftArchive.swift; AppState.swift |
| K01 Native menus and keyboard | Robot study status/application menus; in-document keyboard shortcuts | ApplicationMenu.swift; StatusBarController.swift |
| K02 First launch and resume | Inbox first-run layout; same-session hide/reopen; native quiet launch contract | ApplicationCoordinator.swift; CornerController.swift |

Implement in the existing SwiftUI/AppKit components; retain versioned Core Data payloads, managed-file storage, state machines and tests. No migration or production installation is part of this handoff.
