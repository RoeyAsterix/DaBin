# Native implementation brief

The decisions here are implementation recommendations for the selected design. Validate API availability and behavior with the installed Xcode SDK. Apple references are linked near their relevant use; the overall architecture is a project recommendation, not an Apple-prescribed design.

## Project and components

Default deployment target: **macOS 14+**, Swift, SwiftUI, AppKit, SwiftData. Native `.app` with a shared Xcode scheme and tests. Prefer Apple frameworks and no third-party runtime dependency for MVP. Enable App Sandbox from the first usable build so integration tests exercise the actual permissions model.

Use an accessory/menu-bar application lifecycle with an AppKit application delegate. Keep the bin available after the content panel closes, and provide an explicit Quit action. Recommended component boundaries:

```text
DaBin/
  App/                 app delegate, lifecycle, status-menu controller
  Windows/             bin/content NSPanel controllers, placement, focus
  Features/Bin/        drop target, handle, input state machine
  Features/Capture/    draft editor, batch import status
  Features/Daily/      date navigation, filters, capture rows
  Features/Search/     query state, matching-day groups
  Features/Detail/     original, comment, reminder editor
  Features/Reminders/  upcoming/past reminders
  Features/Settings/   compact native privacy/notification settings
  Domain/              value types, clock, classifier, contextual search
  Persistence/         versioned SwiftData models, repository, migrations
  Services/            attachment store, previews, notifications, pasteboard
  Design/              colors, typography, spacing, reusable components
  Resources/           robot source and asset catalog
DaBinTests/            pure logic and isolated disk-store integration tests
DaBinUITests/          native UI scenarios where practical
```

Use dependency-injected clock, repository, preview fetcher and notification client. Unit tests must not access personal files, network or real notification authorization. Keep fixture mode explicit, debug-only and in a separate store.

## Panels and system integration

Use AppKit-owned `NSPanel`s hosting SwiftUI. The bin is borderless, transparent, small and nonactivating. The content panel must accept key input when explicitly opened while remaining an auxiliary window. Audit `canBecomeKey`, main-window behavior and first responder rather than assuming one style mask handles editing correctly. [Apple: nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel).

Keep all panel/window mutation on the main actor. Persist geometry in preferences; store display identity and edge-relative offsets, not only absolute screen coordinates. Use `visibleFrame` and screen-change notifications. `canJoinAllSpaces` is an API option, not proof that every fullscreen configuration works; verify on the target OS with separate Spaces/displays. [Apple: canJoinAllSpaces](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces).

Small resting window bounds are essential: transparent pixels in a giant window still create potential event interception. Test clicks/drags next to the robot in another app. Expand only the bin window for active drop feedback; keep incoming drag coordinates stable. The content panel opens inward relative to the actual moved bin, unlike the prototype's fixed page positioning.

Implement single/double-click arbitration with `NSEvent.doubleClickInterval`, cancel pending capture on double click/drag, and provide immediate keyboard/menu routes. [Apple: doubleClickInterval](https://developer.apple.com/documentation/appkit/nsevent/doubleclickinterval).

Use an `NSStatusItem` recovery menu. A reliable menu route is required even when global shortcuts are not implemented. App-local keyboard commands are MVP. Optional global shortcuts must be user-assigned and use a supported registration mechanism; do not introduce global keystroke recording or Accessibility permission just for capture. [Apple: NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem).

## Model and persistence

Use a versioned SwiftData schema from v1 and an explicit migration plan as needed. Disable CloudKit for this local-only store. Serialize write operations through a repository/model actor; pass IDs or immutable values across actors, not live context-owned models. Explicitly save before emitting “Saved.” A model-store initialization error must not silently replace the user's database with an empty one. [Apple: ModelContainer](https://developer.apple.com/documentation/swiftdata/modelcontainer), [ModelActor](https://developer.apple.com/documentation/swiftdata/modelactor).

| Field | Meaning and invariant |
| --- | --- |
| `id: UUID` | Stable identity; never regenerate on edit |
| `capturedAt: Date` | Absolute receipt time, frozen before async import |
| `captureDay: String` | Immutable Gregorian `YYYY-MM-DD` in receipt timezone |
| `captureTimeZoneID: String` | IANA identifier at receipt |
| `captureUTCOffsetSeconds: Int` | Receipt offset for stable historical display/fallback |
| `kind` | link, text, image, video, pdf, document, ai, file |
| `originalURL`, `originalText` | Exact supported URL or text representation; optional by kind |
| `attachmentRelativePath` | Managed relative path, never external source as sole original |
| `originalFilename`, `contentType`, `byteCount` | File metadata; unknown is optional, not invented |
| `title`, `previewDescription`, `thumbnailRelativePath` | Derived preview data; disposable/rebuildable |
| `previewState`, `previewError` | idle/loading/ready/unavailable/failed; independent of saved original |
| `comment` | Optional editable plain text |
| `reminderAt`, `reminderTimeZoneID` | Optional absolute future instant and chosen zone |
| `reminderRevision`, `notificationState` | Reconciliation version and pending/scheduled/denied/failed state |
| `createdAt`, `updatedAt` | Persistence audit fields; never substitute for capture time |

Do not include task status or assignment fields. `sourceApp` may be optional when actually supplied; never infer it from foreground-window snooping. Keep all original data distinct from previews.

Use a Gregorian calendar and a POSIX-stable formatter to create `captureDay`; use a localized formatter for display. On travel, group by stored day and render time in its capture zone (show zone in Detail when useful). Inject the clock for midnight, year-end and DST tests. For a multi-item drop, stamp receipt before promises/copies begin; stable ID is the tie-breaker.

Store database and originals under the sandbox's Application Support directory obtained through FileManager. Store regenerable thumbnails under Caches. Suggested layout:

```text
Application Support/DaBin/
  metadata.store             (plus framework-managed companion files)
  Originals/<capture-id>/<sanitized-filename>
  Staging/<import-id>/...
  Imports/<import-id>.json    (recovery journal, if needed)
Caches/DaBin/Previews/<capture-id>/...
```

Never hardcode a user's container path. Keep the display filename verbatim as metadata, but sanitize storage filenames, reject traversal and constrain all resolved paths to managed storage. Do not overwrite existing attachments with equal filenames. Ordinary directories are out of scope for MVP: report them explicitly; do not silently flatten or recursively ingest a folder. Treat symlinks conservatively so a managed “copy” does not still depend on an external target.

### Durable import sequence

1. Accept a readable representation; allocate ID and immutable receipt stamp.
2. Stream/copy original bytes to a uniquely owned staging location off the main thread. For promises, wait for actual delivery; a promise is not a saved file.
3. Verify copy completion and record size/type. Move the finished original into its managed destination on the same volume.
4. Commit metadata and explicitly save the database. Only now emit saved feedback and queue preview work.
5. On failure, retain the user's input where possible, report the failed item and compensate only the newly created files/record owned by this import. Do not roll back unrelated captures.

Filesystem moves and a database transaction are not one atomic transaction. Use an import journal or equivalent recoverable protocol; on launch reconcile interrupted staging/orphans conservatively. Never garbage-collect an ambiguous original merely because preview metadata is missing. Document the recovery protocol and test failure between each step. Free-space/copy failures must not produce a falsely successful card.

## Drag, paste and original access

Bridge a native drop destination to the capture service using pasteboard items, Uniform Type Identifiers and file-promise support. Choose the richest transferable representation per logical item; alternate URL/plain-text/HTML/file representations from that same item are alternatives, not separate captures. Preserve distinct items even when their bytes or URLs happen to be identical.

Preference by item: concrete file or promised file; image bytes; supported web URL; plain text; safely extracted attributed/HTML text. Do not execute pasted HTML or treat script/custom-scheme URIs as launchable web links. Only HTTP(S) strings classify as links. Use a documented finite file-extension fallback when MIME/UTType is absent; port `model.js` cases. `NSFilePromiseReceiver` handles asynchronously supplied file representations. [Apple: NSFilePromiseReceiver](https://developer.apple.com/documentation/appkit/nsfilepromisereceiver).

Do not poll the system clipboard. Read it only for a user paste action or active drop. Use `NSOpenPanel` for Choose files and user-selected read access. Access permission and transfer representations vary by source app: test Finder, a browser, image copy and one file-promise source. Do not assume a denied scope call makes a URL unreadable if it is already inside the container; handle the actual access result. Balance successfully started security-scoped access with its stop call. Short-lived import access is enough for managed copies; persistent external bookmarks are unnecessary unless adding a separately approved reference-in-place mode. [Apple: security-scoped resource access](https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource()).

Open a file with `NSWorkspace` using its managed URL; show actionable error if unavailable. Open a supported web URL in the browser after a click. Copy text uses the user's explicit Copy action. The app must still open managed originals after the source was moved or removed and after relaunch.

## Previews and privacy

Use cancellable background work with bounded concurrency, cache results by capture ID/original identity, and update only preview fields. A preview retry must not recapture the original. Never interpolate saved text into executable HTML.

| Content | Native approach |
| --- | --- |
| Link | `LPMetadataProvider` after preview opt-in; preserve entered URL regardless of redirects |
| Image | ImageIO downsampling for thumbnails; avoid decoding huge originals on the UI thread |
| Video | AVFoundation poster/duration; AVKit playback in Detail |
| PDF | PDFKit first-page thumbnail and page count when readable |
| Document / specialist file | `QLThumbnailGenerator`; specific type fallback if no system generator |

[Apple: LPMetadataProvider](https://developer.apple.com/documentation/linkpresentation/lpmetadataprovider), [QLThumbnailGenerator](https://developer.apple.com/documentation/quicklookthumbnailing/qlthumbnailgenerator).

Recommended default: automatic link previews **off** until explicit opt-in. Explain that enabling them contacts linked websites. Disabling them cancels queued network jobs and stops new automatic fetches; URL capture/open remains available. Network errors, offline state, unsupported formats and preview timeouts leave usable saved cards. No account, telemetry, upload service or cloud entitlement is needed.

## Notification lifecycle

Use `UNUserNotificationCenter` and nonrepeating local requests. The system can handle scheduled delivery while the app is not running; actual visibility is affected by user permission, Focus and OS conditions. Do not promise exact delivery or use an in-app timer as the scheduler. [Apple: scheduling local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).

Request permission in the first reminder-save flow; check current authorization on subsequent saves and app activation. Keep the saved reminder even when permission is denied. Show its scheduling state separately. [Apple: asking notification permission](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications).

Recommended reconciliation design:

- Persist the desired reminder instant and increment its revision; use a stable notification identifier derived from the capture ID.
- Serialize schedule/edit/clear operations. Remove stale pending requests, schedule the current revision and store success/failure. If an async callback belongs to an old revision, reconcile again rather than restoring stale UI.
- On clear, commit the empty reminder and remove pending and delivered notifications for that capture. On reschedule, also clear obsolete delivered alerts.
- On launch, reconcile future desired reminders against pending requests. Never schedule past requests as a catch-up burst. Display them as past reminders instead.
- Put capture ID and reminder revision in notification userInfo. Handle cold-launch responses after the store/window coordinator is ready; open the capture and its immutable day. A stale/cleared notification must not resurrect a reminder.
- Use discreet notification copy such as “You saved something to revisit”; do not expose captured text or filenames on the lock screen by default. Notification dismissal is not task completion and does not move/delete the capture.

## Entitlements, release and boundaries

Start with App Sandbox and user-selected read-only file access for import; add outgoing network client only for opt-in link metadata. Verify each interaction under sandbox. No broad home-folder, Accessibility, Screen Recording, microphone, camera or incoming server entitlement is needed for core scope. Standard local notification authorization uses UserNotifications; remote-push infrastructure is not required. [Apple: configuring App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox).

Use a stable development bundle ID and explicitly record it; changing it can change the storage container and notification identity. Never erase a store to solve a signing/container mismatch. Keep signing-team values configurable. A debug local build and a notarized distributable app are different deliverables; stop short of publishing without the user's distribution instruction.

Launch at login is a later, opt-in convenience if implemented. Use supported service management and reflect actual registration status; never silently register it. [Apple: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice).

Browser localStorage/IndexedDB is not native production storage and is not automatically imported. Its fictional seed data, fixed 480 ms timing, fixed CSS positioning, sample missing originals and review URL parameters must not become shipped behavior. Browser QA does not close native acceptance gates.
