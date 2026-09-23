# DaBin — micro-widget design notes

> **Superseded historical reference.** Follow [OPEN_DESIGN_HANDOFF.md](../OPEN_DESIGN_HANDOFF.md): DaBin is hidden at rest, reveals a purple robot at any screen corner, and captures drops/pastes directly into that robot with a digest animation. There is no separate capture area or composer. The code, screenshots, dimensions, and verification below describe an earlier rejected design; they do not implement or verify the new corner behavior.

## Direction and provenance

DaBin is a personal record of what someone worked on each day. Its persistent presence is only an edge-docked purple metal robot bin, targeting **52 × 64 CSS pixels**. The robot is still recognizable by its lid, mouth, and eyes, but it has no visible plus, count, or compact control. The shell remains the drop target. A single click opens a paste composer; a double-click opens Daily without first flashing the composer. All seeded content is fictional.

Open Design generated the initial redesign in project `dabin-purple-robot-redesign` using `PRODUCT_PLAN.md`, `CODEX_DESIGN_HANDOFF.md`, and the earlier `design/` prototype as references. This workspace copy reflects subsequent requests for a smaller interface, per-capture actions, and contextual search. CSS pixels approximate macOS points; a native build must adapt to display scale and accessibility settings.

## Surfaces

| Surface | Design |
| --- | --- |
| Robot | Docked at a screen edge, about 52 × 64 CSS pixels at rest. The body accepts drops and retains a compact metallic-purple bin silhouette. No persistent action buttons or number badge. |
| Paste composer | Small, on-demand input anchored to the robot. It opens on a single click; keyboard paste and drag/drop remain direct capture routes. |
| Daily | On-demand popover about 336 px wide and no more than 410 px tall. One dense header row contains date navigation, search, reminders, and close; type filters sit immediately below. Captures scroll inside the popover. There is no sidebar, date rail, or wallpaper. |
| Capture | A compact row with a 44 px preview, title/source/time, and visible **Comment** and **Reminder** actions. The card can open detail for a larger preview and editing. |
| Detail and reminders | Replace the capture list inside the same popover. Reminders stay attached to captures rather than becoming assigned tasks. |

The small size depends on restraint: one neutral panel surface, no nested card frames by default, no decorative dashboard, and no permanent guidance text. Captured content supplies most of the color. The popover can shrink when a day has little content but must stay usable with longer titles, keyboard focus, and larger text.

Seeded links demonstrate rich preview cards. Newly pasted URLs use a domain/URL fallback without a network request. Dropped images can preview during the browser session. Video, PDF, document, `.ai`, text, and unknown files use type-specific fallbacks when a thumbnail is unavailable. A missing preview does not imply failed capture.

## Search in Daily

Search compares the query with a capture's title, description, source, original text or URL, comment, and type. Matching is case and accent insensitive. The selected Links / Files / Media filter determines which captures can **match**; neighboring context may be another type.

Results are grouped by capture date, newest date first, and **only dates with matches appear**. Within a date, captures stay in their original order. Each match brings the one capture immediately before and the one immediately after it **on that date**. Overlapping windows are deduplicated, while matches remain visually distinct from context. Opening a date shows its full Daily view. Clearing the query returns to the selected day. Search never changes a capture's recorded date.

## Capture and reminder behavior

1. A valid drop or paste creates one capture per transferable item on the local day at capture time. The browser prototype models this in memory. Production should commit the original and timestamp before preview work.
2. Saving is confirmed in words and with a short robot digest. Reduced Motion replaces movement with static status. Empty or unreadable input does not receive success feedback.
3. **View** after capture opens the item's original day and highlights it. Browsing dates and filters does not move saved captures.
4. Each capture exposes **Comment** and **Reminder** directly in Daily. Both are optional and independent. Clearing a reminder leaves the capture and its date intact. There are no assignees, statuses, or required deadlines.

## Native implementation recommendations

- Keep a single edge-docked robot visible on the active display where macOS permits. Remember its display and edge position, recover from disconnected monitors, and offer a shortcut or menu bar route if a full-screen app hides it.
- Preserve the compact target while respecting minimum accessible hit areas. Enlarge the invisible pointer target or provide keyboard alternatives instead of adding always-visible controls to the shell.
- Store the original URL, text, or copied file with an immutable UTC timestamp, capture-zone ID, and capture-local date. Group by that original local date even after travel.
- Fetch link metadata only with a clear privacy control. A disabled or failed fetch still leaves a useful URL card.
- Attach local notifications to reminder values. Denied notification permission must not erase a reminder.
- Provide a file picker for people who cannot drag content. Do not report success when a source app exposes no transferable representation.

## Review scenarios

1. Inspect the 52 × 64 robot at a screen edge. Confirm its shell is usable as a drop target and that there are no visible plus, count, or compact controls. Try single-click, double-click, paste, and drop.
2. Open the Daily popover and inspect its width, maximum height, one-row header, filters, 44 px previews, and scrolling list. Confirm it has no sidebar or wallpaper.
3. Browse dates and filter All, Links, Files, and Media. Confirm every capture has Comment and Reminder actions and remains on its capture day.
4. Search on one day and across several days. Confirm unmatched dates disappear; each match has at most one immediate same-day capture before and after it; overlapping context is shown once.
5. Edit a comment and reminder, clear a reminder, and return from detail. Check narrow width, dark appearance, Reduced Motion, and keyboard navigation.

This remains a browser design prototype. Dropped originals use session-only blob links; the prototype does not persist captures after reload, contact a link-preview service, or schedule OS notifications. Fictional seeded links remain disabled.
