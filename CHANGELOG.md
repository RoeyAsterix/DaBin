# Changelog

## 0.4.19 (74) - 2026-10-02, local candidate

- Aligns the board, native reveal mask and metal rim to one continuous rounded-corner profile; removes the mismatched circular host clip and fills gaps in the corner rim.
- Updates custom vector/mask backing scales when attaching or moving between displays, without rasterizing the interactive board.
- Draws the continuous rim as a hollow vector fill instead of compositing another full-window gradient and mask.
- Makes every visible edge grabbable, with wider transparent-gutter targets and shallow inside padding; connects the card corners to the physical outer window corners.
- Shares resize geometry with cursor regions and preserves header button/project-picker click areas, central chrome dragging, minimum sizes and expand/restore behavior.
- Keeps the original cancelable robot shrink/fade and four-subpath torso-fill choreography. Capture data and preferences are not part of this window-only change.
- Prepares current App Store privacy resources, friendly listing/reviewer copy, native screenshot drafts and packaging checks. All 73 registered Release suites, 39 media checks, 77 offline Python tests and 51 unsigned Store packaging checks pass; signed distribution/runtime verification and owner declarations remain pending. [Preparation evidence](docs/qa/app-store-2026-10-02/README.md). This is not a binary release or Apple approval.
- Publishes the approved source, guide/copy and QA docs to GitHub main; verifies the corrected public privacy policy by HTTP status and exact source hash. [Publication receipt](docs/qa/app-store-2026-10-02/publication.json). Downloads and the installed app are unchanged by this push.

## 0.4.18 (73) - 2026-10-02, local candidate

- Limits brief in-app notification banners and robot message popovers to two seconds, using monotonic deadlines and cancelable presentation receipts.
- Times out reminder feedback, successful detail/scratchpad saves, clipboard cleanup confirmations, and trail/source/export operation messages without erasing underlying diagnostics or saved data.
- Restarts the deadline for repeated identical messages; old expiry callbacks cannot dismiss a newer message, and expired banners no longer reserve window height.
- Fixes export success-to-failure dismissal races and repeated identical export feedback in the main banner.
- Keeps unsaved-form errors, recovery controls, Undo, in-progress/state indicators and the click-to-dismiss task alarm persistent. System notification duration remains controlled by macOS.

## 0.4.17 (72) - 2026-10-01, local candidate

- Redesigns Explorer capture cards around a large, full-width fitted preview, with the title and original capture date/category beneath it and compact sibling actions.
- Keeps images, video stills, PDF/document pages and visual captures promoted to tasks preview-led; text-only notes and files without a preview remain compact.
- Preserves project-leading labels and frames, attachment inheritance, task controls, selection/keyboard navigation, drag transfer and recoverable removal.
- Reuses the bounded background thumbnail cache without row-level original-file reads, native media players or network requests.

## 0.4.16 (71) - 2026-10-01, local candidate

- Announces successfully saved task focus-timer expiry with a slightly larger canonical robot, an island leap, a visually ringing alarm clock and a sign containing the task's first three words.
- Keeps the alert visible until the robot is clicked or pressed through accessibility, then shrinks and returns it home. Expiry pauses the focus timer at zero without completing the task; acknowledgement does not restart the timer or edit task data.
- Queues separate timer expiries, including repeated runs of the same task; preserves unacknowledged alerts across manual robot interaction and display changes.
- Gives the timer independent island ownership so Auto Capture cannot overlap it; board-open expiry appears immediately without changing navigation.
- Uses static silent presentation for Quiet mode and Reduce Motion, with no audio, notification permission or per-frame application timer. Shutdown cancels pending expiry and return callbacks.

## 0.4.15 (70) - 2026-10-01, local candidate

- Gives collapsed hourly collections and minimized file batches a large, responsive mosaic of up to four real local previews, with a truthful overflow badge and readable text/file fallbacks.
- Places capture count and immutable saved date/time directly beneath the previews; keeps capture totals distinct from automatic action counts, including filtered collections and promoted tasks.
- Keeps one collection-expansion target, full batch copy, existing details/reminders/removal controls, stable hourly scroll identity and persisted batch collapse state.
- Reserves preview-led summary height in native window sizing and reuses the bounded background thumbnail cache; collection previews do not start players or contact websites.

## 0.4.14 (69) - 2026-10-01, local candidate

- Replaces the flat close with a 0.78-second inward fold, compact robot pose and final shrinking tuck/fade toward its island or screen-corner home.
- Fixes a Core Animation key collision that replaced the live content's shrink transform with its fade; content, outline and robot body now contract together.
- Grows the temporary metallic torso fill smoothly instead of flashing a full-size backing plate, and preserves presented opacity/mask state when reopening late in the close.
- Keeps the 0.14-second static Reduce Motion fade, final-size hosted content, cancelable generations and exactly-once closing cleanup.

## 0.4.13 (68) - 2026-10-01, local candidate

- Removes the manual add-paste plus button from capture trails and the alternate Record a paste form from the history popover.
- Keeps original source information, existing paste receipts and correction of legacy manually recorded entries; opening or copying a capture does not invent a paste event.
- Includes the tooltip, robot, preview-click and timestamp improvements. Installed and verified locally after the older app was force-quit with explicit permission; its previous bundle was backed up.

## 0.4.12 (67) - 2026-10-01, local candidate

- Restores visible hover labels using real control anchors, including the redesigned header and capture actions; labels wrap and stay inside the window without intercepting clicks.
- Makes Settings → Appearance → Show tooltips apply immediately to the board, popovers, sheets, island robot, drag handles and menu-bar status icon. Existing saved choices are preserved; the default is enabled.
- Cancels delayed or visible help when disabled, hidden, removed or navigating; keyboard/accessibility labels remain available independently of visual tooltips.
- Includes pending robot, preview-click and timestamp improvements; installation still requires a safe exit from the older running app.

## 0.4.11 (66) - 2026-10-01, local candidate

- Uses one canonical Quiet Orbit head renderer for the island robot and full application frame: angular metallic shell, polygon visor, rectangular mint eyes, scanlines and the same mouth/seam details.
- Removes the old frame's bin lid, handle and separate dark pupils; matches its shell and articulated limbs to the island's metal/silver palette.
- Preserves head proportions during expansion and retains native gaze, blink, resizing, click-through, content transparency and Reduce Motion behavior.
- Uses the native island robot in empty states rather than a legacy SVG and a second face; sleepy motion remains visible-only and bounded.
- Includes pending preview-click and timestamp improvements from 0.4.9–0.4.10; local installation still requires a safe exit from the older running session.

## 0.4.10 (65) - 2026-10-01, local candidate

- Enlarges the capture page's original date and time from 11-point muted text to 16-point medium-weight, high-contrast text.
- Shows the original date and time before the category on daily, weekly, project, Explorer and grouped capture cards.
- Keeps timestamps tied to the original capture day and recorded UTC offset, including after edits or time-zone changes.
- Includes the pending click-to-open file preview behavior from 0.4.9; local installation is pending a safe exit from the unresponsive running app.

## 0.4.9 (64) - 2026-10-01, local candidate

- Clicking a file preview on its capture page opens the saved original in the default macOS application.
- Explorer's inspector uses the same click-to-open behavior, with keyboard and accessibility activation.
- PDFs show a fitted page and videos show a playable-file thumbnail; full document navigation and playback open in the original application's window.
- Preserves background image loading, validated archive paths and existing missing-file feedback.

## 0.4.8 (63) - 2026-10-01, local candidate

- Removes repeated full-text normalization from ordinary Explorer browsing and shares one query result across each view update.
- Reuses immutable original-text search data while keeping edited titles, comments and indexed text immediately searchable.
- Loads dated-file lists, daily previews and downsampled capture images away from the UI thread; image reuse is bounded and tracks file replacements.
- Lets stationary robot gaze settle and skips unchanged window geometry and click-through updates.
- Retains project colors, automatic project routing and the waving project sign from build 62.

## 0.4.7 (62) - 2026-10-01, local candidate

- Promotes Projects in the primary navigation and moves project identity above capture content.
- Adds project colors, including color selection during creation, later color changes and a matching frame around cards in the active project.
- Routes new Auto Capture items directly to the selected project and gives the robot a color-matched project sign that waves for each save.
- Removes redundant or inert visible controls while preserving the useful menu, keyboard and accessibility paths.
- Keeps existing archives compatible: project colors and automatic-capture destinations are additive, optional metadata.
- Public testing release remains gated on complete local verification, Apple signing and notarization; see the [candidate notes](docs/RELEASE_NOTES_0.4.7.md).

## 0.4.6 (61) - 2026-10-01, local candidate

- Includes the pending Inbox Day / Week calendar and Quiet Orbit robot redesign.
- Fixes relocated capture feedback, stale reminder draft recovery and invisible shelved task attachments.
- Binds the embedded updater executable to the Release receipt before public signing.
- Updates the guide and privacy wording; preserves visible trash, window resizing and Explorer.
- Public testing release remains gated on Apple signing and notarization; see the [candidate notes](docs/RELEASE_NOTES_0.4.6.md).

## 0.3.18 — 2026-09-24

- Moved a compact **Get updates** card to the top of Settings so the installed version, update status, and controls are visible immediately at the 380-point window size.
- Kept **Check for updates**, conditional **Download & install**, progress, failure and success states, while adding complete accessibility labels and an always-visible latest GitHub release link to direct builds.
- Added permanent GitHub download URLs for the recommended installer/update and direct Apple Silicon packages.
- Added verified release staging that creates byte-identical stable aliases, plus a GitHub release workflow that restores those aliases whenever a release is published.

## 0.3.17 — 2026-09-24

- Added a clearly labeled **Quit DaBin** action at the bottom of Settings, with a power icon, tooltip, and complete accessibility label and hint.
- Routed the action through the native macOS termination flow so removal, active input, and unsaved-draft checks still apply before every window and background service shuts down.
- Verified that termination stops Auto Capture clipboard polling and screenshot-folder monitoring and prevents any later automatic capture from committing.
- Added a separate Apple Silicon manual-install package alongside the verified GitHub update/installer package, with both installation paths targeting `~/Applications/DaBin.app`.
- Published both packages, completed the public 0.3.16 → 0.3.17 in-app update, directly installed the standalone package, and confirmed the Settings action leaves no DaBin process running while local data and preferences remain unchanged.

## 0.3.16 — 2026-09-24

- Replaced the text Daily/Weekly segmented control with matched purple `1` and `7` calendar icons.
- Reused the action/filter icon language: 15-point symbols, 40 × 34-point targets, 30-point selected and hover circles, pressed feedback, focus rings and 220 ms tooltips.
- Kept both modes accessible as individually labeled buttons with selected state, left/right keyboard switching and stable identifiers, while reducing the control from 92 to 80 points for the narrow header.
- Published and installed 0.3.16 through DaBin's verified updater; live Daily/Weekly interaction, the real hover label and current-version check passed while the archive, preferences and Desktop link remained unchanged.

## 0.3.15 — 2026-09-24

- Moved Settings tooltip hover tracking from the menu's inner icon label to the outer native Menu, so the gear receives the same delayed hover label as the other header icons under real macOS hit testing.
- Left the other ten action and filter tooltips, their timing, keyboard-focus behavior, accessibility names and the paired 280 × 34-point row geometry unchanged.
- Superseded 0.3.14 after its public release and successful in-app installation: live pointer QA found this Settings-only hover gap after publication.
- Published and installed 0.3.15 through DaBin's verified updater; live pointer QA passed and the existing archive and preferences remained byte-identical.

## 0.3.14 — 2026-09-24

- Added compact custom hover tooltips to all five primary actions and six content filters, with short visible labels and complete accessibility names.
- Showed each tooltip after a 220 ms hover delay, exposed the same label for keyboard focus, dismissed it on click and cleared it after pointer and focus leave.
- Kept the existing 280 × 34-point action and filter row geometry unchanged, with representative light and dark render coverage and targeted interaction tests added for release verification.
- Published and installed the release successfully through DaBin's verified updater; subsequent live pointer QA exposed the Settings-only menu-hover gap corrected in 0.3.15.

## 0.3.13 — 2026-09-24

- Aligned the primary-action and filter controls as two visually identical compact rows with the same 280 × 34-point footprint.
- Standardized every row control on a 15-point SF Symbol in an 18-point canvas, a 40 × 34-point target and a 30-point circular selected or hover surface.
- Distributed the five primary actions between the same outer edges as the six filters while preserving every action's order and behavior.
- Kept the compact Daily and Weekly headers aligned at narrow width in both light and dark appearances.

## 0.3.12 — 2026-09-24

- Added an anchored Weekly Search menu with an explicit seven-day picker and separate **Search Day** and **Search Week** actions.
- Added Weekly export choices for **Copy Day**, **Download Day**, **Copy Week** and **Download Week**, with matching deterministic UTF-8 output for each copy/download pair.
- Kept search aligned with the active content filter and same-day neighboring context while making downloads include every stored action in their selected day or fixed seven-day range.
- Included empty dates in the day picker even when Weekly hides their columns, preserved the selected week and feed state, and returned scoped Search to Weekly.
- Added keyboard shortcuts, focus treatment, accessible names, empty-state disabling and scope-specific success or failure feedback to both action popovers.

## 0.3.11 — 2026-09-24

- Rebuilt the successful Auto Capture confirmation as a single polished anticipation, entrance, reaction and exit timeline that lives against the Mac camera island.
- Added twelve shuffled robot celebrations with no repeat among the previous three, plus subtle timing, gaze and entrance variation.
- Kept rapid captures in one click-through panel: the current reaction finishes once while a compact `×N` badge updates immediately.
- Added a dedicated Reduce Motion sequence with a short static peek, success check and gentle fade, with no sound.
- Anchored the popup to the real camera-island rectangle when macOS reports one, retained a safe built-in fallback and kept external-primary placement at the top-right.

## 0.3.10 — 2026-09-24

- Added a dedicated **Text** filter immediately before Links in the centered filter row.
- Used DaBin's existing aligned-text SF Symbol and purple filter treatment, with the tooltip and accessible name **Copy/paste text**.
- Limited the filter to copied, pasted or dragged plain text, excluding links, tasks and document files.
- Applied the filter consistently to Daily, contextual Search, Weekly and automatic hourly groups without changing active Weekly dates.

## 0.3.9 — 2026-09-24

- Removed empty dates from Weekly while preserving the complete seven-date navigation range.
- Counted carried tasks and reminder-day tasks as activity so the dates where they appear remain visible.
- Sized the Weekly panel to its active date columns and kept a completely empty range at the compact bored-robot view.

## 0.3.8 — 2026-09-24

- Added **Export Day** between Search and Notifications with **Copy Day** and **Export Text File** actions.
- Exported the complete selected calendar date in chronological order, independently of the active content filter, with timestamps, types, source applications and available text.
- Preserved multi-item capture boundaries in the export, added clear image placeholders when no caption or OCR text exists, and made clipboard and file output byte-for-byte equivalent UTF-8 text.
- Added empty, success, cancellation and failure handling, plus keyboard shortcuts, focus treatment, accessible labels, Escape dismissal and outside-click dismissal for the export popover.
- Rebuilt Daily and Weekly navigation as three compact rows for navigation, primary actions and filters, removing the previous vertical dead space while retaining narrow-window behavior.
- Restyled Add, Search, Export Day, Notifications and Settings with the filter icon language, kept their rows centered on one axis, and preserved the neutral independent window-close control.

## 0.3.7 — 2026-09-24

- Replaced the Daily and Weekly header's three-dot options icon with an outline settings wheel.
- Matched the wheel's size, colour and hit area to the adjacent task, search and reminder icons.
- Renamed the control's help and accessibility label to **Settings and options** while preserving its existing menu actions.

## 0.3.6 — 2026-09-24

- Replaced flat separators on individual caption cards with thin, continuous rounded frames in Daily, Search and Reminders.
- Kept the stronger theme-colour outline for carried tasks while giving ordinary cards a quiet neutral frame in light and dark appearances.
- Preserved the existing hourly-action frame without adding a competing nested outline, and adjusted compact panel sizing for the new card spacing.

## 0.3.5 — 2026-09-23

- Added opt-in **Auto Capture** under Settings → Capture, off by default, for future clipboard changes and new screenshots written to a user-selected folder.
- Added visible enabled, paused, permission and exclusion states; a quick Pause command; and default exclusions for DaBin and common password managers.
- Stored automatic action origin, timestamp, content and best-effort source-application metadata in the existing local archive, with cross-channel image duplicate suppression and no automatic website-preview requests.
- Grouped the fourth successful automatic action in a fixed local clock hour into one expandable summary with a stable count and accessible minus control.
- Added a passive success robot on the hardware primary display, with safe-area placement, burst counting, screen-capture exclusion and Reduce Motion support.
- Preserved immediate cancellation on Pause or Off, prevented pre-existing clipboard and folder contents from importing, and withheld success confirmation for failed or partly failed actions.

## 0.3.4 — 2026-09-23

- Superseded 0.3.3 and carried forward its compact **Daily / Weekly** segmented control, selected-date anchoring, filter and scroll continuity, drafts, panel transition and Reduce Motion behavior.
- Replaced the sandbox-incompatible updater launch-argument handoff with a private, one-use document beside the verified ZIP.
- Made the installer validate the document owner, permissions, schema, package name, location and SHA-256 before consuming it and independently checking the package as before.
- Kept the local capture archive outside the update flow and unchanged during installation.

## 0.3.3 — 2026-09-23

- Replaced the separate Today and This Week actions with one compact **Daily / Weekly** segmented control.
- Anchored Daily → Weekly to the selected day and made Weekly → Daily return without resetting the selected date, type filter, Daily scroll position or unsaved drafts.

This release is superseded by 0.3.4 because its direct updater still relied on launch arguments that macOS does not deliver from the sandboxed caller.

## 0.3.2 — 2026-09-23

- Requested a fresh embedded-updater instance to avoid helper-process reuse; later live QA showed that sandboxed LaunchServices still discarded the ZIP path and SHA-256 arguments, so 0.3.4 replaces this transport.
- Added the underlying updater error to the native failure alert instead of showing only a generic heading.

## 0.3.1 — 2026-09-23

- Added **Settings → Your quiet corner → Below camera island** for Macs with a built-in camera island.
- Used macOS screen safe-area and auxiliary top-region geometry to place the robot below the real camera cutout; displays without that geometry continue using their corners.
- Rebuilt the transient robot as a native character that peeks in, follows the pointer, welcomes a drop, digests a capture and reacts to successful, partial and failed saves.
- Added quiet idle blinks, glances and shrugs while the robot is visible, with animation work stopped when it hides.
- Respected the macOS Reduce Motion setting by keeping the robot's expressions while removing positional, repeated and keyframed movement.
- Kept the robot-home choice in a local app preference, separate from captures and the movable Daily-board position.

## 0.3.0 — 2026-09-23

- Added a user-initiated GitHub Releases update check in Settings and the app menu.
- Added verified in-app download using a fixed HTTPS origin, exact size and SHA-256 checksum.
- Embedded a signed update helper in direct builds; it confirms, re-verifies, backs up, replaces and relaunches DaBin while preserving the local capture archive.
- Kept the direct update downloader and helper out of the Mac App Store build path.
- Added dark mode and transparency controls.
- Grouped files received in one paste or drop into one caption card.
- Updated the one-page PDF guide and privacy documentation.

## 0.2.2 — 2026-09-23

- Added dark mode and board opacity settings.
- Added grouped multi-file capture cards.
- Completed the local update package and expanded release QA.

Earlier implementation history is recorded in [native/IMPLEMENTATION_NOTES.md](native/IMPLEMENTATION_NOTES.md) and [native/QA_RESULTS.md](native/QA_RESULTS.md).
