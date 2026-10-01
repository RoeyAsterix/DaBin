# DaBin native application architecture

DaBin is a self-contained Apple Silicon macOS application. It uses Swift, AppKit and SwiftUI with Apple's system frameworks. There is no browser runtime, local web server, JavaScript bridge, companion process, package download or remote backend required to capture and browse content.

## Boundaries

| Layer | Responsibility | Main files |
| --- | --- | --- |
| Entry and macOS lifecycle | Start the application, respond to reopen/quit, present native quit decisions | `DaBinMain.swift`, `AppDelegate.swift` |
| Composition | Own one archive, services, preferences, state and panel controller for the session; start once and shut down explicitly | `ApplicationCoordinator.swift` |
| Native commands | Standard macOS About/Hide/Quit, responder-chain editing and explicitly registered global search/capture chords | `ApplicationMenu.swift`, `QuickAccess.swift` |
| Desktop integration | Per-display reveal targets, camera-island geometry, robot character and motion state, paste/drop destinations, keyboard focus, panel placement, automatic-capture reaction rotation and animations | `CornerController.swift`, `RobotView.swift`, `RobotCharacterView.swift`, `RobotMotion.swift`, `RobotLifecycle.swift`, `RobotAppFrameView.swift`, `AutoCaptureRobotCelebration.swift`, `AutoCaptureRobotPresenter.swift`, `DailyCaptureView.swift`, `WindowDragHandle.swift` |
| Presentation | Inbox/Today/Workspace shell, persistent search, Add/More menus, date browsing, hourly summaries and shared cards; no database construction | `BoardView.swift`, `LibraryScreen.swift`, `TrashScreen.swift`, `NewNoteScreen.swift`, `DayExportUI.swift`, feature screen files, shared capture components |
| State and domain | Navigation, drafts, chronological membership, filters, task carryover, source facts, selected-day and fixed-week search context, and deterministic day/week export text | `AppState.swift`, `Domain.swift`, `TaskPlanning.swift`, `DayExport.swift` |
| Capture intake | Read only explicit paste/drop transfers; preserve receipt time; coordinate promised files and partial failures | `InputService.swift` |
| Optional automatic intake | Gate opt-in clipboard and screenshot-folder monitoring; retain the user-selected folder grant; apply source exclusions and duplicate suppression; stop promptly on pause, disable and shutdown | `AutoCaptureService.swift`, `ScreenshotFolderMonitor.swift`, `AutoCaptureFingerprint.swift`, `AutoCaptureSettings.swift` |
| Capture copy | Reconstruct one visible action from immutable text/link values or validated managed originals, then perform one native pasteboard write | `CaptureClipboard.swift`, `CaptureCopyButton.swift` |
| Persistence | Transactional metadata, owned originals, readable dated archive, recoverable trash, validated backups and interrupted-operation recovery | `CaptureStore.swift`, `CaptureRepository.swift`, `ArchiveBackup.swift`, `DailyArchive.swift`, `OriginalFileStorage.swift`, `CaptureRemoval.swift` |
| Disposable previews | Bounded parallel local previews, optional website requests, cancellation/timeout bridging, cache regeneration | `PreviewService.swift`, `PreviewRequest.swift` |
| Local content index | Bounded on-device Vision/PDFKit/text extraction, legacy indexing, retry and removal-safe publication; no network collaborator | `ContentIndexService.swift` |
| Reminders | Serialized scheduling, revision checks, permission feedback and wake/activation reconciliation | `ReminderService.swift`, `ReminderLifecycle.swift` |
| Preferences and policy | Shared local theme, board placement, robot-home, previews and Auto Capture settings; accessible bundled privacy information | `ThemeSettings.swift`, `RobotPlacementSettings.swift`, `AutoCaptureSettings.swift`, `PrivacyInformation.swift`, `Resources/` |

The Xcode navigator groups these boundaries. Sources remain in one flat directory so the portable build and Xcode inventory use the same files.

## Ownership and shutdown

`ApplicationCoordinator` constructs all production dependencies and passes them to the desktop controller and views. Tests inject temporary storage, isolated preferences, fake notification clients, private event centers and synthetic pointer positions.

Startup is idempotent. Shutdown removes the pointer and animation timers, local keyboard monitor, desktop notifications and view callbacks. It detaches native hosting views before closing panels so SwiftUI state can be released, stops Auto Capture's clipboard and folder observers, stops new lifecycle reconciliations, and cancels queued/running preview work. A reconciliation already underway may finish; an already-started disposable thumbnail write may also finish. A stopped controller rejects stale reveal requests. Saved system reminders survive normal quit; deleting a capture separately cancels its reminder. The app does not install a background helper or launch-at-login service, so Auto Capture operates only while DaBin is running.

The first launch opens Inbox once for discoverability. After dismissal, screen corners are the default reveal target, and a setting can move the robot below a compatible built-in camera island. Displays without camera-island geometry use the top-right corner when that setting is selected. Double-clicking the revealed robot resumes the current board context. The standalone guide and App Review notes must explain this. Reopening the running app restores its current route and visible board. Native About, Hide, Show All, Settings and Quit commands are available when DaBin is active.

## Persistence invariants

- Schema 9 adds optional task planning (workday, deadline, priority, effort, order, checklist and recurrence lineage). Schema 8 retains task attachments. Schema 7 adds optional pin, project and deletion-date fields; old records decode unpinned, unfiled and active. Schema 6 added the local-content-index fields; schemas 1–5 decode with an empty pending index. The Core Data model remains stable because each record stores one versioned JSON payload.
- Converting an existing capture to a task persists a separate `convertedToTask` flag introduced in schema 5; `kindRaw` remains the original content type. Older records still decode without that flag. `isTask` combines legacy task records and converted content, so previews and clipboard payloads retain the original content while filters, reminders and carryover use task status. Conversion saves in place, is idempotent and rolls back the flag on metadata failure.
- Task cards are presented individually outside imported batches and automatic-hour summaries. The original action still contributes to its hour's count; summary placement follows its remaining non-task content. Exports retain original receipt grouping and include task status without moving or duplicating receipt dates.
- Receipt date/time and source metadata remain facts about the original capture.
- Automatic records retain their automatic origin and stable action identity. Source-application metadata is best effort and must never be presented as authoritative provenance.
- Imported source files are copied and verified; their external originals are not moved or edited.
- Card copy reads only persisted values and DaBin-managed originals. It never reopens the external source path, and a missing member prevents a grouped action from partially replacing the clipboard.
- Core Data is the authoritative index. Readable folders and thumbnails are managed derivatives or owned copies, not an alternative mutable index.
- A failed import compensates its own work; recoverable interrupted imports retain a journal and verified bytes.
- Removal commits the metadata deletion before removing owned files. A durable intent handles cleanup retries before import recovery. Deleted or stale objects cannot upsert themselves through service saves.
- Preview work is quiesced before capture removal. Callback cancellation, completion and timeout produce one result; late results cannot restore a removed record or update capture metadata after session shutdown.
- Content indexing is separate from preview state and link-preview consent. It reads only DaBin-managed immutable originals, runs with one local worker, retains a prior index if rebuilding fails, and is quiesced before removal. Images use Vision, PDFs use native text plus per-page OCR fallback, and supported text documents are decoded locally. Empty successful recognition is terminal; explicit page, byte and character limits bound work.
- Parallel cache-folder creation tolerates a validated existing directory, while rejecting symlinks and obstructing files.
- Minimize is a persisted presentation preference. It does not discard content, comments, reminders, task state or searchability.
- Notification work rechecks the current capture/revision after each suspension, so stale scheduling cannot override a newer edit/removal.

## Optional Auto Capture boundary

Auto Capture is a separate, explicit intake mode and defaults off. Constructing its settings or starting the normal app does not by itself read the clipboard or request folder access. Enabling it requires a user action. The screenshot path is selected through the system folder picker; its security-scoped bookmark is stored locally and resolved only for that user-authorized location.

The clipboard observer establishes the current pasteboard change count as its baseline after Auto Capture is enabled or resumed. It processes only later changes, rather than importing content already present when monitoring began. Turning Auto Capture off or pausing it tears down clipboard polling and screenshot-folder observation immediately. Restarting monitoring takes a fresh baseline. Normal explicit paste and drop continue to use `InputService` independently of this mode.

Folder observation records the existing image files as a baseline, then covers new screenshot images written to the selected save location. macOS exposes no public notification that identifies every screenshot produced by the system, so DaBin does not claim system-wide screenshot detection. A screenshot whose destination is the clipboard can be considered through the post-enable clipboard-change path; a screenshot saved outside the chosen folder is not supplied by the folder observer. Neither path requires screen recording or captures the live screen itself.

Attribution to a source application is a best-effort sample of available macOS application state near receipt time. It can be missing or imprecise and is never treated as verified file provenance. DaBin's own bundle identifier and a default set of password-manager bundle identifiers are excluded. The settings model can retain an explicit exclusion set, but attribution limits make exclusions an additional guard rather than a promise to identify every content origin. Pause or disable Auto Capture for work that should not be observed.

For single images, a bounded normalized-pixel fingerprint suppresses an opposite-channel repeat that arrives through the screenshot folder and clipboard within the short duplicate interval. A later copy or a repeat through the same channel remains a distinct user action. Successfully saved automatic records remain local, use the normal transactional archive, and never initiate website-preview fetching. Preview eligibility for manually saved links is a separate preference.

Automatic records keep a stable action identifier so one user action that yields several records stays together. Daily collapses a busy civil-clock hour into an expandable summary once the hour reaches four successful automatic actions; the immutable receipt day, local hour and UTC offset define that group. Filtering affects visible members without changing whether the original hour qualifies.

After a successful automatic save, a reused nonactivating, click-through robot panel appears briefly on the hardware primary display. A shuffled bag selects among ten eating reactions, retaining the previous three choices across shuffle boundaries so they cannot repeat. One value timeline sequences anticipation, climb, eating, reaction and complete retreat in about 1.8–2.6 seconds. Saves arriving while the token remains visible update its exact `×N` action count; later arrivals form one bounded follow-up aggregate. Board and manual-interaction suspension are independent and must both clear before feedback resumes. A real camera-island rectangle sets the built-in placement and visual edge; external-primary placement remains top-right. Reduce Motion replaces the full performance with a short static peek, success check and opacity fade. The panel is confirmation only, contains no sound, never becomes an input surface, uses the public macOS window-sharing exclusion, and is presented only after persistence succeeds.

## Connected work and recovery

`WorkspaceStore` owns one atomic `Workspace.json` sidecar: per-project scratchpads, shelf references, snippet names, processed Inbox IDs, selected project and per-project selection. Capture metadata remains in Core Data; a shelf entry never duplicates or owns the external source file. Failed scratchpad writes retain pending text and expose a retry. Workspace backup restore is additive and rejects conflicting authored notes before committing.

`TaskPlanning` separates an immutable receipt from the chosen workday, deadline and notification reminder. Completion can atomically create one linked next occurrence. The cadence anchor prevents monthly drift; completion never generates an unbounded missed-period backlog. Attachments remain on the original occurrence and are reachable through the previous-occurrence link.

`DraftArchive` stores composer and detail edits in private `Drafts.json`, separately from saved capture records. Invalid recovery files are preserved instead of overwritten. Quit flushes recovery data and prompts only when unsaved content cannot be persisted.

`AppState` preserves search return route, filter, detail/draft identity and temporary-page return destinations. Bounded route-chain checks prevent Back loops when search, settings and composers are nested. The native controller keeps expanded geometry separate from the saved compact frame; content remains mounted when occluded while decorative animation stops.

Production startup loads authoritative metadata before beginning readable-folder repair and preview/index preparation in small cancellable batches. New saves still commit their changed records immediately. `CaptureRepository` fetches existing metadata IDs in bounded batches before upserting, avoiding repeated scans of pending objects during large imports.

`ClipboardRetentionService` is opt-in and uses recoverable trash. Tasks, reminders, organized/pinned captures, named snippets, shelf items and explicitly kept Inbox items are protected. Eligibility is rechecked after asynchronous preview/index cancellation. Default Never does not silently clear existing settings errors.

## Native interface

The board shell selects a feature screen. Inbox collects unfiled/unprocessed captures; Today plans deliberate work independently of deadlines and reminders; Workspace shares optional project context across Library, Clipboard, Shelf and Notes. Activity retains the daily receipt feed and weekly history with its previous task-carryover behavior. Detail, note/task editors, Search, Recently Deleted and Settings have separate files.

`BoardView` owns labeled main tabs, persistent search, a truthful Add menu and a More menu. Day/Week controls and the calendar remain within the timeline. General search resets to the complete archive and clears stale type filters. Matching records appear by default; nearby same-day context is an explicit toggle. Global shortcuts register only two specific Carbon hotkeys, report conflicts, and unregister during shutdown; they do not monitor general typing. Quiet mode suppresses automatic confirmations and idle peeks and bypasses the opening transformation.

Clipboard and screenshot capture have independent preferences and generation guards. The shared Pause stops both selected sources. Missing screenshot permission does not stop clipboard monitoring; toggling one source does not cancel the other's pending work. Legacy combined preferences migrate to both sources without changing the user's prior enabled state.

User removal moves a capture to Recently Deleted and cancels reminders while retaining metadata and owned files. Trash/restore replace canonical objects so stale service callbacks cannot mutate a returned capture. Explicit permanent deletion retains the established journaled cleanup. Backup serializes active and trashed snapshots plus their owned files into a checksummed `.dabinbackup` directory, excluding preferences and the live database. Restore validates all metadata, file paths and hashes before copying, rejects conflicting records/files, and commits metadata in one transaction. Rollback removes only files whose containment, identity and hash still match the restore's own writes; modified paths are preserved and reported.

Day and Week export documents are built directly from the complete store by immutable receipt day, independent of the visible filter and task carryover presentation. A week is a fixed seven-date local-calendar range ending on the displayed range date; it neither duplicates carried tasks nor imports actions from another stored day. Each copy/download pair uses the same document bytes. Clipboard, save-panel and file-writing effects remain behind an injected action controller so tests use private or in-memory destinations.

Panel geometry is expressed in macOS points. Daily/Week transitions respect the selected screen and keep the compact header anchored. Image/document previews fit their bounds; PDF pages use the native PDFKit view. Visual QA records logical size and actual backing pixels, including real 2× Retina rendering; it does not upscale a 1× screenshot and call it Retina.

Camera-island detection is geometric and local. `CornerGeometry` combines `NSScreen.safeAreaInsets` with `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`; a valid top inset and the gap between the two auxiliary regions identify the camera island. The robot is centered below that gap and enters from the top. If a screen does not expose that geometry, the same preference resolves to the top-right corner trigger on that screen.

The transient robot is a native AppKit/Core Animation character, separate from capture storage and window ownership. `RobotMotionState` reduces reveal, hover, accepted-drag, saving and result events with a fixed priority. `RobotCharacterView` applies independent transforms to the body, face, eyes, lid, arms, intake and shadow, and cancels ambient animation when hidden. When macOS Reduce Motion is enabled, expressions update without positional, scaling, rotating, repeated or keyframed movement.

## Build and release

The local build emits an ARM64 `.app` with all runtime resources inside `Contents/Resources`. Debug symbols stay outside the application bundle. The optimized local Release build remains ad-hoc signed until a developer identity is supplied; optimization and local signature validity do not establish App Store distribution readiness.

The shared inventory feeds build, tests and the generated Xcode project. QA retains source/configuration fingerprints, per-suite logs and explicit failure/timeout results. See `QA_RESULTS.md` for the exact tested revision and environment and `APP_STORE_READINESS.md` for distribution gates.

Minimum deployment target is macOS14. Runtime coverage on older supported macOS releases, App Store signing, full Xcode archive validation and Apple review must be completed separately; the local machine runs macOS26.6.2. There is no claim of Intel support.


## Robot lifecycle and application frame

`RobotLifecycle` is a value reducer with generation-tagged transitions. Capture
phases, opening, closing, display changes and interruption have explicit endpoints.
An open request wins over a capture or a pending close. Old callbacks cannot
complete a newer transition. `CornerController` coordinates the interactive robot,
app panel and capture presenter; shutdown cancels immediately.

`AutoCaptureRobotCelebration` holds the ten-style shuffled deck, recent-three
exclusion, timing, generic token paths and Reduce Motion sequence.
`RobotCharacterView` renders those definitions with native vector CALayers.
`AutoCaptureRobotPresenter` is a nonactivating, click-through panel on the primary
display. It uses bounded counters rather than a capture-object queue and buffers
feedback during an open app view. No captured content enters these layers.

`RobotAppFrameView` wraps the existing `DailyCaptureHostingView`. Reserved chrome
adds 20 points of width and 50 of height while leaving the established content
width unchanged. During transformation the native panel temporarily covers both
source and destination; the real content stays mounted at its final layout size.
GPU transforms, reveal masks and opacity provide the transition, after which the
normal panel frame is restored. Header drag, paste/drop, filters and previews keep
the same hosting view and state. The controller's existing 10 Hz pointer tick feeds
clamped, eased gaze only while the board is visible; no new continuous render loop
is started. Reduce Motion disables gaze/blink motion and uses a short fade.

The screenshot monitor waits for a stable local file and successful archive save
before asking for feedback. Native panels use `sharingType = .none`, but that flag
is not a universal exclusion contract for all macOS screenshot/recording APIs.
DaBin does not initiate the user's system screenshot and has no public signal that
can hide an already visible robot before every external screenshot. Hardware notch
geometry uses safe-area and auxiliary menu-bar regions rather than device names.
