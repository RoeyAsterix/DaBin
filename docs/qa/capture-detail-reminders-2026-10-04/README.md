# Capture detail and persistent reminders — 4 October 2026

## Implemented behavior

- Clicking a capture preview opens a reusable, resizable **DaBin Extended View**. Images use the complete saved original extent; PDFs use their media box. Native text stays selectable and changes font metrics when zoomed. Other supported documents use local Quick Look, and videos use AVKit.
- Fit to Screen, 100%, Reset View, plus/minus, pinch, wheel zoom, and panning are provided. Ordinary precise trackpad scrolling remains native for text and documents. Double-click toggles Fit/100%. No preview is sent to a service.
- A shared, prominent Comments/Reminder tab bar provides saved reply counts, scheduling status, comment posting/editing, countdown/date scheduling, snoozing, and reminder removal. Draft replies survive restart. Reset remains an immediate canvas action.
- Switching the tabs preserves the canvas. Wide and narrow arrangements use `AnyLayout` to keep native view identity. The originating detail remains mounted, preserving its scroll position. A bounded 16-capture cache retains zoom state during the current app session; the window retains its chosen size and position and clamps to an available display when reopened.
- Removed the capture-detail Pin action and its tooltip/accessibility target. Pin functionality still used elsewhere is retained.
- Due reminders and completed focus timers are durable occurrences. One coordinator restores overdue alerts after start/wake/clock changes and schedules the nearest future deadline. Exact revision/date or completion IDs prevent acknowledging a rescheduled alert accidentally.
- A single alarm robot represents all pending occurrences, growing at 8-second intervals to 1×, 1.5×, 2× and at most 3×. Growth and squash are also bounded by the display. At maximum size, clock motion becomes gentler.
- Only the rendered robot and clock accept mouse events. The surrounding transparent native panel, placard and hint remain click-through. Arrival does not activate DaBin. An explicit click saves acknowledgements before opening Extended View or the completed-reminder list. Failed persistence leaves alerts available for retry.
- Reduce Motion uses a static, normal-size robot and visible reminder status. No audio was added. Display changes preserve pending receipts and escalation progress. An accessibility announcement includes the reminder title.

## Architecture and data safety

`CaptureExtendedWindowController` owns the reusable native window and per-capture zoom states. `CaptureExtendedCanvas` centralizes native media rendering and input. `CaptureDetailPanels` shares the reply/reminder UI and the existing recoverable draft.

`CaptureAnnotations` adds ordered replies and exact reminder/focus occurrence tokens. Schema 11 adds optional Codable payload fields to the existing Core Data payload model. Original capture content, dates, files and older single comments remain compatible. The existing aggregate comment text still supports cards, search and export. Append/edit and combined alert acknowledgements use the existing save/rollback mechanisms; archive/backup tests cover both new metadata types.

`ReminderAlertCoordinator` derives pending occurrences from saved state. `TaskTimerRobotPresenter` owns one nonactivating panel, aggregation, acknowledgement and display lifecycle. `TaskTimerRobotView` reuses the current robot artwork with Core Animation transforms. `TaskTimerAlarmMotion` centralizes bounded pacing and scale.

All fixtures use temporary archives, synthetic files and isolated preferences. The user's installed app and personal captures were not used as test data. Pre-existing uncommitted project work was preserved.

## Verified regression run

**12 targeted Release suites passed, with 1,029 distinct checks.** The initial 11-suite pass covered 993 checks. After the media test exposed and fixed an image layout constraint, all five affected viewer/robot suites passed again against the final source (463 checks, including the 36 new media checks). macOS 26.6.2 (25G83), Apple Silicon, Swift 6.4, deployment target macOS 14. Compiler warnings are errors. The recorded source fingerprint did not change during the run.

| Suite | Checks |
| --- | ---: |
| TaskFocusTests | 82 |
| DomainTests | 218 |
| ApplicationLifecycleTests | 77 |
| LocalContentSearchTests | 91 |
| CaptureZoomStateTests | 30 |
| CaptureAnnotationTests | 55 |
| ReminderAlertCoordinatorTests | 26 |
| CommentDraftArchiveTests | 17 |
| DetailPreviewInteractionTests | 110 |
| CaptureExtendedInteractionTests | 24 |
| TaskTimerRobotTests | 263 |
| ExtendedMediaInteractionTests | 36 |

The Extended View fixture presses native accessible controls: opening from the capture page, zooming text, switching sections, posting a reply, removing a reminder, resizing to 480 points, Escape/back, reopening with retained size/zoom, and opening a multiple-reminder list. The robot suite covers actual coordinator → saved acknowledgement → Extended View/list → list-row navigation, live Reduce Motion, rollback/retry, late arrivals, capped growth, transformed hit regions and display changes.

The initial Debug pass found two defects: SwiftUI container identifiers obscured child accessibility identifiers, and text backing-scale changes created implicit animation tracks under Reduce Motion. Both were repaired before the successful Release run. The review also fixed backward-clock handling for focus completion and stale completed-task receipts.

The media suite verifies four complete corner markers with equal pixel areas, image wheel/pinch/double-click/drag, PDF media boxes/pages/native zoom, native text typography and input, complete accessible text, and local RTF Quick Look. It caught and fixed a real image-canvas alignment bug: the intrinsic image width was expanding its ZStack beyond the fitted viewport.

Full machine-readable evidence: [release-regression-report.json](release-regression-report.json) and [final-viewer-regression-report.json](final-viewer-regression-report.json). Native robot evidence: [task-timer-robot-report.json](task-timer-robot-report.json).

## Build and changed files

`DABIN_SIGNING_IDENTITY=- ./scripts/build.sh` passed, producing `native/build/DaBin.app` as an optimized standalone ARM64 app targeting macOS 14. Both app and embedded updater have locally verified signatures. This is a local development build under the existing 0.4.31 (86) version; publishing/versioning and installing it were not part of this change. [Build receipt](build-receipt.json).

The final app executable hash is `f86d7019c088ad52170be9ce4e498cc84f39e17432dbaa6e6dd1d62dc98d95ae`. Every final production-source hash matches both the final viewer test module and app build receipt.

`git diff --check`, Python runner compilation, Xcode project regeneration, and `plutil -lint DaBin.xcodeproj/project.pbxproj` passed. Swift compilation uses warnings as errors.

- Detail UI: `DetailScreen`, `CapturePreviews`, new `CaptureDetailPanels`, `CaptureExtendedWindow`, `CaptureExtendedCanvas`.
- Shared state and recovery: `AppState`, `ApplicationCoordinator`, `DraftArchive`.
- Persistence: `Domain`, `CaptureRepository`, `CaptureStore`, `DailyArchive`, new `CaptureAnnotations`.
- Reminder lifecycle/motion: `TaskFocusSession`, new `ReminderAlertCoordinator`, `TaskTimerAlarmMotion`, `TaskTimerRobotPresenter`, `TaskTimerRobotView`.
- Tests: six new suites (`CaptureZoomState`, `CaptureAnnotation`, `ReminderAlertCoordinator`, `CommentDraftArchive`, `CaptureExtendedInteraction`, `ExtendedMediaInteraction`); updated focus, robot, domain and content-search suites. Registered in `scripts/run_qa.py`; native Xcode project regenerated.

Exact native file paths and hashes: [change-manifest.json](change-manifest.json).

## Native screenshots

- [Capture detail](capture-detail.png)
- [Wide Extended View — comments](extended-wide-comments.png)
- [Wide Extended View — reminder](extended-wide-reminder.png)
- [Narrow Extended View — comments](extended-narrow-comments.png)
- [Narrow Extended View — reminder](extended-narrow-reminder.png)
- [Full image at Fit, all four corners visible](image-fit-complete.png)
- [Image at 100% with pan](image-native-100-panned.png)
- [PDF page 2 at native zoom](pdf-page-2-native-zoom.png)
- [Selectable text after native font zoom](text-native-font-and-zoom.png)
- [Alarm robot at 1×](dark-normal-hold@2x.png)
- [Alarm robot at 3×](dark-normal-stage-3@2x.png)
- [Static Reduce Motion robot](light-reduced-hold@2x.png)

These are actual production SwiftUI/AppKit/Core Animation views with fictional content, not design mockups.

## Platform limits

- Notch/external placement and disconnection use injected display geometry. Physical display unplugging and a live VoiceOver session were not available in this test pass.
- Preview support for arbitrary document types depends on the installed Quick Look provider. Unknown or unavailable originals keep their metadata and display an unavailable state.
- Image decoding has an 8192-pixel edge limit to bound preview work; unusually large images are shown in full extent with downsampled detail. 100% currently refers to decoded pixels per point.
- Zoom/page state is retained during the app session, not persisted across an app restart. Native PDF/text scroll offsets survive Comments/Reminder and responsive layout changes, but are not restored after closing and recreating the Extended View.
- These checks validate the native feature and local build; they do not constitute new notarization, App Store approval, or testing on another physical Mac.
