# DaBin — handoff to Open Design

## Assignment

Create a **new visual and interaction design** for DaBin, a personal macOS daily capture tool. The user has rejected the current redesign even after it was reduced to a 52 × 64 px robot and an approximately 344 × 410 px Daily popover: **“It still takes too much space and [is] not designed well.”** Treat that as feedback on the *design direction*, not a request to scale the same interface down again.

The user's latest direction is now fixed: **DaBin is completely hidden at rest. Moving the cursor into any screen corner reveals the purple robot peeping into the screen. All drops and pastes go directly into the robot, which gives a small digest animation. There is no separate drop zone, paste area, composer, or text-entry popup.** Explore different visual treatments and motion within this behavior, then select and develop the strongest direction. Show actual-scale desktop mockups and close-ups.

Create a **new Open Design project named “DaBin — spatial redesign”**. Write the selected design to a new folder, `DaBin/open-design-v2/`, so the user can compare it with the current prototype. Do not overwrite `DaBin/opendesign-redesign/` or `DaBin/design/`.

## Product in one paragraph

DaBin is a hidden personal macOS capture tool. At a screen corner, a little metallic purple robot bin peeks into view and receives content directly through drag or paste. It briefly looks as though it is digesting what it received. Each capture is saved under the **local calendar day when it entered DaBin**. Double-clicking the revealed robot opens Daily, where the person revisits that date's links, files, media, and thoughts. Every card can have an optional **Comment** and **Reminder**. There are no assignees or task-completion states.

## Corner reveal and direct capture — highest priority

| State | Required behavior |
| --- | --- |
| Hidden | No robot, tab, badge, panel, visible hotspot, or decorative background occupies the screen. The app runs in the background. |
| Corner entry | Any of the four screen corners can reveal the robot. It peeks inward from the active corner with its purple metal body, eyes, and intake recognizable. Reveal one robot at the active corner. |
| Carrying a drag | Reaching a corner while dragging content must also reveal the robot, without releasing the item. The user can continue directly onto its body and drop. |
| Interacting | Keep the robot revealed while the pointer moves from the corner onto its body and while a drag, explicit paste, or capture is in progress. Avoid flicker or retreat beneath the pointer. |
| Direct paste | The revealed robot itself receives an explicit paste command, such as Cmd+V while targeted/focused. A click may focus it; it does not open a composer or text field. Hover reveals the robot without reading the clipboard or taking content automatically. Resolve focus clearly so paste reaches DaBin. |
| Digest | On a successful drop or paste, perform a brief ingestion reaction: an item disappears into the intake, a small chew/lid/body motion, then a settled expression. The actual save must not wait for the animation. Use static confirmation under Reduced Motion; never play success for unreadable input. |
| Retreat | When the pointer leaves the corner and robot, retract after any active capture/digest finishes. Return to zero visible presence; do not strand a permanent docked robot. Propose a short exit grace period if needed to make movement forgiving. |
| Open Daily | Double-click the revealed robot to open Daily. Keep the explicitly opened board usable as the pointer moves into it; dismissing it returns to the hidden/corner-reveal model. This continuity is an interaction baseline to validate, not a reason to keep the robot permanently visible. |

Choose sensible corner activation regions and reveal/retreat timing. Test all four corners and the path from the corner onto the robot. Account for native macOS corner gestures, multiple displays, and keyboard accessibility in the design notes. These should support the hidden default rather than add persistent desktop chrome.

## Required behavior

1. **Capture:** Accept pasted or dragged URLs, text, images, videos, PDFs, documents, presentations, `.ai` files, and other readable transferable representations directly into the robot. Multiple dropped items become separate captures. A successful capture gets brief digest feedback and a clear route to the new card. If the source provides no readable data, show a plain failure message near the revealed robot. Do not add a separate drop/paste surface.
2. **Corner robot:** Keep the purple metal robot-bin identity at actual desktop scale. Follow the hidden, corner-peek, direct-capture, digest, and retreat states above. **Double-click opens Daily.** The former always-visible, freely parked widget and single-click paste composer are superseded by this corner interaction. Provide an accessible keyboard route without introducing a permanent panel.
3. **Daily:** Open on Today. Browse previous/next dates and pick a date. Show captures in time order with usable previews and capture times. Filters are **All, Links, Files, Media**. Files includes PDFs, documents, `.ai`, and other non-media files; Media includes images and videos. All includes text and unknown types. An empty day and an empty filtered result need clear, distinct states.
4. **Cards and originals:** A URL should become a link card with page title, domain, description, and image when available; preview failure still leaves a readable URL and open-original action. Show thumbnails/posters/first pages for media and documents when available. Keep a clear type-specific fallback when unavailable. The capture must remain useful even when preview extraction fails.
5. **Comment and Reminder:** Put a visible **Comment** and **Reminder** action on every capture in Daily and search results. They are optional. Editing either one must leave the capture on its original day. Reminders have a date/time and a way to clear them. A secondary reminder view may be compact, but should return to the original capture.
6. **Search:** Search across capture days. Results show **only dates containing a query match**. For every matching capture, also show the immediate capture before and after it **on the same day**, if present. Deduplicate overlapping context and distinguish matches from neighboring context. A date appears once per group; avoid a redundant date strip. The Links/Files/Media filter may limit eligible matches, while neighboring context can be another type. Opening a result keeps its capture date clear.

Capture time is immutable. A reminder date, a suggested project, or a tag never moves a card to another Daily date. Projects/tags may be suggested quietly later; neither is required to capture or browse. **Do not add assignees, completion states, required deadlines, or project-management chrome.**

## Visual problem to solve

- The previous browser prototype is at [opendesign-redesign/index.html](./opendesign-redesign/index.html). Review its [robot](./opendesign-redesign/previews/robot-closeup.png), [Daily close-up](./opendesign-redesign/previews/daily-closeup.png), [actual-scale Daily screen](./opendesign-redesign/previews/daily.png), and [search](./opendesign-redesign/previews/search-closeup.png) for reference.
- Those files are **rejected visual examples with obsolete capture behavior**. Their always-visible robot, single-click composer, and [paste popup screenshot](./opendesign-redesign/previews/composer.png) must not be recreated. The previous dimensions are not targets for the new design. Daily/filter/comment/reminder/search code may be useful as behavioral reference.
- Seek a calm, distinctive macOS design with a clear hierarchy at normal viewing distance. Minimize permanent screen obstruction, repeated controls, nested boxes, wallpaper, sidebars, and decorative background. A restrained surface behind open content is fine when needed for legibility.
- The visible footprint **at rest is zero**. Design the corner reveal, usable robot drop target, digest, retreat, and intentionally opened Daily view. Do not solve footprint only by shrinking text or click targets.
- Keep the robot crafted and metallic purple without turning it into a large mascot. Give captured content more visual prominence than application chrome. Support light/dark appearance, keyboard focus, accessible labels, and Reduced Motion.

## Design process and deliverables

1. Show **two or three visual concepts within the fixed hidden/corner-peek interaction**. Each should include a hidden desktop, a robot peeking from a corner, direct capture/digest, and an open Daily state at actual scale. Select one direction and explain why.
2. Build a **clickable local prototype** in `DaBin/open-design-v2/` using fictional sample data. Exercise reveal at all four corners, reveal during an active drag, direct drop and paste into the robot, digest and retreat, double-click Daily, date navigation, all four filters, card detail, comments, reminders, and contextual search. No separate paste-entry surface is allowed. A backend or account is not needed for this design pass.
3. Produce review screens and a short interaction recording or motion sequence for hidden → corner peek → direct drop/paste → digest → retreat. Show all four corner placements. Also cover capture failure, populated/empty Daily, filters, URL preview/fallback, media/file fallback, search with one and several matching dates, detail/comment/reminder, dark mode, and narrow display. Include actual-scale desktop screenshots and close-ups. Label browser viewport corner simulation separately from native screen-corner behavior.
4. Add concise design notes: typography, color, spacing, states, keyboard behavior, minimum hit areas, proposed dimensions/footprint, and why the solution uses less attention than the current one. Identify any interaction that needs native macOS validation.
5. Run local browser QA on the prototype and record what was checked. Link the entry point and the most useful screenshots in the final Open Design response.

## Acceptance checks

- The resting desktop contains no visible DaBin UI. Reaching any screen corner reveals a peeping robot, including while dragging content.
- Pointer movement from a corner onto the robot keeps it visible. Drops and explicit pastes go directly into the robot, without opening a separate area, composer, text field, or capture panel.
- Successful capture produces a short digest reaction. After interaction completes and the pointer leaves, the robot retreats. Double-click opens a usable Daily view.
- The Daily view makes a day's work scannable without a full app window or dense, tiny text.
- A user can identify a link, image/video, PDF/document, and fallback file at a glance.
- Every capture has a Comment and Reminder action. No assignment or task-completion UI appears.
- Search renders only matching dates and includes at most the immediate same-day item before and after each hit, without duplicate context.
- The design has no sidebar or simulated desktop background. Its open surfaces are content-sized where practical.
- Mockups show actual desktop footprint alongside detail views, so the user can judge space use rather than seeing only cropped artwork.

## Source and precedence

This handoff and the latest user correction take precedence. Use the updated [PRODUCT_PLAN.md](./PRODUCT_PLAN.md) for the underlying capture model. [CODEX_DESIGN_HANDOFF.md](./CODEX_DESIGN_HANDOFF.md), the earlier design specifications, prototype code, screenshots, and QA records are historical: any permanent visible robot, movable resting widget, paste composer, add area, or optional-search language in them is superseded. The existing prototype has not been updated to implement corner reveal. Keep sample data fictional and work only with this repository.

The existing browser prototype is session-only: it does not provide native floating windows, durable capture/file storage, live link metadata, or OS notifications. Those are **future app requirements**, not features to pretend are complete in this design pass.

## Prompt to send to Open Design

> Redesign DaBin from `DaBin/OPEN_DESIGN_HANDOFF.md`. The app is completely hidden at rest. When the cursor reaches any of the four screen corners, one metallic purple robot peeks inward, including when the user is carrying a drag. Drop or paste content directly into that robot; it performs a little digest animation after a successful capture and retreats when interaction finishes and the pointer leaves. There is no separate drop zone, paste area, composer, text box, add button, or permanent desktop widget. Double-click the revealed robot to open Daily. Explore visual treatments within this fixed interaction, then build the selected clickable design under `DaBin/open-design-v2/`. Retain immutable capture dates, All/Links/Files/Media filters, rich preview/fallback cards, per-card Comment and Reminder, and search showing only matching dates with one immediate same-day capture before and after each hit. The included prototypes are rejected references with obsolete capture behavior. Use fictional content, show actual-scale corner/reveal/digest/retreat and Daily states, verify interactions locally, and link the finished files and screenshots.
