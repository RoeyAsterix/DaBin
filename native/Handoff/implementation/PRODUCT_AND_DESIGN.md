# Product and native design contract

## Source authority

The user selected the v2 edge-bin direction and explicitly required **no sidebar**. `reference/prototype/` is the selected visual/interaction reference. The original product plan remains authoritative for the capture model; the newer source handoff makes contextual search required. Historical redesign exploration is complete.

Native decisions below fill gaps in the browser prototype. They are recommended implementation defaults, identified as such, rather than claims that the user has tested or approved native behavior.

## Product

“Drop it now. See your day later.” DaBin is a personal date-based capture archive. A capture stays on the day it entered the app. A comment is annotation; a reminder is an optional notification. Neither is a task, status or filing requirement.

MVP: bin, capture, Daily, contextual search, detail, comments, reminders, useful previews/fallbacks and reliable originals. Defer projects/tags, OCR, AI categorization, cloud accounts/sync, collaboration, OS widgets and automation integrations. Do not port the browser's optional WebMCP hooks. The bottom-tray concept is not a second app mode.

## Window model

Two reusable windows: the tiny bin plus one floating content panel. Daily, Capture, Search, Detail and Reminders are routes in that panel, not six separate simultaneous windows. The HTML files are separate review entrypoints, not a required one-to-one native-window mapping.

| Element | Selected prototype size | Native contract |
| --- | --- | --- |
| Resting robot artwork | 32 × 43 CSS px | Start at 32 × 43 pt; preserve proportions |
| Robot pointer target | 52 × 56 | Usable target around the artwork |
| Widget wrapper | 58 × 78 | Small transparent bin window; no full-screen overlay |
| Move handle | 44 × 18 | Separate, keyboard accessible; larger focus target is acceptable |
| Hover artwork | 39 × 50 | Brief reveal, no layout churn |
| Active drop receiver | 84 × 92 | Temporary expansion; collapse after drop/exit |
| Daily/Search/Detail/Reminders | 420 wide, at most 640 high | Readable, internally scrolling content panel |
| Capture | 400 wide | Same panel; width may change around a stable anchor |

Dimensions are logical points, not Retina pixels. Anchor the panel inward from the bin with a small gap. Clamp both windows to `NSScreen.visibleFrame`, including negative display coordinates and menu-bar/Dock insets. Recompute on display removal, display-scale change and window move. Choose the side with room; never put the panel beyond the screen to preserve a preferred edge. On unusually constrained work areas, reduce padding/width before text size; keep all controls reachable.

Recommended: one bin on its assigned display, visible across ordinary Spaces; test fullscreen behavior rather than promising it. Keep normal floating level, not screensaver/security-window level. No automatic duplicates on every monitor. Remember the display and edge-relative position; fall back to the main display when absent. The menu-bar action “Show DaBin” restores a recoverable on-screen position.

## Navigation and interaction

| Trigger | Result |
| --- | --- |
| Single click on bin | Open Capture after double-click discrimination; focus editor; do not read clipboard automatically |
| Double click | Cancel pending single click and open Daily/Today/All; never flash Capture |
| Drag handle | Move bin; do not invoke capture on release |
| Drop on body | Accept supported data; show saving, then success/partial failure/failure |
| Bin keyboard Enter/Space | Open Capture immediately |
| Bin keyboard Down | Open Daily immediately |
| Focused handle arrows / Shift+arrows | Move 5 / 25 pt within visible bounds |
| App-local Cmd+Shift+D / Cmd+K | Daily / Search; preserve normal text editing shortcuts |
| Escape | Close transient picker first, otherwise dismiss content panel and preserve draft |
| Close panel | Hide content panel only; bin stays available |
| Back from Detail | Restore origin route, day/query/filter and scroll position |

Use the operating system's double-click timing and cancel delayed actions on drag, route change and double click. A right-click/accessibility menu offers “Paste a capture” and “Open Daily” directly. Opening Capture means opening an editor; pasteboard reads happen after explicit Paste/Cmd+V. Successful saving has a short digest reaction and “Saved to [capture day]” plus “View capture.” A late-completing save across midnight must name the correct day.

The idle bin must not take typing focus away from another app. Explicitly opening text input must give the editor keyboard focus. Hover, drop and background preview updates must not activate a typing panel. Outside-click dismissal must not swallow the other application's click or lose unsaved input.

Recommended draft policy: keep capture/comment/reminder drafts when dismissed or routed away; explicit Save commits. Warn only before explicit discard or quitting with unsaved edits. Stored originals are independent of editor drafts.

## Screen contracts

### Daily

Header: Daily with quiet DaBin identity and compact Search/Reminders/Close controls. No sidebar. Date row: previous, selected date, next and Today. Disable future-day navigation. Filters: All, Links, Files, Media.

- Fresh bin/menu Daily invocation opens Today/All. While browsing, retain the filter through date changes. Back preserves previous state.
- Sort within a day oldest to newest by immutable timestamp, then ID for ties. Do not reorder after preview completion, comment edits or reminder changes.
- First visual capture gets the larger preview; other rows favor scanning. Names wrap; timestamps remain readable.
- Every card shows Comment and Reminder actions, including those without values.
- Empty day: “Nothing was captured on this date.” Empty filter: “No media on this day” with “Show all captures.” These are distinct from loading/error states.
- “View capture” after a save opens that exact item, even when the prior date/filter would hide it.

### Capture

Title, editable multiline text, Choose files and Save to today. Support native Paste, file selection and drops. Pasted text/URLs enter the editor until saved; explicit file paste/drop starts managed import immediately with progress. Whitespace-only text is invalid. A multiline string consisting entirely of HTTP(S) URLs produces separate link captures; mixed prose/URLs remains one text capture. Preview is never a save prerequisite.

For a batch, report how many items saved and which failed. Retry only failed items; never silently recapture the successful ones. Do not clear text on failure.

### Capture card and Detail

| Kind | Card/detail behavior |
| --- | --- |
| Link | Domain, title, description and image when available; readable original URL and Open original even without metadata |
| Text | Excerpt on card; full text and Copy text in Detail |
| Image | Thumbnail; full original available |
| Video | Poster and duration if known; native playback in Detail and Open original |
| PDF | First page and count when available; original still opens if thumbnail fails |
| Document / `.ai` | System-provided thumbnail if available; named type fallback otherwise |
| Generic file | Filename/type/size when known and original open action |

Detail shows the original capture date/time, large preview or fallback, source information, editable comment, optional reminder date/time, Clear reminder and Save changes. Activating Comment or Reminder focuses the relevant field. A clear reminder is a draft until Save; make that clear in status text. Large text/filenames wrap or scroll without pushing the original action out of reach.

Missing managed file: explain the problem; preserve its record/comment/day; disable or fail Open honestly. Do not manufacture a replacement original. File relocation at the original source should not cause this state because the app owns a copy.

### Search — required for MVP

Search title, description, original text/URL, original filename, comment, kind and stored local day (`YYYY-MM-DD`). Use case/diacritic-insensitive matching; all query words must match somewhere in a record. Empty query displays guidance, not the entire archive.

1. Find eligible hits after applying the selected type filter.
2. Group only days with at least one hit, newest day first.
3. In each day's full chronological capture list, include each hit and its immediate predecessor/successor when present.
4. Deduplicate by capture ID; render each day and each record once in chronological order.
5. Label actual hits “Match” and context-only rows “Nearby capture.” A hit always takes precedence over the neighbor label. Neighbors may be a different type.

Do not reach across midnight for a neighbor or add a second date strip. A hit at a boundary has only the existing same-day neighbor. See `search-cases.json` for executable expectations.

### Reminders

Keep reminders secondary. Upcoming entries sort by reminder time; past entries are visibly separate, without task checkboxes. Each opens Detail or its original Daily day. Saving a reminder requests notification permission in context, only if needed. Denial does not delete the reminder; show “Notifications are off” and a route to native settings. Scheduling failure must be visible and retryable.

Recommended timing: one nonrepeating absolute instant, with the chosen timezone stored. Reject past times for new/edited reminders. For DST gaps reject nonexistent local times; for repeated times show which offset will be used. A timezone change does not alter the scheduled instant. The archive day never changes. Overdue reminders remain reviewable; do not emit a burst of duplicate catch-up alerts after launch.

## Visual implementation

- Neutral near-white content, graphite text, muted metallic purple actions and robot. Preserve extracted light/dark tokens in `design-tokens.json`; use native dynamic colors mapped to those roles.
- SF system typography: title 23–25 pt, capture name 16–18, body 14–16, secondary metadata 12. Monospaced time digits. Use system font APIs, not bundled Apple font files.
- Spacing: 4/8/12/16/20 pt. Panel radius 19 pt; one hairline boundary and restrained shadow. Capture rows use dividers, not nested cards.
- Desktop header controls 36 pt; maintain comfortable targets for visible text actions. Small artwork does not mean small hit targets.
- Put captured content ahead of app chrome. No wallpaper simulation, marketing hero, saturated page gradients or settings embedded in the main board.
- Preserve `reference/prototype/assets/robot.svg` as the source asset. Convert to asset-catalog PDF/PNG if required by native rendering; keep the source and aspect ratio. Do not redraw the identity.
- Follow macOS appearance, contrast and Reduce Motion. Replace digest motion with a static saved check when motion is reduced. VoiceOver names/actions must distinguish move, capture, Daily, original, comment and reminder.

Compact native settings may expose link-preview opt-in and notification status. A menu-bar menu may provide Show DaBin, Capture, Daily, Search, Reminders, Settings and Quit. Global shortcuts and launch-at-login are optional later conveniences; neither blocks MVP nor changes the product's main navigation.
