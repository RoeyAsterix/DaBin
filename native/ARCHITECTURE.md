# DaBin native application architecture

DaBin is a self-contained Apple Silicon macOS application. It uses Swift, AppKit and SwiftUI with Apple's system frameworks. There is no browser runtime, local web server, JavaScript bridge, companion process, package download or remote backend required to capture and browse content.

## Boundaries

| Layer | Responsibility | Main files |
| --- | --- | --- |
| Entry and macOS lifecycle | Start the application, respond to reopen/quit, present native quit decisions | `DaBinMain.swift`, `AppDelegate.swift` |
| Composition | Own one archive, services, preferences, state and panel controller for the session; start once and shut down explicitly | `ApplicationCoordinator.swift` |
| Native commands | Standard macOS About/Hide/Quit and app commands; responder-chain editing | `ApplicationMenu.swift` |
| Desktop integration | Per-display reveal targets, camera-island geometry, robot character and motion state, paste/drop destinations, keyboard focus, panel placement, automatic-capture reaction rotation and animations | `CornerController.swift`, `RobotView.swift`, `RobotCharacterView.swift`, `RobotMotion.swift`, `AutoCaptureRobotCelebration.swift`, `AutoCaptureRobotPresenter.swift`, `DailyCaptureView.swift`, `WindowDragHandle.swift` |
| Presentation | Small SwiftUI screens, compact timeline header, scoped Weekly Search and export action popovers, hourly automatic-capture summaries and shared visual components; no database construction | `BoardView.swift`, `WeeklyScopeActions.swift`, `DayExportUI.swift`, `HourlyCaptureFeed.swift`, `HourlyCaptureCard.swift`, feature screen files, shared capture components |
| State and domain | Navigation, drafts, chronological membership, filters, task carryover, source facts, selected-day and fixed-week search context, and deterministic day/week export text | `AppState.swift`, `Domain.swift`, `DayExport.swift` |
| Capture intake | Read only explicit paste/drop transfers; preserve receipt time; coordinate promised files and partial failures | `InputService.swift` |
| Optional automatic intake | Gate opt-in clipboard and screenshot-folder monitoring; retain the user-selected folder grant; apply source exclusions and duplicate suppression; stop promptly on pause, disable and shutdown | `AutoCaptureService.swift`, `ScreenshotFolderMonitor.swift`, `AutoCaptureFingerprint.swift`, `AutoCaptureSettings.swift` |
| Persistence | Transactional metadata, owned original copies, readable dated archive and interrupted-operation recovery | `CaptureStore.swift`, `CaptureRepository.swift`, `DailyArchive.swift`, `OriginalFileStorage.swift`, `CaptureRemoval.swift` |
| Disposable previews | Bounded parallel local previews, optional website requests, cancellation/timeout bridging, cache regeneration | `PreviewService.swift`, `PreviewRequest.swift` |
| Reminders | Serialized scheduling, revision checks, permission feedback and wake/activation reconciliation | `ReminderService.swift`, `ReminderLifecycle.swift` |
| Preferences and policy | Shared local theme, board placement, robot-home, previews and Auto Capture settings; accessible bundled privacy information | `ThemeSettings.swift`, `RobotPlacementSettings.swift`, `AutoCaptureSettings.swift`, `PrivacyInformation.swift`, `Resources/` |

The Xcode navigator groups these boundaries. Sources remain in one flat directory so the portable build and Xcode inventory use the same files.

## Ownership and shutdown

`ApplicationCoordinator` constructs all production dependencies and passes them to the desktop controller and views. Tests inject temporary storage, isolated preferences, fake notification clients, private event centers and synthetic pointer positions.

Startup is idempotent. Shutdown removes the pointer and animation timers, local keyboard monitor, desktop notifications and view callbacks. It detaches native hosting views before closing panels so SwiftUI state can be released, stops Auto Capture's clipboard and folder observers, stops new lifecycle reconciliations, and cancels queued/running preview work. A reconciliation already underway may finish; an already-started disposable thumbnail write may also finish. A stopped controller rejects stale reveal requests. Saved system reminders survive normal quit; deleting a capture separately cancels its reminder. The app does not install a background helper or launch-at-login service, so Auto Capture operates only while DaBin is running.

The first launch remains quiet: screen corners are the default reveal target, and a setting can move the robot below a compatible built-in camera island. Displays without camera-island geometry use their corners even when that setting is selected. Double-clicking the revealed robot opens Daily. The standalone guide and App Review notes must explain this. Reopening the running app opens Daily. Native About, Hide, Show All, Settings and Quit commands are available when DaBin is active.

## Persistence invariants

- Receipt date/time and source metadata remain facts about the original capture.
- Automatic records retain their automatic origin and stable action identity. Source-application metadata is best effort and must never be presented as authoritative provenance.
- Imported source files are copied and verified; their external originals are not moved or edited.
- Core Data is the authoritative index. Readable folders and thumbnails are managed derivatives or owned copies, not an alternative mutable index.
- A failed import compensates its own work; recoverable interrupted imports retain a journal and verified bytes.
- Removal commits the metadata deletion before removing owned files. A durable intent handles cleanup retries before import recovery. Deleted or stale objects cannot upsert themselves through service saves.
- Preview work is quiesced before capture removal. Callback cancellation, completion and timeout produce one result; late results cannot restore a removed record or update capture metadata after session shutdown.
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

After a successful automatic save, a reused nonactivating, click-through robot panel appears briefly on the hardware primary display. A shuffled bag selects among twelve celebrations, retaining the previous three choices across shuffle boundaries so they cannot repeat. One value timeline sequences anticipation, entrance, reaction and complete retreat in about 1.8–2.6 seconds. Later saves during that sequence update a single `×N` badge without creating another panel or restarting the robot. A real camera-island rectangle sets the built-in placement and visual edge; external-primary placement remains top-right. Reduce Motion replaces the full performance with a short static peek, success check and opacity fade. The panel is confirmation only, contains no sound, never becomes an input surface, uses the public macOS window-sharing exclusion, and is presented only after persistence succeeds.

## Native interface

The board shell selects a feature screen. Daily, Week, Search, capture cards, Detail, task editing, Reminders and Settings have separate files. Shared formatting, colors and controls keep typography, hierarchy and actions consistent.

Daily and Week share one fixed three-row header owned by `BoardView`: navigation, primary actions and type filters. This keeps their center axes aligned and prevents the feature screens from accepting surplus vertical layout space. The neutral window-close control stays outside the colored action row. In Weekly, the Search action owns an anchored scope popover with an explicit date from the displayed seven-day range plus a full-range choice. Search scope is applied before the established same-day neighbor expansion and retains the active content filter.

Day and Week export documents are built directly from the complete store by immutable receipt day, independent of the visible filter and task carryover presentation. A week is a fixed seven-date local-calendar range ending on the displayed range date; it neither duplicates carried tasks nor imports actions from another stored day. Each copy/download pair uses the same document bytes. Clipboard, save-panel and file-writing effects remain behind an injected action controller so tests use private or in-memory destinations.

Panel geometry is expressed in macOS points. Daily/Week transitions respect the selected screen and keep the compact header anchored. Image/document previews fit their bounds; PDF pages use the native PDFKit view. Visual QA records logical size and actual backing pixels, including real 2× Retina rendering; it does not upscale a 1× screenshot and call it Retina.

Camera-island detection is geometric and local. `CornerGeometry` combines `NSScreen.safeAreaInsets` with `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`; a valid top inset and the gap between the two auxiliary regions identify the camera island. The robot is centered below that gap and enters from the top. If a screen does not expose that geometry, the same preference resolves to the existing corner trigger on that screen.

The transient robot is a native AppKit/Core Animation character, separate from capture storage and window ownership. `RobotMotionState` reduces reveal, hover, accepted-drag, saving and result events with a fixed priority. `RobotCharacterView` applies independent transforms to the body, face, eyes, lid, arms, intake and shadow, and cancels ambient animation when hidden. When macOS Reduce Motion is enabled, expressions update without positional, scaling, rotating, repeated or keyframed movement.

## Build and release

The local build emits an ARM64 `.app` with all runtime resources inside `Contents/Resources`. Debug symbols stay outside the application bundle. The optimized local Release build remains ad-hoc signed until a developer identity is supplied; optimization and local signature validity do not establish App Store distribution readiness.

The shared inventory feeds build, tests and the generated Xcode project. QA retains source/configuration fingerprints, per-suite logs and explicit failure/timeout results. See `QA_RESULTS.md` for the exact tested revision and environment and `APP_STORE_READINESS.md` for distribution gates.

Minimum deployment target is macOS14. Runtime coverage on older supported macOS releases, App Store signing, full Xcode archive validation and Apple review must be completed separately; the local machine runs macOS26.6.2. There is no claim of Intel support.
