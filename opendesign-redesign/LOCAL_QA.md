# Local browser verification

> **Superseded historical reference.** Follow [OPEN_DESIGN_HANDOFF.md](../OPEN_DESIGN_HANDOFF.md): DaBin is hidden at rest, reveals a purple robot at any screen corner, and captures drops/pastes directly into that robot with a digest animation. There is no separate capture area or composer. The code, screenshots, dimensions, and verification below describe an earlier rejected design; they do not implement or verify the new corner behavior.

Open Design produced the first redesign in project `dabin-purple-robot-redesign`. Its original [QA notes](./QA_NOTES.md) describe that generation pass. The files in this directory were copied from that output and then revised for the compact Daily panel and contextual search.

## Previously verified on the copied Open Design prototype

Headless Chromium verified single-click paste entry, double-click Daily, URL paste, text and `.txt` drops, type filters, date browsing, detail comment and reminder editing, compact robot, dark appearance, and a 390 px narrow view without horizontal overflow. That pass reported no page errors; the later revision replaced its preview PNGs.

## Verified on the compact revision

Local Playwright checks in headless Chromium confirmed:

- The Daily panel is 520 px wide at desktop size, with no side menu or simulated desktop background. The 390 px view has no horizontal overflow.
- Capture cards expose Comment and Reminder buttons. Each opens the corresponding detail field, and edited values save to the capture.
- Search shows only dates with matching captures. Results include the immediate preceding and following capture on the same date; a query matching captures on two dates produces two date groups. Type filters constrain matches, and **View day** returns to the full day.
- The Reminders header control, robot double-click to open Daily, pasted link capture, and compact robot mode work.
- Updated desktop Daily, robot, compact, dark, narrow, and search screenshots were captured in `previews/`. The browser reported no JavaScript page errors.

The prototype does not persist captures after reload, store dropped file bytes, fetch live URL metadata, or schedule system notifications.

## Verified on the earlier minimal-presence revision

That revision opened with only an 80 × 99 px robot near the lower screen edge. The browser canvas was transparent and the Daily panel stayed closed until opened. Hover revealed the paste and count controls; double-click opened the 440 px Daily panel. A dropped text item was captured by the smaller robot, and a pasted URL still created a card.

The same local Playwright pass rechecked Comment and Reminder actions, search dates and adjacent same-day captures, filters, date browsing, Reminders, compact mode, dark appearance, and the 390 px layout. Daily measured 440 × 540 px with six captures; a sparse search contracted to 440 × 443 px. It reported no JavaScript errors or horizontal overflow. Its compact screenshot is retained as `previews/legacy-compact.png`.

## Verified on the current micro-widget revision

Local Playwright measured a 52 × 64 px robot at rest on a transparent canvas, with no persistent badge controls. Single-click opened a composer under 280 × 190 px. Double-click opened a 344 × 410 px Daily popover; a sparse contextual search contracted it to 344 × 337 px. The search field stays collapsed until requested.

The pass verified single-click paste entry, a saved URL, a dropped text capture, date/type navigation, Comment and Reminder editing, reminder browsing, and search groups containing only matching dates with same-day neighboring captures. The 390 px layout had no horizontal overflow and the browser reported no JavaScript errors. Current screenshots include `robot.png`, `daily-closeup.png`, `search-closeup.png`, `composer.png`, `dark.png`, and `narrow.png`.
