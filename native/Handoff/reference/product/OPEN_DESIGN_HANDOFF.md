# DaBin — handoff to Open Design

## Assignment

Create a **new visual and interaction design** for DaBin, a personal macOS daily capture tool. The user has rejected the current redesign even after it was reduced to a 52 × 64 px robot and an approximately 344 × 410 px Daily popover: **“It still takes too much space and [is] not designed well.”** Treat that as feedback on the *design direction*, not a request to scale the same interface down again.

Explore at least two materially different ways for DaBin to remain available on screen with very little visual obstruction. Select and develop the strongest direction. A slim edge-docked resting state, a temporarily expanding drop target, or another spatial model are open for exploration. Preserve a usable drag target and readable Daily content. Explain the tradeoffs with full-screen, actual-scale mockups, not only cropped close-ups.

Create a **new Open Design project named “DaBin — spatial redesign”**. Write the selected design to a new folder, `DaBin/open-design-v2/`, so the user can compare it with the current prototype. Do not overwrite `DaBin/opendesign-redesign/` or `DaBin/design/`.

## Product in one paragraph

DaBin is a tiny metallic purple robot bin that receives anything transferable by drag or paste while a person works. Each capture is saved under the **local calendar day when it entered DaBin**. Opening Daily lets the person revisit that date's links, files, media, and thoughts as visual cards. Every card can have an optional **Comment** and **Reminder**. It is a personal record of a day, not a team task manager.

## Required behavior

1. **Capture:** Accept pasted or dragged URLs, text, images, videos, PDFs, documents, presentations, `.ai` files, and other readable transferable representations. Multiple dropped items become separate captures. A successful capture gets brief digest feedback and a clear route to the new card. If the source provides no readable data, show a plain failure message.
2. **Floating robot:** Keep the purple metal robot-bin identity, recognizably a bin at actual desktop scale. The user can move it. Its body is the drop target. Single-click or a clear keyboard route opens paste entry; **double-click opens Daily without flashing the paste composer first**. Design idle, hover, drag target, saving, success, and failure states. Its resting presence should feel materially less obstructive than the rejected prototype.
3. **Daily:** Open on Today. Browse previous/next dates and pick a date. Show captures in time order with usable previews and capture times. Filters are **All, Links, Files, Media**. Files includes PDFs, documents, `.ai`, and other non-media files; Media includes images and videos. All includes text and unknown types. An empty day and an empty filtered result need clear, distinct states.
4. **Cards and originals:** A URL should become a link card with page title, domain, description, and image when available; preview failure still leaves a readable URL and open-original action. Show thumbnails/posters/first pages for media and documents when available. Keep a clear type-specific fallback when unavailable. The capture must remain useful even when preview extraction fails.
5. **Comment and Reminder:** Put a visible **Comment** and **Reminder** action on every capture in Daily and search results. They are optional. Editing either one must leave the capture on its original day. Reminders have a date/time and a way to clear them. A secondary reminder view may be compact, but should return to the original capture.
6. **Search:** Search across capture days. Results show **only dates containing a query match**. For every matching capture, also show the immediate capture before and after it **on the same day**, if present. Deduplicate overlapping context and distinguish matches from neighboring context. A date appears once per group; avoid a redundant date strip. The Links/Files/Media filter may limit eligible matches, while neighboring context can be another type. Opening a result keeps its capture date clear.

Capture time is immutable. A reminder date, a suggested project, or a tag never moves a card to another Daily date. Projects/tags may be suggested quietly later; neither is required to capture or browse. **Do not add assignees, completion states, required deadlines, or project-management chrome.**

## Visual problem to solve

- The current browser prototype is at [opendesign-redesign/index.html](./opendesign-redesign/index.html). Review its [robot](./opendesign-redesign/previews/robot-closeup.png), [actual-scale resting screen](./opendesign-redesign/previews/robot.png), [Daily close-up](./opendesign-redesign/previews/daily-closeup.png), [actual-scale Daily screen](./opendesign-redesign/previews/daily.png), [search](./opendesign-redesign/previews/search-closeup.png), and [paste entry](./opendesign-redesign/previews/composer.png).
- Those files are **functional references and rejected visual examples**, not a template. The current small robot and dense popover already failed the user's spatial and aesthetic test. Do not preserve their dimensions, CSS, header, card layout, or placement merely because they work.
- Seek a calm, distinctive macOS design with a clear hierarchy at normal viewing distance. Minimize permanent screen obstruction, repeated controls, nested boxes, wallpaper, sidebars, and decorative background. A restrained surface behind open content is fine when needed for legibility.
- Design the visible footprint **at rest, during drag, and when Daily is open**. Show how a very quiet resting state remains discoverable and how a small capture target stays usable. Do not solve footprint only by shrinking text or click targets.
- Keep the robot crafted and metallic purple without turning it into a large mascot. Give captured content more visual prominence than application chrome. Support light/dark appearance, keyboard focus, accessible labels, and Reduced Motion.

## Design process and deliverables

1. Show **two or three genuinely different concepts** at actual desktop scale. For each, include the resting robot, an active drag target, and an open Daily state, with approximate visible footprint and one sentence on the tradeoff. Choose one direction and explain why.
2. Build a **clickable local prototype** in `DaBin/open-design-v2/` using fictional sample data. Exercise single-click paste, double-click Daily, drag/paste feedback, date navigation, all four filters, card detail, comments, reminders, and contextual search. A backend or account is not needed for this design pass.
3. Produce review screens for resting, hover/drop, paste, saving/success/failure, populated Daily, empty Daily, filter result, URL preview/fallback, media/file fallback, search with one and several matching dates, detail/comment/reminder, dark mode, and narrow display. Include both actual-scale desktop screenshots and close-ups.
4. Add concise design notes: typography, color, spacing, states, keyboard behavior, minimum hit areas, proposed dimensions/footprint, and why the solution uses less attention than the current one. Identify any interaction that needs native macOS validation.
5. Run local browser QA on the prototype and record what was checked. Link the entry point and the most useful screenshots in the final Open Design response.

## Acceptance checks

- The resting state occupies very little attention **and** remains recognizable as DaBin and usable for a drop or paste.
- The Daily view makes a day's work scannable without a full app window or dense, tiny text.
- A user can identify a link, image/video, PDF/document, and fallback file at a glance.
- Every capture has a Comment and Reminder action. No assignment or task-completion UI appears.
- Search renders only matching dates and includes at most the immediate same-day item before and after each hit, without duplicate context.
- The design has no sidebar or simulated desktop background. Its open surfaces are content-sized where practical.
- Mockups show actual desktop footprint alongside detail views, so the user can judge space use rather than seeing only cropped artwork.

## Source and precedence

Use [PRODUCT_PLAN.md](./PRODUCT_PLAN.md) for the underlying data and capture model. Its older screen-state language about a permanent add button/count and its P1 classification of search are superseded by this handoff and the user's later instructions. The older [CODEX_DESIGN_HANDOFF.md](./CODEX_DESIGN_HANDOFF.md) is historical and likewise does not make search optional. Use the current prototype only to inspect working interaction examples. Keep all sample data fictional and work only with this repository.

The existing browser prototype is session-only: it does not provide native floating windows, durable capture/file storage, live link metadata, or OS notifications. Those are **future app requirements**, not features to pretend are complete in this design pass.

## Prompt to send to Open Design

> Redesign DaBin from `DaBin/OPEN_DESIGN_HANDOFF.md`. The user rejected the current 52 × 64 robot and ~344 × 410 Daily popover as still too space-consuming and poorly designed. Treat `DaBin/opendesign-redesign/` as a functional reference and rejected visual example, not as a layout to shrink. Explore two or three substantially different minimal-presence macOS concepts, choose one, and build a polished clickable prototype under `DaBin/open-design-v2/`. Preserve the metallic purple robot bin, drag/paste capture, double-click Daily, immutable capture day, All/Links/Files/Media filters, rich preview/fallback cards, per-card Comment and Reminder, and contextual date search showing only matching dates with one same-day capture before and after each match. Use fictional content. Show actual-scale desktop footprint and close-ups, document design decisions, verify key interactions locally, and link the finished files and screenshots.
