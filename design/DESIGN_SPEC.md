# DaBin — macOS micro-widget design specification

> **Superseded historical reference.** Follow [OPEN_DESIGN_HANDOFF.md](../OPEN_DESIGN_HANDOFF.md): DaBin is hidden at rest, reveals a purple robot at any screen corner, and captures drops/pastes directly into that robot with a digest animation. There is no separate capture area or composer. The code, screenshots, dimensions, and verification below describe an earlier rejected design; they do not implement or verify the new corner behavior.

## Product and visual intent

DaBin is a personal record of what someone worked on each day. Anything readable that is dragged or pasted into its floating purple metal robot bin becomes a capture on that day's board. Captures can carry an optional comment or reminder. The interface does not use assignees, completion states, or required deadlines.

The persistent surface should feel like a tiny crafted object at the edge of the screen. At rest, **only the robot is visible**: no badge, plus button, compact toggle, toolbar, panel, or desktop backdrop. Its lid, eyes, and intake remain legible at small size. The Daily board appears only when requested and should feel like a concise macOS popover rather than a second workspace.

## Window model and size targets

The browser design uses CSS pixels as approximations of macOS points. Native implementation must adapt to display scale, text size, safe areas, and pointer accessibility.

| Surface | Target | Behavior |
| --- | --- | --- |
| Robot at rest | **52 × 64 px** | Edge-docked, movable purple metal bin; whole body accepts drops. No persistent auxiliary controls or count. |
| Paste composer | About 260–280 px wide | Appears beside the robot on a single click, then closes after capture or dismissal. |
| Daily popover | **About 336 px wide; at most 410 px tall** | Opens on double-click or keyboard command. Anchors near the robot and flips inward when near a screen edge. Height follows content until the cap; the capture list then scrolls. |
| Detail and Reminders | Within the same popover | Replace the Daily list rather than opening another large window. |

The robot docks to the nearest practical screen edge and remains inside the visible area. A small top rim can be used for repositioning while the body stays a reliable drop target; keyboard repositioning should also be available. A double-click must not flash the single-click composer first. The browser canvas behind the surfaces is transparent and contains no simulated wallpaper or side menu.

**Future native implementation:** keep one robot on the active display where macOS permits, remember its display and edge position, and recover it after a monitor disconnect. Offer a configurable shortcut or menu bar route when a full-screen app covers it. Do not duplicate it on every monitor.

## Robot and capture feedback

The 52 × 64 px robot uses a simple lid, dark intake, two restrained eyes, purple metal shell, and short grounded shadow. Keep the silhouette readable without large highlights, gradients, or mascot features. Do not reserve room for helper labels in the resting state. A brief hover hint can explain single-click to paste and double-click for Daily without changing the widget's size.

- **Single-click:** open the small paste composer. Return saves; Shift+Return adds a line. Pasting files or text directly while the robot has focus captures them without opening a duplicate composer.
- **Double-click:** open or focus Daily without first displaying the composer.
- **Drag hover:** subtly lift the lid and brighten the eyes; keep the drop target stationary. A short nearby release hint may appear during the drag only.
- **Successful capture:** save the original representation and capture timestamp first, then show a short digest motion and text confirmation. Multiple readable items create separate captures with one batch confirmation. A View action opens the original capture day and highlights the new item.
- **Failure:** empty paste or unreadable drag receives a plain-language message, with no success animation. Partial batches report saved and unreadable counts separately.

Reduced Motion replaces the digest movement with a static status. The animation never delays saving and is never the sole confirmation. The browser prototype models capture in memory; native code must confirm only after durable storage succeeds.

## Daily popover layout

Daily uses one compact surface and two persistent control rows:

1. **Header:** previous day, concise date, next day, search affordance, reminders affordance, and close. Search can expand into an input in the header while keeping the popover width fixed. Icon controls need accessible names and tooltips.
2. **Filter row:** All, Links, Files, Media. The active filter is visibly selected and exposed to assistive technology.

Below the controls, a single capture list scrolls within the 410 px height cap. There is no sidebar, date rail, dashboard, or outer background. Daily opens on Today. The date control can select another day; navigation never changes a capture's stored date. Following View from a newly saved item selects that item's day and All, then highlights it. The active filter otherwise remains selected while browsing.

Cards are compact, largely unboxed rows. Each has a **44 px preview/type tile**, title, source or short description, capture time, and explicit **Comment** and **Reminder** actions. These actions open the relevant field in detail. Clicking the main row opens a larger preview and metadata; Open original is separate. The list should remain scannable with long names truncated in rows and available in full in detail or accessibility text.

| Filter | Contents |
| --- | --- |
| All | Every capture, including text and unknown readable representations. |
| Links | Captured URLs, even if a remote preview is unavailable. |
| Files | PDFs, documents, presentations, `.ai`, archives, and other non-media files. |
| Media | Images and videos, including those without thumbnails. |

An empty day says “Nothing captured on this day.” An empty filtered day names the active filter and offers All. Date and filter controls remain available. A long day scrolls beneath the compact header and filters.

## Search with capture context

Search compares the query with title, description, source, original text or URL, comment, and type. Matching is case and accent insensitive. The selected type filter determines which captures can **match**; their neighbors may be another type.

Results show **only dates containing a match**, newest date first. Under each date, show each matching capture with the immediately preceding and following capture **from that same day**. Keep the original capture order and deduplicate overlapping windows. Matches are visually distinct from neighboring context. A date action opens the complete Daily view for that date. Clearing search returns to the previously selected day. Search never moves a capture or changes its date.

When several dates match, each date group is compact and clearly labeled. The list scrolls inside the same 336 × 410 px popover; search does not open a larger results window or add a side column.

## Preview and detail behavior

Link cards use page title, domain, and image when available. Without metadata, a readable URL/domain card remains. Image and video captures use thumbnails when possible. PDF, document, `.ai`, text, and unknown readable files use recognizable type tiles and filename fallbacks. A failed preview does not imply failed capture; title and timestamp remain visible.

Detail replaces the list inside the same popover. It shows a back route, larger preview, title, type, original capture date/time, description, and Open original. Two independent sections provide an editable comment and reminder date/time. Saving an empty comment clears it. Clearing a reminder does not delete the capture or alter its day. The Reminders view lists captures with reminders and returns to their detail.

**Future native implementation:** store the original URL, text, or copied file with immutable UTC time, capture-zone ID, and original capture-local date. Keep grouping by that date after travel. Fetch link metadata behind a clear privacy control; disabling or failing retrieval leaves the URL card intact. Local notifications should use the reminder value; denied permission must not erase it. Provide a file picker for people who cannot drag content.

## Accessibility and visual tokens

The tiny shell needs a usable effective pointer area without adding always-visible chrome. Keep keyboard capture, a keyboard route to Daily, visible focus, and a file-picker route in the native app. Give the date, search, reminders, close, filters, and per-card actions clear accessible names. Announce saved and failed captures in words. Respect light/dark appearance, Increase Contrast, Reduce Transparency, Reduced Motion, and larger text; allow the popover to grow within the available screen when accessibility size requires it.

Use SF Pro and SF Symbols for the panel. Let captured thumbnails supply most of its color. Purple identifies the robot and small active accents; the popover uses a quiet neutral surface. A 4 pt spacing system and restrained 10–13 px row typography suit the compact target. Avoid nested card boxes, oversized headings, decorative gradients, and persistent instructions.

## Prototype acceptance criteria

1. At rest, only an edge-docked purple robot about 52 × 64 px is visible. It remains a usable drop target. No plus, count, compact toggle, sidebar, or simulated desktop backdrop is visible.
2. Single-click opens the paste composer; double-click opens Daily without composer flicker. Valid drops and pastes create demo captures with clear confirmation. Empty or unreadable input reports failure.
3. Daily targets 336 px width and a 410 px height cap. One header row contains date navigation, search, reminders, and close; the filter row sits beneath it. The capture list scrolls inside the popover.
4. Every capture shows a 44 px preview/type tile and visible Comment and Reminder actions. Each opens the relevant detail field. Comment and reminder changes leave the capture date intact.
5. All, Links, Files, and Media filters work; empty day and empty filter messages differ. View after saving opens the original day, selects All, and highlights the capture.
6. Search shows only matching dates with one immediately preceding and following same-day capture per match, deduplicated and kept in capture order. Clearing search returns to the selected day.
7. Link, image, video, PDF, `.ai`, text, and generic file examples have readable fallbacks. The browser prototype makes no remote metadata requests or uploads.
8. Keyboard access, focus, Reduced Motion, light and dark appearances, and non-animated status remain usable. Demo captures, comments, and reminders are session-only; native floating-window behavior, durable storage, opening originals, and OS notifications remain future work.
