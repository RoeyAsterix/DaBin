# DaBin desktop buddy redesign

## Implemented design

- Full-width fitted capture previews, lighter rounded cards, a compact icon action rail, and distinct open/completed task surfaces.
- Source application icons are resolved locally from the recorded bundle identifier. Website locations have a domain/globe fallback. Source locations expand on demand. The destination is explicitly labeled **Saved in DaBin**; external paste destinations are not inferred.
- Converting a capture opens its task workspace. Tasks accept files and text from drag-and-drop, the clipboard, or a file picker. Attachments remain ordinary searchable/exportable capture records with their original receipt date and source, linked through `parentTaskID`. Library shows the containing task, while receipt history retains each recorded action.
- Reminder editor supports an illustrated clock, date/time, and `hours:minutes` countdown. Save resolves countdown intent to one absolute deadline; reopening or editing a comment never restarts it.
- Completing a persisted task makes the visible robot happy. Reopening or a failed save does not celebrate, and hidden windows stay hidden.
- Auto Capture lives beside the logo, with clear on/paused/setup behavior. Library has consistent icon filters. Settings can disable hover tooltips without removing accessibility names.
- A thin robot shell reserves space for its head, hands, and feet outside content. Dragging any edge/corner resizes the app and remembers the size. Expand/restore uses the current display's safe area and does not switch Spaces. Manual island reveal is 0.55 seconds instead of 1.1 seconds.

## Persistence and privacy

Schema 8 adds an optional parent task identifier; schema 1–7 data remains readable. Attachment families participate in transactional trash/restore/delete and interrupted-operation recovery. File transfers validate that the parent is still a live task at commit time. Provider file representations are copied during their callback, with a bounded timeout and normal archive integrity checks.

No external paste monitoring, additional permissions, new remote preview requests, or private capture thumbnails in robot animations were introduced.

## Verification

- Final ARM64 Release build: **0.4.1 (49)**, warnings treated as errors. Build receipt matches all source/build inputs and executable SHA-256.
- Final Release regression run: **34/34 suites passed, 42,182 reported checks**, with no source changes during the run. [Machine-readable report](release-regression-report.json) and [log](release-regression.log).
- Native interaction coverage: **7/7 window suites passed across the final run and a targeted rerun**, covering header accessibility/keyboard actions, native task paste/drop and editor focus, resize/filter transitions, robot drag/drop, weekly expansion and robot window transitions. Together with the core run, **all 41 registered suites have passing results on identical production inputs**. [Combined verification](combined-verification.json) retains the original failures and rerun evidence.
- Independent visual review: **40 production renders** at 380 and 720 points, light/dark. Task/countdown/date controls fit at the narrow width; attachment text/media, app source icons, and the thin robot shell were reviewed. Explicit appearance assertions cover the nested native window/frame/hosting view. These are 1× view snapshots, not a claim of physical Retina or live mouse/keyboard verification.
- Xcode project generation check, Swift parser validation, and `git diff --check` passed. No separate lint configuration is present.
- Strict code-signature verification passed on `/tmp/DaBin-Buddy-0.4.1-build49/DaBin.app`, a clean copy of the exact built bytes. The synced Documents folder can reattach Finder/file-provider metadata to app bundle directories; the existing build and install tooling deliberately copies bytes without that metadata before verification or installation. No security settings were weakened.

The initial window run exposed an incorrect test assumption that occluded windows should celebrate. Diagnostics verified that the locked screen correctly suppressed the animation, preserved focus, and kept the dismissed board hidden. The test now checks both visible and occluded behavior separately; visible-frame feedback also has direct unit coverage. One weekly intermediate-frame assertion failed once under load; an unchanged-code diagnostic and strict rerun both passed (14 genuine intermediate frames in each direction). This transient scheduling sensitivity remains recorded; no production condition or weekly assertion was relaxed.

The initial broad Debug run found three test failures: an obsolete manual-reveal timing expectation, a one-point AppKit panel constraint in synthetic display geometry, and an outdated build-number expectation. Expectations were corrected without weakening pure geometry or automatic-capture timing checks; the final Release run passed all three.

Test stores, preferences, notification clients, and pasteboards are isolated from the personal archive. The Mac is locked, so live desktop interaction and replacing the currently running installed app remain pending. The installed app has not been replaced or forcibly terminated.

## Selected native renders

- [Task workspace and attachments](native-view-buddy-task-attachments-light-380x740.png)
- [Clock/countdown reminder](native-view-buddy-task-countdown-light-380x680.png)
- [Wide Library with media](native-view-buddy-library-media-dark-720x620.png)
- [Thin robot frame in light mode](native-view-buddy-robot-frame-light-400x670.png)

## Changed implementation areas

- `BoardView`, `BoardComponents`, `BuddyControls`, `CaptureFilterStrip`, `LibraryScreen`: header/icons, tooltips, filters, responsive Library.
- `CaptureCards`, `GroupedCaptureCard`, `CapturePreviews`, `CaptureSourceView`, `DetailScreen`, `TaskAttachmentsView`, `TaskEditorScreen`, `ReminderClockEditor`: preview-first cards, task workspaces, provenance and reminder controls.
- `Domain`, `CaptureStore`, `CaptureRepository`, `OriginalFileStorage`, `InputService`, `ReminderSchedule`, `AppState`: durable task relationships, safe file transfer, transactional recovery, reminder deadlines and navigation.
- `ApplicationCoordinator`, `CornerController`, `BoardResizeGeometry`, `DailyCaptureView`, `RobotAppFrameView`, `RobotMotion`, `RobotCharacterView`: successful-completion feedback, task paste/drop routing, resizing, theme propagation and island timing.
- `ThemeSettings`, `SettingsScreen`, remaining icon-action views: persistent tooltip preference and consistent conditional help.
- Existing storage, task, input, theme, motion, header/window and render tests were extended; project inventory and version metadata updated.

## Remaining platform limits

Source attribution exists only when recorded data supplies it. Installed application icons are local; websites use a domain/globe fallback. “Saved in DaBin” is the verified destination. The app does not monitor or invent external paste destinations. Expand fills the current display's safe area while preserving the app's existing passive-panel behavior and current Space. This local build is not a newly notarized public installer or TestFlight upload.
