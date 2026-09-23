# DaBin native application architecture

DaBin is a self-contained Apple Silicon macOS application. It uses Swift, AppKit and SwiftUI with Apple's system frameworks. There is no browser runtime, local web server, JavaScript bridge, companion process, package download or remote backend required to capture and browse content.

## Boundaries

| Layer | Responsibility | Main files |
| --- | --- | --- |
| Entry and macOS lifecycle | Start the application, respond to reopen/quit, present native quit decisions | `DaBinMain.swift`, `AppDelegate.swift` |
| Composition | Own one archive, services, preferences, state and panel controller for the session; start once and shut down explicitly | `ApplicationCoordinator.swift` |
| Native commands | Standard macOS About/Hide/Quit and app commands; responder-chain editing | `ApplicationMenu.swift` |
| Desktop integration | Corner reveal, robot, paste/drop destinations, keyboard focus, panel placement and animations | `CornerController.swift`, `RobotView.swift`, `DailyCaptureView.swift`, `WindowDragHandle.swift` |
| Presentation | Small SwiftUI screens and shared visual components; no database construction | `BoardView.swift`, feature screen files, shared capture components |
| State and domain | Navigation, drafts, chronological membership, filters, task carryover, source facts and search context | `AppState.swift`, `Domain.swift` |
| Capture intake | Read only explicit paste/drop transfers; preserve receipt time; coordinate promised files and partial failures | `InputService.swift` |
| Persistence | Transactional metadata, owned original copies, readable dated archive and interrupted-operation recovery | `CaptureStore.swift`, `CaptureRepository.swift`, `DailyArchive.swift`, `OriginalFileStorage.swift`, `CaptureRemoval.swift` |
| Disposable previews | Bounded parallel local previews, optional website requests, cancellation/timeout bridging, cache regeneration | `PreviewService.swift`, `PreviewRequest.swift` |
| Reminders | Serialized scheduling, revision checks, permission feedback and wake/activation reconciliation | `ReminderService.swift`, `ReminderLifecycle.swift` |
| Preferences and policy | Shared local theme/placement/preview settings, accessible bundled privacy information | `ThemeSettings.swift`, `PrivacyInformation.swift`, `Resources/` |

The Xcode navigator groups these boundaries. Sources remain in one flat directory so the portable build and Xcode inventory use the same files.

## Ownership and shutdown

`ApplicationCoordinator` constructs all production dependencies and passes them to the desktop controller and views. Tests inject temporary storage, isolated preferences, fake notification clients, private event centers and synthetic pointer positions.

Startup is idempotent. Shutdown removes the pointer and animation timers, local keyboard monitor, desktop notifications and view callbacks. It detaches native hosting views before closing panels so SwiftUI state can be released, stops new lifecycle reconciliations, and cancels queued/running preview work. A reconciliation already underway may finish; an already-started disposable thumbnail write may also finish. A stopped controller rejects stale reveal requests. Saved system reminders survive normal quit; deleting a capture separately cancels its reminder. The app does not install a background helper or launch-at-login service.

The first launch remains quiet to preserve the corner-only interaction: reach a corner to reveal the robot, then double-click it for Daily. The standalone guide and App Review notes must explain this. Reopening the running app opens Daily. Native About, Hide, Show All, Settings and Quit commands are available when DaBin is active.

## Persistence invariants

- Receipt date/time and source metadata remain facts about the original capture.
- Imported source files are copied and verified; their external originals are not moved or edited.
- Core Data is the authoritative index. Readable folders and thumbnails are managed derivatives or owned copies, not an alternative mutable index.
- A failed import compensates its own work; recoverable interrupted imports retain a journal and verified bytes.
- Removal commits the metadata deletion before removing owned files. A durable intent handles cleanup retries before import recovery. Deleted or stale objects cannot upsert themselves through service saves.
- Preview work is quiesced before capture removal. Callback cancellation, completion and timeout produce one result; late results cannot restore a removed record or update capture metadata after session shutdown.
- Parallel cache-folder creation tolerates a validated existing directory, while rejecting symlinks and obstructing files.
- Minimize is a persisted presentation preference. It does not discard content, comments, reminders, task state or searchability.
- Notification work rechecks the current capture/revision after each suspension, so stale scheduling cannot override a newer edit/removal.

## Native interface

The board shell selects a feature screen. Daily, Week, Search, capture cards, Detail, task editing, Reminders and Settings have separate files. Shared formatting, colors and controls keep typography, hierarchy and actions consistent.

Panel geometry is expressed in macOS points. Daily/Week transitions respect the selected screen and keep the compact header anchored. Image/document previews fit their bounds; PDF pages use the native PDFKit view. Visual QA records logical size and actual backing pixels, including real 2× Retina rendering; it does not upscale a 1× screenshot and call it Retina.

## Build and release

The local build emits an ARM64 `.app` with all runtime resources inside `Contents/Resources`. Debug symbols stay outside the application bundle. The optimized local Release build remains ad-hoc signed until a developer identity is supplied; optimization and local signature validity do not establish App Store distribution readiness.

The shared inventory feeds build, tests and the generated Xcode project. QA retains source/configuration fingerprints, per-suite logs and explicit failure/timeout results. See `QA_RESULTS.md` for the exact tested revision and environment and `APP_STORE_READINESS.md` for distribution gates.

Minimum deployment target is macOS14. Runtime coverage on older supported macOS releases, App Store signing, full Xcode archive validation and Apple review must be completed separately; the local machine runs macOS26.6.2. There is no claim of Intel support.
