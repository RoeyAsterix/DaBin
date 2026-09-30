# DaBin buddy redesign — independent UX review

Review date: 29 September 2026. Scope: the shipping native AppKit/SwiftUI application, with preservation of its local archive, calendar, capture, and robot behavior. This review is based on production source; rendered-image verification is recorded separately below.

## Design direction

Make captured content the visual focus and let the robot provide personality around it. Use the existing adaptive `Palette`, theme accent, SF Symbols, and `AccentIconButton` vocabulary. Reduce visual weight through thinner outlines, quieter backgrounds, compact metadata, and fewer persistent labels. Keep useful text for content, times, errors, and decisions where a symbol alone would be ambiguous.

### Information order

1. **Header:** logo, Auto Capture state, flexible space, clear close control. The enabled state needs a distinct fill/check or dot and an accessible value, not brightness alone.
2. **Navigation and filters:** consistent icon targets, clear selected state, shared tooltip preference, no nested settings destination.
3. **Capture card:** short title and time; generous fitted preview; compact source and status metadata; consistent copy/comment/reminder/more actions.
4. **Capture detail:** compact title and actions, the preview, optional task workspace, then notes, reminder, and provenance details. Do not place rarely used organization settings above the preview.
5. **Task card/detail:** a clear completion control, distinct but quiet task surface, visible next step, reminder, and attached content. Conversion reveals task controls immediately and retains the original preview.

## Production findings and implementation guidance

| Area | Existing behavior reviewed | Recommended change and acceptance check |
| --- | --- | --- |
| Cards | `CaptureRow` constrains media to 48 × 52 points beside three title lines. | Make expanded preview the main card region, preferably 128–180 points high in compact cards. Fit the whole image/page; do not crop document edges. Minimized cards remain a single compact summary. |
| Detail | Task/organization controls precede `DetailPreview`; media has a fixed 230-point height. | Place compact action rail near the title and preview immediately beneath. Let preview grow with window width while bounding height so actions remain discoverable. Avoid showing duplicate OCR and preview text by default. |
| Task transformation | A converted file keeps its original `Capture.kind`; task status is separate. | Preserve this model. Give a task a visible completion indicator and a lightly tinted task surface; show attachment/reminder controls when it becomes a task. Retain its original file, source, date, title, notes, and indexed text. |
| Task files | Existing import batches group by immutable `capturedAt`. | Use an explicit task relationship for attachments. Never alter receipt time to force membership. A drop on a task must not also create a duplicate board capture. Handle partial import failure and promised files. |
| Filters | `CaptureFilterMenu` renders text-only options; Library has a project menu plus Pinned checkbox. | Use the same ordered type icons in Library and timeline: All, Text, Links, Files, Media, Tasks. Add symbols to native submenu entries. Project and Pinned filters must retain their independent state. |
| Tooltips | Existing `AccentIconButton` has hover/focus tooltip infrastructure; native `.help` appears elsewhere. | Persist one preference, enabled by default, and apply it to the new icons and native help. Turning it off must dismiss any current tip. Preserve accessibility labels, hints, selected state, focus rings, and keyboard activation. |
| Source | `CaptureSourceView` displays source app/path/URL as text. The model records source application identity. | Resolve installed application icons locally. Use existing website preview/icon data where available and a globe fallback otherwise. Include source name in accessibility text and preserve a way to read/copy the exact location. |
| Paste destination | The model currently has no verified external paste destination. | Show DaBin or the task as destination only for an actual import into it. Copying an item does not prove it was pasted anywhere. Do not infer paste destination from the frontmost app or fabricate a website/app icon. |
| Reminder | A switch reveals one date/time picker. | Add a small readable clock with **Countdown** and **Date** modes. Hours and minutes must be editable with keyboard and steppers; mode is not encoded by symbol alone. Resolve a countdown to one absolute due date when saving. Display the resulting due time and timezone. |
| Robot frame | `RobotAppFrameView` reserves 32 points on top, 10 at each side, and 18 below; torso gradients can dominate. | Use a fine perimeter, recognizably matching lid/face, small arms and feet, and restrained tint. Keep reserved content bounds. Decorative parts must not cover the search field, scroll bars, controls, or card edges. |
| Resize | The board is a borderless nonactivating panel; `resizeBoard` derives size from route and item count. | Add usable edge/corner resize zones and remember manually chosen size. Once manually resized, filters, previews, or routes must not snap it back. Clamp to the current display's visible bounds. Maintain independent compact/full-view behavior. |
| Hover entrance | Island choreography is independent from app expansion and capture reactions. | Halve only the intended island hover entrance. Keep capture-save and screenshot-completion ordering intact. Opening/capture/close state transitions must still cancel cleanly. |
| Completion | Task status is a model mutation with persistence/reminder side effects. | Play the happy response only after a successful transition from incomplete to complete. Reopening tasks, rendering already-completed tasks, failed persistence, and initial loading must not celebrate. Respect Reduce Motion. |

## Icon and accessibility contract

- Use SF Symbols at a consistent perceived size and weight, inside at least a 28–34 point target on the compact desktop layout. Preserve the existing 40 × 34 timeline targets when space permits.
- Use `Label` in native menus so icons supplement menu text. In the visible action rail, use icon-only presentation with meaningful `accessibilityLabel` and optional help.
- Keep **Save**, destructive confirmation, task completion state, reminder mode, and due time understandable without guessing symbols. “As many icons as possible” should not make content or decisions cryptic.
- Tab order follows visual order. Space/Return activates the focused control. Native menus and popovers support Escape, and closing one must not close the app window.
- A disabled-tooltip preference is visual only; VoiceOver still identifies every control and current state. Selected filter state must not depend on color alone.
- A clock face is a supplemental visualization. Date/time fields remain the precise and accessible editing mechanism.
- Red/green task status also uses different glyphs and descriptive accessibility values. Avoid low-contrast disabled-looking text on active controls.

## Reminder and task attachment behavior

### Countdown

- Validate hours ≥ 0 and minutes 0–59, with a positive total; show a clear inline message for zero or invalid input.
- Compute the deadline at Save. Reopening the detail must not restart the countdown or silently alter an existing reminder.
- Switching modes should preserve the proposed deadline when possible. Show the exact scheduled local date/time before save.
- Completed tasks keep their original reminder metadata but clearly show that delivery is paused according to existing reminder semantics.
- Changing the system timezone or crossing daylight-saving time must not lengthen an already saved duration; store the absolute deadline through the existing reminder model.

### Attachments

- Entering a task drop target visibly highlights that task only. Show the count of successfully attached files and allow opening each attachment.
- Keep an explicit Add files action for keyboard users. Pasting while a text editor owns focus must continue editing text; it must not be intercepted as a task file import.
- File imports remain local, preserve original files, and use the existing managed-original storage and validation service.
- Reopening/restarting, backup/restore, and deleting/restoring a task preserve attachments. A missing original should yield a recoverable placeholder rather than a blank layout.
- If a batch partly fails, keep the successful attachments and name the failed count. Never claim that all files were attached.

## Responsive layout review matrix

| Configuration | Required result |
| --- | --- |
| Minimum compact width | Header controls and all type filters remain reachable; no clipping of X or Auto Capture; card controls do not collide with time. |
| Medium width | Preview expands before metadata gutters expand; task actions fit without oversized whitespace. |
| Wide/full view | Content has a readable maximum measure or purposeful adaptive columns; images fit; clock and attachment controls remain close to task content. |
| Short window | Main content scrolls; save/footer controls remain reachable; decorative robot elements stay outside scroll content. |
| Light and dark appearance | Preview, border, body frame, clock, and disabled states remain distinct. |
| Minimum allowed transparency | Text and controls remain readable on both busy light and dark desktop backgrounds; Reduce Transparency forces the intended solid surface. |
| Reduce Motion | No continuous rocking or spring motion; short fades and static happy confirmation remain understandable. |
| Display reconfiguration | Window returns within an available screen; saved width/height do not strand it; external display uses its existing entry point. |

## Verification checklist

### Functional gates

- [ ] Each filter produces the same underlying results in timeline and Library, including converted image/file tasks.
- [ ] Tooltip setting persists across launches, updates visible controls immediately, and leaves accessibility intact.
- [ ] Auto Capture toggle remains beside the logo on all principal routes and still respects first-enable consent/permission, pause, and error states.
- [ ] Card copy, notes, reminders, pin/project, minimize, delete/undo, preview, and original-file actions remain functional.
- [ ] Task conversion reveals the task workspace without losing draft edits, source information, or scroll context.
- [ ] Attachment drop, paste, file picker, duplicates, partial failures, reopen, and backup/restore are covered.
- [ ] Countdown and date reminder modes schedule the intended deadline, including zero input and completed-task behavior.
- [ ] Happy robot response is successful-completion-only and does not steal focus or block input.
- [ ] Manual resize persists and is not overwritten by filters, incoming captures, preview completion, or route changes.
- [ ] Hover entrance timing is half its former value; other state machine behavior remains valid.

### Visual gates

- [ ] Production render with mixed text/PDF/image/link cards at compact and wide sizes.
- [ ] Converted task with multiple files, a comment, and both reminder modes; completed and incomplete states.
- [ ] Library filters selected/hovered/focused with tooltips enabled and disabled.
- [ ] Light/dark renders plus empty state and long title/source URL.
- [ ] Robot body open at compact and wide sizes, with no content occlusion and clear character continuity.
- [ ] Keyboard-only action path and visible focus rings, including task attachment and reminder controls.

## Review status

Initial source review complete. The checklist above is a release review contract, not a claim that the redesign has already passed. Final native renders and test outcomes should be linked here after implementation.

### Final native render review — 0.4.1 (49)

Reviewed 40 offscreen snapshots of the actual production views against the final Release module `d30478ba15e5be2d38de1017942d26fb507e2645d0316ddb0c5189ad4f0898e3`. Compact and wide board content uses 380 and 720 points; robot-frame renders include their existing reserved outer insets. Both appearances are covered. Fixtures use a temporary local store and injected settings, and never read or write the user's clipboard, archive, or standard preferences.

The full local evidence is in the ignored `native/build/qa/buddy-redesign/` directory: `buddy-redesign-renders.json`, `contact-light.jpg`, `contact-dark.jpg`, and the full-resolution PNGs. The tracked QA bundle preserves the complete manifest and four representative PNGs. Generate the full set with `native/scripts/render_qa.sh --buddy-redesign`, or compile the fixture with `@testable import DaBinTestCore` against the existing QA module to avoid rebuilding production sources.

Confirmed visually:

- The Library media preview is substantially larger and fits the full reference image. Expanded detail gives the image the main content region at both widths.
- Filters use aligned, consistently sized purple symbols. Card action rails, compact source badges, and title metadata are legible in both appearances.
- The task workspace is expanded and its two attachments are visible immediately. The note attachment displays actual saved text rather than an empty generic thumbnail.
- The 64-point clock, Countdown/Date controls, hour/minute fields, and native date/time editor fit at 380 points. Save and footer controls remain reachable; scrolled content stays below the header.
- Native created tasks now use a compact “Created in DaBin” label. Converted captures retain source provenance. Safari and Preview badges show their actual locally installed app icons.
- The completed task has a clear green completion marker and changed task heading. Confirmation motion itself is covered by state/window tests, not still images.
- The robot frame is thin, with its face, arms, and feet outside content. Light and dark appearance both propagate through the nested AppKit frame.

Two issues found by this independent review were corrected and rendered again:

1. The initial nested robot frame ignored the light preference and remained Dark Aqua. The production `CornerController.applyBoardAppearance` bridge now updates native window, frame, and hosting appearance. Final renderer assertions verify that the host/window match the requested appearance in all four frame snapshots.
2. Manually created tasks had a large “Unknown source” panel. Their new compact creation badge removes unnecessary visual weight and moves attachments upward.

Verification for the tooltip foundation: `ThemeSettingsTests` passed **177 checks**, including five added preference checks for default-on, live storage, relaunch, re-enabling, and malformed stored values. The final native renderer compiled with warnings treated as errors and completed **40/40 snapshots**.

Limits: these are native-view renders at one pixel per point, not a screen recording or interactive QA session. The Mac was locked during review. Mouse resizing, actual hover tooltips, keyboard/VoiceOver navigation, and animation feel still require the unlocked-session checks reported by the main QA run; this document does not claim those checks from screenshots. The fixtures deliberately use image and text previews, so they do not claim PDFKit tile rendering coverage.
