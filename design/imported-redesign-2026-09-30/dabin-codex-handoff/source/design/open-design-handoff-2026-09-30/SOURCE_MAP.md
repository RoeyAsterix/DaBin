# Native source and implementation map

All paths below are relative to the repository/package root. The ZIP includes a frozen native source snapshot from commit `b3f8507a77107474f923d9e4af5fc8ad4efe4a00`. It is implementation reference, not an installer. It excludes build outputs, personal records, credentials, the Git database, and obsolete handoff source.

## UI and state ownership

| Area | Primary files under native/Sources/DaBin |
|---|---|
| Shell, navigation, routes and drafts | BoardView.swift, AppState.swift, BoardComponents.swift, BuddyControls.swift, DraftArchive.swift |
| Inbox, Today, Workspace | InboxScreen.swift, TodayPlanningScreen.swift, LibraryScreen.swift, WorkspaceItemCard.swift |
| Project/collection state | WorkspaceStore.swift, WorkspaceQuery.swift, WorkspaceClipboard.swift, ScratchpadView.swift, ShelfCaptureController.swift, ShelfExport.swift |
| Timeline and grouping | DailyScreen.swift, WeeklyScreen.swift, CaptureCards.swift, CaptureCardGroup.swift, GroupedCaptureCard.swift, HourlyCaptureFeed.swift, HourlyCaptureCard.swift, CaptureFilterStrip.swift |
| Capture and task detail | DetailScreen.swift, TaskEditorScreen.swift, NewNoteScreen.swift, TaskPlanning.swift, TaskPlanningEditor.swift, TaskAttachmentsView.swift |
| Preview, source, copy | CapturePreviews.swift, PreviewService.swift, FittedPDFPreview.swift, CaptureSourceView.swift, CaptureCopyButton.swift, CaptureClipboard.swift |
| Search and export | SearchScreen.swift, ContentIndexService.swift, WeeklyScopeActions.swift, DayExport.swift, DayExportUI.swift |
| Reminders | ReminderClockEditor.swift, ReminderSchedule.swift, ReminderService.swift, ReminderLifecycle.swift |
| Input and persistence | InputService.swift, DailyCaptureView.swift, Domain.swift, CaptureStore.swift, CaptureRepository.swift, DailyArchive.swift, OriginalFileStorage.swift |
| Deletion and backup | CaptureRemoval.swift, TrashScreen.swift, ArchiveBackup.swift, ClipboardRetentionService.swift |
| Automatic capture | AutoCaptureService.swift, AutoCaptureSettings.swift, ScreenshotFolderMonitor.swift, AutoCaptureFingerprint.swift |
| Robot/window lifecycle | CornerController.swift, RobotLifecycle.swift, RobotMotion.swift, IslandRobotChoreography.swift, RobotAppFrameView.swift, RobotCharacterView.swift, RobotView.swift, BoardResizeGeometry.swift, WindowDragHandle.swift |
| Automatic animation | AutoCaptureRobotPresenter.swift, AutoCaptureRobotCelebration.swift, BoredRobotView.swift |
| Theme, logo and settings | ThemeSettings.swift, DaBinLogo.swift, SettingsScreen.swift, ClipboardRetentionSettings.swift, RobotPlacementSettings.swift, PrivacyInformation.swift |
| Entry points and update boundary | ApplicationCoordinator.swift, ApplicationMenu.swift, StatusBarController.swift, QuickAccess.swift, SoftwareUpdateService.swift, UpdateHandoff.swift |

Retain these boundaries. Avoid a monolithic redesigned view with duplicated storage or animation state. The Core Data versioned payload remains authoritative; readable archive folders and caches are not independent editable databases. A web prototype must not replace native ingestion, local storage, UserNotifications, or security-scoped file access.

## Keyboard preservation

| Action | Existing equivalent |
|---|---|
| Global search | ⌃⌥Space or optional ⌃⌥⇧Space |
| Global capture clipboard | ⌃⌥V or optional ⌃⌥⇧V |
| Open DaBin | ⌘O |
| Focus robot for paste | ⌘⇧V |
| Universal search | ⌘K |
| Today | ⌘⇧D |
| Settings | ⌘, |
| Save detail | ⌘S |
| Add task | ⌘Return in task composer |
| Paste at robot | ⌃V or ⌘V |
| Robot open or dismiss | Return or Escape |
| Week-scoped search | ⌘7 in the applicable weekly search interaction |

Preserve native responder-chain editing and modifier behavior. Global shortcuts offer two predefined combinations and disable/conflict handling; there is no arbitrary key recorder. Per-screen Escape should dismiss the innermost transient UI before hiding the app when appropriate.

## Current limits and deferred work

Current supported runtime is Apple Silicon macOS 14+. Older supported OS versions still need runtime verification; do not claim Windows, Linux, Intel, cloud sync, or web parity. Runtime evidence was collected on macOS 26.6.2 with Xcode 27.

No account, analytics, ads, external OCR/AI, semantic search, launch-at-login control, or silent update checks are implemented. Screenshots are observed from an authorized folder or clipboard, not by taking live screen captures. Source app is best effort. URLs can save without networking; opt-in manual link previews and explicit update checks are disclosed network operations.

Imported files are managed copies. Live external references, folder watching beyond the selected screenshot folder, arbitrary folder ingestion, and automatic filesystem organization are not current features. Source-location metadata must not be confused with an active file reference.

Deferred roadmap: task-linked focus timer; editable time records/CSV; quiet schedules; calendar timeboxing; live file/folder references; batch rename/image resize/text cleanup; organization recipes; sequential paste/text expansion; optional selected-content AI. Preserve space for sensible extension, but do not add these as working controls or use them to replace existing features.

Validation boundaries include checklist 100 steps, 1–500 characters each; effort 1–10,080 minutes; countdown hours 0–99/minutes 0–59 and nonzero duration. Keep helpful validation rather than silent failure. OCR/indexing has bounded pages/bytes/text; large-document limits are explicit in source.

## Evidence status

The baseline QA report records 50/50 native suites and 26 static Store checks. Build 53 uses the compact two-row primary header, not the earlier Daily-only toolbar. These checks were completed before this design handoff; creating this package does not constitute another native QA run.

Current images are production SwiftUI/AppKit view renders with synthetic data. Historical build-50 details/timeline/robot-frame references are separately labeled. The screenshots are design context, not approval of the current appearance or proof of native OS interactions. The source snapshot is the fallback for features without screenshots.

No TestFlight upload or public binary publication is part of this handoff. Store readiness, signing/notarization and update integrity must remain separate engineering gates.
