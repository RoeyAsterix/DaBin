# Implementation notes

## Latest conversation takes precedence

The attached handoff retains an always-visible, movable widget and separate Capture editor. Both are superseded by the user's latest instruction. This app uses zero visible idle UI, a selectable corner or built-in-camera-island reveal target, direct robot paste/drop, digest, and retreat. There is no move handle or separate capture view. Single click only focuses the robot; there is therefore no delayed single-click composer or double-click flash.

The explicitly opened board remains usable until dismissed. It is one native panel switching among Daily, Week, Search, Detail, Reminders and Settings. Compact views are 380 points wide with height following content, capped at 500; an empty Daily is 290 points. Week expands to at most 1440 × 560 points within the usable display. The transient robot window is 72 × 88 points and contains a native AppKit/Core Animation character. The original supplied SVG remains preserved as a handoff resource. The background outside the native surfaces is transparent. No sidebar or simulated desktop exists.

The default corner trigger is 9 logical points along each edge, polled every 100 ms with tolerance in common run-loop modes (including drag tracking). Camera-island mode instead uses a small trigger around the actual top cutout reported by macOS. A corridor connects the active reveal target to the robot inside the usable screen frame and permits slow travel across Dock/menu-bar insets. Exit grace is 0.8 seconds; saving, drag interaction and digest feedback keep the target available. One robot is shown on the active display; it does not duplicate across displays. The panel uses ordinary floating level and never creates a screen-sized input overlay.

No persistent menu-bar item was added, to honor complete hiding at rest. Reopening DaBin, its active-app menu, the focused robot's context menu, and keyboard actions provide recovery. A system-wide hotkey is not registered. OS Hot Corners may activate at the same corners; this app does not change system settings.

## Update 0.3.12

Weekly keeps the compact five-icon action row. Its Search icon now opens `WeeklySearchPopover`, which uses `WeeklyDayPicker` to expose every calendar date in the current seven-day range, including dates whose empty columns are hidden. **Search Day** applies an exact persisted-day scope; **Search Week** applies the complete fixed date set. Scope filtering happens before the established same-day-neighbor expansion, the active content filter still limits hits, and leaving scoped Search returns to Weekly. Daily's existing general Search behavior remains available.

The shared export icon opens the existing Day popover in Daily and `WeeklyExportPopover` in Weekly. Weekly offers **Copy Day**, **Download Day**, **Copy Week** and **Download Week**. `WeekExportDocument` uses seven local Gregorian calendar dates ending on the displayed week-ending date, reads exact persisted capture days, excludes future actions and applies the current-moment cutoff to today. It does not use the visible content filter or duplicate task carryover projections. Its deterministic filename is `DaBin-Week-YYYY-MM-DD-to-YYYY-MM-DD.txt`; the day document retains `DaBin-YYYY-MM-DD.txt`.

Both popovers use native transient presentation, Escape dismissal, keyboard focus and shortcuts, tooltips and accessibility names. Day and week emptiness are evaluated independently. The injected export controller accepts either document through one protocol so each copy/download pair writes identical UTF-8 bytes and reports scope-specific success or failure. Existing Daily export behavior and stored data need no migration.

## Update 0.3.8

Daily and Weekly now share one compact three-row header. The first row keeps the DaBin logo, previous date, selected date, next date and Daily/Weekly control together, while the neutral close control remains independent at the far right. The second row centers Add, Search, Export Day, Notifications and Settings in that order. The third row centers the existing content filters on the same axis. Shared accent icon components give the primary actions and filters matching symbol size, spacing, hover, pressed and focus treatment without changing their behavior. Fixed oversized header spacers were removed, and the navigation row reduces spacing at the 380-point compact width before content can clip.

`DayExportDocument` builds a deterministic plain-text record from the complete archive for the selected calendar date. It intentionally has no visible-filter input, applies a current-moment cutoff only when the selected day is today, groups records by their persisted manual or automatic action boundary, sorts actions chronologically, and includes timestamps, types, available source-application details and textual content. Image-only records use an explicit screenshot or image placeholder when no stored caption or OCR text is available. The document owns the `DaBin-YYYY-MM-DD.txt` name and UTF-8 bytes so Copy Day and Export Text File cannot diverge.

The Export Day icon opens a small native popover beneath the button. Empty days disable both actions and state that there is nothing to export. Copy success shows a brief checkmark and **Day copied.**; file export uses a sandbox-compatible save panel and reports success or failure without treating cancellation as an error. The choices are ordinary action buttons with visible keyboard focus, help and accessibility text. Daily uses Command-1 and Command-2; Weekly keeps those day actions and uses Command-7 and Command-8 for the week actions. These distinct keys remain reliable with the native Edit menu installed. Escape, clicking outside, changing the selected date or leaving the timeline dismisses the popover.

## Update 0.3.7

The Daily and Weekly header menu now uses the outline SF Symbol `gearshape` instead of `ellipsis`. Its 13-point symbol, 30 × 30-point hit area and muted colour match the adjacent task, search and reminder controls. The menu actions are unchanged, while the help and accessibility label now read **Settings and options**.

## Update 0.3.11

Automatic save confirmation now has its own value-only animation policy in `AutoCaptureRobotCelebration.swift`, separate from the interactive paste/drop robot reducer. `AutoCaptureRobotReactionDeck` uses a seeded shuffled bag of twelve reactions and carries its previous-three history across bag boundaries. Each performance fixes the reaction, bounded timing/gaze/entrance variation, display-edge entrance, ordered phases and total duration before any layer animation starts.

`RobotCharacterView` schedules one automatic timeline for anticipation, spring entrance, a reaction-specific success move and complete retreat. The reactions reuse the robot's eyes, arms, lid, intake card and body, with small native vector props for the check, clipboard, flash, stamp and confetti. They do not add sound, image assets or windows. The ordinary reveal, hover, drag, digest, success, partial-success and failure states remain unchanged.

`AutoCaptureRobotPresenter` still owns one nonactivating, click-through, capture-excluded panel. The first success starts one performance; later successes while it is active only update the `×N` badge. A single success relies on the robot's success cue and omits a redundant `×1`. The panel uses the exact camera-island rectangle macOS reports when available, meets its lower edge and centers beneath it. Safe top-center and external top-right fallbacks remain bounded by the usable display.

Reduce Motion is evaluated for each new burst and selects a brief peek, checkmark and fade with no body travel, rotation, squash, spring, particles or ambient task. Dismissal and shutdown cancel the sequence, remove transient layers and order the panel out. The existing `AutoCaptureService.onSaved` boundary remains the sole caller, after complete durable success; failure and partial-failure paths cannot celebrate.

## Update 0.3.6

`CaptureRow` now presents every top-level individual caption as a lightly filled continuous rounded rectangle with a 0.75-point neutral stroke. Carried tasks retain a 1-point theme-colour stroke. Six points of outer vertical spacing keep adjacent frames from touching, and the Daily panel-height estimate includes that spacing.

The same row component covers Daily, Search and Reminders. Rows embedded inside an expanded automatic-hour action omit their own frame because the action container already supplies the rounded card surface. Grouped batches, hourly summaries and Weekly cards retain their existing rounded frames.

## Update 0.3.5

Auto Capture is a separate default-off service composed from `AutoCaptureSettings`, `AutoCaptureService`, `ScreenshotFolderMonitor` and the existing `InputService`. Enabling it first presents a local-storage explanation and asks the user to choose the folder configured as the macOS screenshot destination. The resulting read-only security-scoped bookmark, enabled and paused state, privacy acknowledgement and excluded bundle identifiers live in app preferences. Starting or resuming seeds `NSPasteboard.changeCount` without reading a payload, so existing clipboard contents are never imported.

Clipboard events and authorized-folder additions enter one serialized pipeline with an immutable automatic action ID and receipt metadata. Pause, Off and shutdown advance a generation token, stop the timer and directory source, cancel delayed images, clear queued private pasteboards and reject an in-flight commit before durable metadata is written. Workspace activation also reseeds the counter when leaving an excluded app, closing the normal copy-then-switch interval without loading that clipboard content. DaBin and common password managers start excluded; source attribution remains best effort.

A bounded normalized-pixel digest deduplicates a screenshot that arrives through the folder and clipboard channels within the short comparison interval. Automatic links stay outside the website-preview queue. Durable subsets from a partly failed action still appear in the feed, while only a completely successful action can invoke the confirmation robot.

Automatic action IDs drive fixed local-clock-hour grouping. One to three actions remain ordinary cards; the fourth converts that hour to one stable summary whose count updates as actions arrive. Filtering changes visible members without dissolving the qualifying group. Expansion retains the same outer identity and leaves the Daily scroll binding unchanged; the top-right minus control has the accessibility label `Collapse actions`.

`AutoCaptureRobotPresenter` owns one borderless nonactivating panel. It chooses the hardware primary display, centers below a built-in safe top area or uses the top-right of an external primary display, ignores input, cannot become key or main, joins the current Space without switching it, and uses `NSWindow.SharingType.none` to stay out of screen capture. One burst reuses the panel and increments its action count. Reduce Motion removes character travel and leaves a short fade.

## Update 0.3.4

Release 0.3.4 supersedes 0.3.3. Live update QA showed that `NSWorkspace.OpenConfiguration.arguments` is ignored when the caller is sandboxed, so the verified ZIP path never reached the helper even when a new helper instance was requested. The failure occurred before installation; the existing app and local capture archive were not replaced or modified.

The direct updater now creates a private, permission-restricted, one-use `.dabinupdate` document beside the downloaded ZIP and asks LaunchServices to open that document with the embedded helper. The document contains only its schema version, the same-directory package filename and the expected SHA-256. The helper accepts the file through the native application-open callback, constrains it to the app-owned Updates directory, rejects symbolic links and unexpected keys, checks its owner and permissions, validates the package name, location and checksum, and removes the handoff after consumption. Existing independent ZIP, layout, ARM64, signature, confirmation, backup, replacement and rollback checks remain in place.

Direct command-line package arguments remain available for build and package QA. The Mac App Store build still omits the direct downloader and helper.

## Current Daily/Weekly navigation

The date row uses one compact native segmented control labeled **Daily** and **Weekly**. Daily → Weekly opens the seven-day range ending on `selectedDay`. Weekly → Daily changes only the route, so it returns to the same selected day without resetting the active type filter, Daily scroll position or unsaved drafts. Re-selecting the active segment is idempotent. The centered date continues to open Weekly, and a weekly day heading or Back returns to Daily.

## Update 0.3.2 (historical)

The direct update launcher began setting `NSWorkspace.OpenConfiguration.createsNewApplicationInstance` before opening the embedded helper, and failure alerts began including the underlying localized error. That change prevented helper-process reuse but did not solve argument delivery from the sandboxed main app. The argument transport carried through 0.3.3 and is superseded by the 0.3.4 document handoff described above. The helper's independent checksum, layout, architecture and signature validation remains.

## Update 0.3.1

Settings adds a segmented **Robot home** choice under **Your quiet corner**. `RobotPlacementSettings` stores `corners` or `cameraIsland` under the app-owned `DaBin.robotHome.v1` preference. It is independent of the Daily-board position and capture archive. Invalid or absent values resolve to corners without rewriting preferences; tests and renders can use a non-persisting instance. A live choice change dismisses the current transient robot before the next reveal.

`CornerGeometry.cameraIslandRect` combines `NSScreen.safeAreaInsets.top`, `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`. A positive safe-area inset and a valid gap between the two top auxiliary regions identify the built-in camera island. The trigger expands slightly around and below that gap; the 72 × 88 point robot is centered beneath it, enters from the top, and the Daily panel opens below the robot. On any display without valid island geometry, camera-island mode resolves to the established corner triggers. This fallback applies per display, so an attached external monitor continues using corners.

The transient mascot is rebuilt as `RobotCharacterView`, a native layer hierarchy for its body, shell, face, eyes, mouth, lid, arms, intake card and shadow. `RobotMotionState` gives interaction feedback a fixed priority: result, saving, accepted drag, hover, then idle. The character peeks in from the active edge, gives a greeting, follows the pointer, opens for an accepted drop, performs a two-part digest, and uses separate successful, partial and failed result reactions. Quiet visible idle work includes blinking, looking around and an occasional shrug. Ambient tasks and layer animations stop when the robot hides or the controller shuts down.

`NSWorkspace.accessibilityDisplayShouldReduceMotion` is observed while the app runs. Reduce Motion keeps immediate facial/result expression changes but removes positional, scaling, rotating, repeated and keyframed movement. The existing `RobotView` remains the single drag, paste, click, keyboard and accessibility hit target; decorative character layers do not intercept input.

## Update 0.1.19

In 0.1.19, before the current Daily/Weekly segmented control, Daily's Today control called `showCurrentWeek()`, which explicitly opened the weekly route and selected the current seven-day range regardless of capture count or filter. The weekly control read This Week and restored that current range when browsing history. The centered Daily date still opened a week ending on the selected day; a weekly day heading and Back returned to Daily.

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

The board passes its adaptive accent through SwiftUI's environment and tint. Filters, dates, buttons, source-copy actions, task frames, the DaBin wordmark/emblem and PDF navigation update immediately. The purple transient and empty-state robots remain the mascots; red Task and green Completed retain their status meanings. Light/dark accent variants maintain contrast against the board's neutral surfaces; selected color swatches retain the chosen source color. Theme render fixtures use an isolated preference suite.

## Update 0.1.15

Images and cached previews share a bounded aspect-fit view in Daily, Week, Search and Detail. Both dimensions are constrained before scaling, and a small inset keeps image edges inside the rounded preview. Detail image previews remain 230 points high; documents remain 190 points. The surrounding widget and board sizes do not change.

PDF previews now fit a whole page instead of using PDFKit's continuous-mode fit-to-width behavior. The dedicated `FittedPDFPreview` component retains multi-page navigation. Document/AI/file previews use the existing local Quick Look thumbnail cache for proportional containment, with Open original still available for the complete file. No original content or archive metadata is resized or rewritten.

## Update 0.1.14

Dragging toward the selected reveal target can show the robot while Daily or Week remains open. Moving the board's own header does not trigger this path. Ordinary hover retains the previous minimal-presence behavior. The robot remains visible through input completion and digest feedback, and retreats after the pointer leaves even when the board is still open.

The entire robot view owns hit testing; its artwork and feedback badge cannot intercept drops. Destination callbacks validate advertised readable types and require a copy operation before accepting a transfer. Unsupported or move-only drags are rejected, and exit/end/cancel paths clear drag state. The destination is never ordered out to release hover focus during an active accepted drag. File originals remain untouched; ordinary text without explicit source metadata still reports no source path.

The open board's existing top-left is retained in memory before changing the robot's reveal target or display, preventing an incoming capture from moving an initially unplaced Daily board. This does not rewrite the user's placement preference. HTML and generic data registrations expose the existing original-byte import fallback; HTML-only content remains a local file without loading web resources, while browser selections offering plain text capture that text once.

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

The title and blank header area are a native AppKit drag surface; header buttons retain their normal interactions. Mouse events move the borderless panel using screen coordinates. The window controller pauses layout during the gesture, remembers its top-left point locally, and preserves that anchor during route/height changes and relaunch. Saved coordinates are validated and clamped to a connected display if the screen arrangement changes. The robot continues to reveal at the selected target, with corners as the default and fallback.

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

Daily uses purple icon filters with tooltips and accessibility labels, a geometrically centered date, and a 24-point continuous panel radius. The original empty-state robot gets a small sleepy face, glances, blinks and sighs in empty Daily states. Its timeline pauses when the panel is hidden or occluded, and Reduce Motion selects a static pose. The separate transient robot is superseded by the native 0.3.1 character described above.

Capture detail shows the source location separately from the managed original, with a copy action. Actual file-transfer URLs supply the original path. Explicit WebArchive main-resource URLs can supply the origin of copied text or media; text content, HTML links and the frontmost application are never treated as evidence of origin. Ordinary plain-text clipboard content cannot reveal its source document path unless the sender includes it. File promises expose a temporary delivery location, so that location is deliberately excluded. Source metadata is saved at receipt and retained across source deletion and app relaunch.

Capture payload schema 2 adds optional `sourceFilePath` and `sourceURL`; v1 payloads and older recovery journals remain readable. Existing captures are not retroactively assigned guessed paths. Link records can still show their original URL.

## Native architecture

- `DaBinMain.swift`: accessory lifecycle, native menus, safe quit, startup recovery.
- `CornerController.swift` / `RobotPlacementSettings.swift`: transparent panels, per-display corner/camera-island targets, fallback geometry and local robot-home preference.
- `RobotView.swift` / `RobotCharacterView.swift` / `RobotMotion.swift` / `DailyCaptureView.swift`: one robot input surface, native character state and Reduced Motion, and robot/Daily drag and paste.
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

`Handoff/` is extracted unchanged from the user's ZIP. Prototype HTML is reference only; the app does not embed a web view. `Resources/robot.svg` is byte-identical to the handoff robot and remains the source for its existing icon derivatives. The transient 0.3.1 character is rendered from native layers rather than that SVG. Native views use system fonts and the handoff's light/dark color roles.

`build/qa/screenshots/` contains native NSHostingView renders backed by real isolated persistence. The manifest explicitly labels them as native-view renders, not desktop screenshots. GUI interaction checks used a separately signed `com.dabin.mac.qa` sandbox; fictional items never entered normal DaBin storage.

## Local delivery

The source project and portable ZIP are on Desktop. The executable app is installed at `~/Applications/DaBin.app`, outside Desktop/Documents synchronization. The document provider reattaches a FinderInfo attribute to `.app` directories in synced folders after cleanup, so their later strict codesign checks fail. The personal-Applications copy passed repeated strict verification after installation. Build signing occurs in a local temporary directory; the install script copies without extended attributes and preserves executable permissions. This changes no entitlements or system security settings.
