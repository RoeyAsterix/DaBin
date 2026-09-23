# Implementation notes

## Latest conversation takes precedence

The attached handoff retains an always-visible, movable widget and separate Capture editor. Both are superseded by the user's latest instruction. This app uses zero visible idle UI, any-corner reveal, direct robot paste/drop, digest, and retreat. There is no move handle or separate capture view. Single click only focuses the robot; there is therefore no delayed single-click composer or double-click flash.

The explicitly opened board remains usable until dismissed. It is one native panel switching among Daily, Week, Search, Detail, Reminders and Settings. Compact views are 380 points wide with height following content, capped at 500; an empty Daily is 290 points. Week expands to at most 1440 × 560 points within the usable display. The transient robot window is 72 × 88 points, using the supplied SVG unchanged. The background outside the native surfaces is transparent. No sidebar or simulated desktop exists.

The active corner trigger is 9 logical points along each edge, polled every 100 ms with tolerance in common run-loop modes (including drag tracking). A corridor connects the physical corner to the robot inside the usable screen frame. It permits slow travel across Dock/menu-bar insets. Exit grace is 0.8 seconds; saving, drag interaction and digest feedback keep the target available. One robot is shown at the active corner; it does not duplicate across displays. The panel uses ordinary floating level and never creates a screen-sized input overlay.

No persistent menu-bar item was added, to honor complete hiding at rest. Reopening DaBin, its active-app menu, the focused robot's context menu, and keyboard actions provide recovery. A system-wide hotkey is not registered. OS Hot Corners may activate at the same corners; this app does not change system settings.

## Update 0.1.19

Daily's Today control now calls `showCurrentWeek()`, which explicitly opens the weekly route and selects the current seven-day range regardless of capture count or filter. The weekly control reads This Week and restores that current range when browsing history. The centered Daily date still opens a week ending on the selected day; a weekly day heading and Back return to Daily.

Weekly day columns are always rendered, including empty archives and empty task/type filters. Their entrance keeps its directional slide but no longer starts at zero opacity; content visibility does not depend on an appearance animation completing. The seven-day structure and per-day empty labels remain available throughout layout and resizing.

## Update 0.1.18

Daily is now a second capture destination. `DailyCaptureHostingView` registers the shared native pasteboard types and consumes accepted copy-only drops synchronously through the existing `InputService`. Normal child hit testing is preserved for rows, buttons, previews and the draggable header. A temporary theme-colored outline marks accepted drags; no permanent drop area or extra window space is added.

`DailyCapturePanel` routes Control-V, Command-V and Edit → Paste through a single deduplicated capture path. Only the Daily route captures, and an editable native text responder takes priority. Search, new-task and comment editors retain their own paste behavior. Repeats and duplicate responder dispatches do not produce extra records. Pasteboard payloads are read only for an explicit paste or accepted drop.

An optional per-batch `InputService` completion callback reveals successful Daily-origin captures on their receipt date with All selected. Failure leaves the selected date/filter unchanged. Navigation during an asynchronous import takes precedence; the completion never changes a later route/date/filter or reopens a dismissed window. Late promised-file receipts preserve the original callback and capture date. Robot capture and the shared persistence, source provenance, preview and feedback pipeline are retained.

## Update 0.1.17

Daily and Search keep their current top edge and width during same-view content resizing. A filter change animates the bottom edge with a 0.38-second eased native panel transition. Available height is capped below the header at the display's bottom edge; existing content scrolling handles overflow instead of moving the header upward. Initial corner placement and normal route navigation still use their existing layout rules.

Rapid filter changes retarget from the displayed frame, and preview/status changes during that transition continue smoothly. Identical pending targets preserve the current timer, including weekly unfolding. Reduce Motion skips interpolation; dragging, dismissal and display changes cancel it. Programmatic resizing does not write a user placement preference. Weekly unfolding retains its 0.28-second timing.

## Update 0.1.16

Settings adds six accent presets and the native custom color picker. A dedicated `ThemeSettings` observable object normalizes an opaque sRGB choice and persists it under `DaBin.themeColor.v1` in local preferences. Invalid values fall back to Purple without rewriting preferences. Changing a theme has no archive or capture writes.

The board passes its adaptive accent through SwiftUI's environment and tint. Filters, dates, buttons, source-copy actions, task frames, the DaBin wordmark/emblem and PDF navigation update immediately. The original corner/empty-state purple robot remains the mascot; red Task and green Completed retain their status meanings. Light/dark accent variants maintain contrast against the board's neutral surfaces; selected color swatches retain the chosen source color. Theme render fixtures use an isolated preference suite.

## Update 0.1.15

Images and cached previews share a bounded aspect-fit view in Daily, Week, Search and Detail. Both dimensions are constrained before scaling, and a small inset keeps image edges inside the rounded preview. Detail image previews remain 230 points high; documents remain 190 points. The surrounding widget and board sizes do not change.

PDF previews now fit a whole page instead of using PDFKit's continuous-mode fit-to-width behavior. The dedicated `FittedPDFPreview` component retains multi-page navigation. Document/AI/file previews use the existing local Quick Look thumbnail cache for proportional containment, with Open original still available for the complete file. No original content or archive metadata is resized or rewritten.

## Update 0.1.14

Dragging toward a screen corner can reveal the robot while Daily or Week remains open. Moving the board's own header does not trigger this path. Ordinary hover retains the previous minimal-presence behavior. The robot remains visible through input completion and digest feedback, and retreats after the pointer leaves even when the board is still open.

The entire robot view owns hit testing; its artwork and feedback badge cannot intercept drops. Destination callbacks validate advertised readable types and require a copy operation before accepting a transfer. Unsupported or move-only drags are rejected, and exit/end/cancel paths clear drag state. The destination is never ordered out to release hover focus during an active accepted drag. File originals remain untouched; ordinary text without explicit source metadata still reports no source path.

The open board's existing top-left is retained in memory before changing the robot's corner/display, preventing an incoming capture from moving an initially unplaced Daily board. This does not rewrite the user's placement preference. HTML and generic data registrations expose the existing original-byte import fallback; HTML-only content remains a local file without loading web resources, while browser selections offering plain text capture that text once.

## Update 0.1.13

Daily's centered date opens a rolling seven-day board ending on the selected day. Week provides seven chronological columns, independent vertical scrolling, a range calendar, seven-day navigation and the same type filters. Clicking a day collapses to Daily; capture details return to the original week with Back. Cards show capture titles/previews, current task status, comments and reminders. The columns use the same task carryover/reminder-day rules as Daily; they are not an inferred audit history of previous edits or completion states.

Native window geometry chooses the side with more room, anchors the appropriate edge, and clamps the expanded frame to the connected screen. A 0.28-second eased frame transition is paired with a subtle directional column reveal. Reduce Motion disables both. Compact placement remains separate from programmatic expansion, survives detail/return and rapid reversal, and maps weekly dragging back to a sensible compact anchor. Weekly columns have a 170-point minimum width; small screens scroll horizontally instead of compressing text.

Date grouping uses calendar-day arithmetic across midnight, months, years and DST. Weekly projections never mutate capture dates, duplicate records, relocate files or reschedule reminders. An open current week advances after midnight/wake, while historical browsing stays put.

## Update 0.1.12

Capture rows put the capture type below the timestamp. Tasks show the red/green status toggle in that position, with no duplicate type label or bottom toggle. Their action area remains separate from the button that opens the capture. Row titles increase exactly 15% (14 → 16.1 points; featured titles 17 → 19.55 points), while timestamps retain their existing 12.65-point size. Original creation labels, purple frames, comments and reminders remain available.

The purple checkmark adds a Tasks filter to Daily and Search. Daily includes only explicit tasks, both open and completed when otherwise eligible for the selected date; reminder-date and carryover rules still apply. Search restricts matches to tasks and preserves the established immediate-neighbor context, which may contain another capture type.

## Update 0.1.11

A task's reminder replaces automatic daily carryover. An unfinished task with a reminder appears at the top only on the reminder's local calendar day, including when created that same day. It is not carried onto earlier or overdue days. Original-day records remain in their normal chronology when not highlighted, and tasks without reminders continue to carry forward. Completing disables highlighting; editing or clearing the reminder immediately changes which days include the task. The selected Daily date and the reminder label use the current local time zone consistently.

`AppState.isTaskAtTop` is the shared membership, ordering and purple-frame rule. The existing record, original creation date, archive location and notification schedule are preserved; no duplicate records or rollover writes are introduced.

## Update 0.1.10

A compact custom DaBin logo replaces the Daily header title. Its purple robot-bin emblem and wordmark are native vectors/text, transparent outside their shapes, with light/dark styling. The header retains its existing height and native drag surface; toolbar controls and other route titles retain their positions. The logo is exposed as a single accessible DaBin heading.

## Update 0.1.9

Daily projects earlier unfinished explicit tasks above the selected day's records, preserving newest-first order within both groups. Carried rows use their original creation date and a one-point purple rounded outline; type filters still apply. Completion removes the task from carryover while retaining it on its original day, and reopening resumes carryover. Ordinary captures and reminders do not become tasks automatically.

Carryover is a view of the existing record: no duplicate capture, archive move, receipt-date change or reminder rescheduling occurs at rollover. Search retains the original chronological context. Historical days show the task's current completion state; there is no inferred completion history. Calendar-day, activation, wake and time-zone events refresh Today without changing an intentionally browsed older date.

## Update 0.1.8

The title and blank header area are a native AppKit drag surface; header buttons retain their normal interactions. Mouse events move the borderless panel using screen coordinates. The window controller pauses layout during the gesture, remembers its top-left point locally, and preserves that anchor during route/height changes and relaunch. Saved coordinates are validated and clamped to a connected display if the screen arrangement changes. The robot continues to reveal at screen corners.

203 native window checks passed, including actual header-handler event dispatch, live resizing during route changes, persistence, two-display placement and invalid/offscreen preference recovery. The installed app received a real CUA header drag and saved its new position.

## Update 0.1.7

Capture-row time labels increased from 11 to 12.65 points (+15%) across Daily, Search and Reminders. The existing native rendering suite produced 38 renders; inspected timestamp rows remain aligned without clipping.

## Update 0.1.6 — QA repairs

Preview and reminder services now persist only changed captures. They leave unrelated metadata and readable archive files untouched; full saves and startup archive synchronization remain available. Unchanged preview states perform no write. Failed notification-state persistence restores the previous in-memory state so reconciliation can retry.

`ReminderLifecycle` reconciles on launch, activation and wake without requesting notification permission. Events are coalesced to avoid a scheduling backlog. Startup passes all captures to the preview service, allowing deleted local thumbnail caches to regenerate while keeping intact previews.

Board messages carry explicit success, warning or error severity. Capture failures and partial imports have appropriate icons, task reminder failures remain visible after returning to Daily, and assistive announcements identify partial failures. Reminder feedback belongs to the capture and current revision; clear/completion removes stale notices while preserving unrelated errors. New isolated regression suites cover lifecycle/cache recovery and scoped persistence. Window tests continue through independent assertion failures while retaining a failing exit status.

## Update 0.1.5

Storage is factored into `CaptureRepository` (Core Data transactions and schema validation), `DailyArchive` (stable date paths, safe filesystem access and readable files), `OriginalFileStorage` (import receipt/error types and byte verification), and `CaptureStore` (capture lifecycle and coordination). UI and services call store APIs. Preview reads/writes now use validated owned paths.

Primary attachments live under `Archive/<year>/<number month>/<day weekday month year>/<receipt time - UUID>/Original/`. Metadata and exact text/link records share the capture folder. Paths use immutable captureDay and the stored UTC offset, with Gregorian English names. Core Data remains the canonical searchable index. Generated metadata is synchronized after successful commits; a sidecar failure warns and retries rather than incorrectly rolling back an acknowledged save. All service saves refresh readable metadata too.

Startup recovers old/new import journals before migrating legacy originals. Migration verifies copied bytes and any existing destination before updating the metadata path; the old original stays untouched. Destination conflicts and unknown files are preserved. The source document path remains distinct from managed storage. `DailyArchive` records hashes of owned generated files and backs up externally changed versions to `Local edits/` before replacing them.

Settings exposes the archive in Finder; record details expose their folder. `--organize-archive` is a headless local maintenance mode for use while the app is closed. It creates no fake captures and performs no notification, clipboard or network work.

## Update 0.1.4

Daily’s purple plus opens a compact task form in the same panel (380 × 310 points, or 370 points with reminder controls). Tasks are explicit capture records on their creation day; no assignee, project menu, or extra permanent input area is added. Red Task / green Completed buttons include icons and labels in rows and detail. New-task drafts survive hiding/back navigation and participate in the unsaved-quit guard; explicit Cancel discards the draft.

Task completion is persisted, keeps its original receipt time, and remains reversible. Reminder dates are retained as history while completion suppresses pending/delivered alerts. Reopening resumes future reminders; past dates remain silent. The scheduler invalidates in-flight jobs using the current completion state and reminder revision. Completed tasks remain in Daily/search and leave the active Reminders list.

Capture payload schema 3 adds optional `isCompleted`, defaulting to false for schema 1/2 records. A task and its initial reminder are one metadata transaction; failed writes retain the draft and rollback status changes. Tasks bypass file/link preview generation.

## Update 0.1.3

Hovering over the robot gives its nonactivating panel temporary keyboard focus for Control-V and Command-V. A tracking area and existing pointer polling handle arrival and departure. Leaving releases hover focus using native window ordering. Dragging or holding a mouse button does not acquire hover focus. Existing click-to-focus and keyboard access remain available. Only an explicit paste reads the clipboard; no global keyboard monitor or Accessibility permission is added. Key repeat and duplicate responder routing cannot save a capture twice. Focus release uses window ordering; Apple documents `resignKey()` as an override hook that must not be called directly ([NSWindow documentation](https://developer.apple.com/documentation/appkit/nswindow/resignkey())).

## Update 0.1.2

Daily now lists captures newest first across all type filters, using the original capture time. Equal timestamps retain deterministic UUID ordering. Search retains chronological neighboring context.

## Update 0.1.1

Daily uses purple icon filters with tooltips and accessibility labels, a geometrically centered date, and a 24-point continuous panel radius. The original robot gets a small sleepy face, glances, blinks and sighs in empty Daily states. Its timeline pauses when the panel is hidden or occluded, and Reduce Motion selects a static pose. The normal corner robot remains unchanged.

Capture detail shows the source location separately from the managed original, with a copy action. Actual file-transfer URLs supply the original path. Explicit WebArchive main-resource URLs can supply the origin of copied text or media; text content, HTML links and the frontmost application are never treated as evidence of origin. Ordinary plain-text clipboard content cannot reveal its source document path unless the sender includes it. File promises expose a temporary delivery location, so that location is deliberately excluded. Source metadata is saved at receipt and retained across source deletion and app relaunch.

Capture payload schema 2 adds optional `sourceFilePath` and `sourceURL`; v1 payloads and older recovery journals remain readable. Existing captures are not retroactively assigned guessed paths. Link records can still show their original URL.

## Native architecture

- `DaBinMain.swift`: accessory lifecycle, native menus, safe quit, startup recovery.
- `CornerController.swift` / `RobotView.swift` / `DailyCaptureView.swift`: transparent panels, corner state, focus, robot and Daily drag/paste, preserved vector robot, digest/Reduced Motion.
- `InputService.swift`: one representation per pasteboard item, native URL transfer grants, ordinary files and file promises, aggregate/partial-failure feedback, original intake stamp even on late delivery.
- `Domain.swift`: immutable receipts, versioned snapshots, classification and contextual search.
- `CaptureStore.swift`: capture lifecycle, recovery and migration coordination. `CaptureRepository.swift` owns Core Data transactions; `DailyArchive.swift` owns dated paths/readable records; `OriginalFileStorage.swift` owns import receipts and integrity checks.
- `AppState.swift` / `BoardView.swift`: native views, durable edits, drafts, originals and compact navigation. `CaptureSourceView.swift` renders provenance, and `BoredRobotView.swift` provides the visibility-aware empty state.
- `PreviewService.swift`: bounded native thumbnail jobs, opt-in cancellable LinkPresentation fetching.
- `ReminderService.swift`: serialized revision-aware UserNotifications scheduling and response routing.

## Persistence fallback

Full Xcode is absent, and the installed Command Line Tools SDK does not include the `SwiftDataMacros` compiler plugin. Instead of leaving an unbuildable macro-based project, this implementation uses Apple's Core Data SQLite store with an explicit `DaBinV1` schema and versioned capture payloads. The product model and local-only storage behavior are preserved. Unsupported metadata versions fail clearly; there is no automatic database reset. See `Tests/PERSISTENCE_QA.md` for import and recovery details.

Managed-copy hashes verify the saved bytes and recovery state. No filesystem-wide snapshot of an external file being edited concurrently by its source app is claimed. Ordinary folders, symlinks, aliases and sources exposing no readable transfer data produce clear failures. Delayed promised files keep their original receipt day. Unfinished promise staging may remain in the OS temporary directory if the source never returns a callback; it is never mislabeled as a saved capture.

## Native boundaries

Website previews default off and are separate from successful capture. LPMetadataProvider supplies a title and image/icon when available; the domain is used as supporting metadata because Apple's public metadata API does not expose arbitrary page-description text. Originals always remain available.

Reminders are absolute instants, with the selected timezone retained. The native date picker supplies valid instants and shows the current timezone/offset; there is no custom parser for nonexistent wall-clock times in DST gaps. Changes to capture comments or reminders never alter the receipt date. No background timer impersonates an OS reminder.

Thumbnails are stored under the app's managed `Previews/` directory, relative to the store root. They are disposable and never replace originals. Project/tag suggestions, OCR, accounts, sync, team workflow and launch-at-login are deferred.

## Reference and test provenance

`Handoff/` is extracted unchanged from the user's ZIP. Prototype HTML is reference only; the app does not embed a web view. `Resources/robot.svg` is byte-identical to the handoff robot. Icon raster sizes are local derivatives of that vector. Native views use system fonts and the handoff's light/dark color roles.

`build/qa/screenshots/` contains native NSHostingView renders backed by real isolated persistence. The manifest explicitly labels them as native-view renders, not desktop screenshots. GUI interaction checks used a separately signed `com.dabin.mac.qa` sandbox; fictional items never entered normal DaBin storage.

## Local delivery

The source project and portable ZIP are on Desktop. The executable app is installed at `~/Applications/DaBin.app`, outside Desktop/Documents synchronization. The document provider reattaches a FinderInfo attribute to `.app` directories in synced folders after cleanup, so their later strict codesign checks fail. The personal-Applications copy passed repeated strict verification after installation. Build signing occurs in a local temporary directory; the install script copies without extended attributes and preserves executable permissions. This changes no entitlements or system security settings.
