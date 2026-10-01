# DaBin v3 design system

The visual identity comes from the supplied build-53 source. Canonical source palette is recorded in ../brand-spec.md. Editable component styles: tokens.css. Editable behavior: model.js, views.js, settings.js, interactions.js, events.js. Rebuild standalone screens with `python3 open-design-v3/build.py`.

## Product posture

A small native companion: capture quickly, optionally connect to a project, act, retrieve. No permanent sidebar, oversized mascot, account flow or invented cloud/AI service. This redesign preserves tasks and grouped files from the latest handoff.

## Tokens

| Role | Light | Dark |
|---|---|---|
| Canvas | #FDFCFE | #1D1C21 |
| Surface | #FFFFFF | #252328 |
| Foreground | #2B2731 | #EBEAED |
| Secondary | #615A69 | #A9A6AE |
| Hairline | #E3E0E6 | #3C3940 |
| Soft selection | #F3F1F5 | #2D2A30 |
| Default readable accent | #6D5387 | #AB92C6 |

Source presets: Purple #6D5387, Blue #386A9A, Teal #287875, Green #47763E, Rose #A34D73, Amber #956515. Custom source colors are mixed toward black/white until readable; never rewrite the chosen preference. Robot shell remains identity-purple. Semantic success, warning and error use labels and shapes as well as color.

Display: SF Pro Rounded / Avenir Next / native fallback. Body: SF Pro Text / Apple system. Numerics and receipt times: SF Mono / system mono. Sizes 11, 12, 14, 15/16, 18, 26/30. Body 1.5–1.65 line height. Compact body is 13–14px, secondary 11–12px. Headings use negative tracking, small labels positive tracking.

Spacing: 4/8/12/16/20/28/32. Cards 12px radius, inputs/buttons 8px, app shell 17px. Hairline card boundaries; shadows only for frame separation/dialogs. Keep visual accent concentrated on selected main navigation and the primary action. Metallic gradients belong only to the robot hardware.

## Component states

- Buttons: default, hover, pressed, focus-visible, disabled; icon-only controls have permanent accessible names and optional hover help. Desktop target 32–34px; coarse-pointer 44px.
- Tabs: selected text/shape and aria-current; repeated project context survives collection changes.
- Capture card: source/receipt, fitted original preview, copy, project, direct task conversion, Keep and secondary actions. Expanded/minimized preserves searchability.
- Task: a distinct bordered card with a square completion control, title, project, hours/minutes timer and calendar action. The editor uses icon priority controls, direct date choices, and compact repeat buttons.
- Grouped files: one container with individual member links; group copy is atomic native behavior.
- Hourly capture group: four or more successful automatic actions per local hour; collapse is distinct from deletion and retains position.
- Dialog: named title, native modal focus containment, Escape, backdrop dismissal and return focus.
- Empty state: specific recovery action; no fabricated content or statistics.
- Error: visible action-specific message, retained draft/record and retry path.

## Resizing contract

Native minimum 380×430 content / 400×480 outer. Frame reserves 10px sides, 32px head and 18px feet. Main chrome remains bounded; only content scrolls. Above 700px container width, preview grids and task details gain two columns. Below that, one readable list and stacked detail panes. At browser widths below 400, this reference gracefully fits the viewport; shipping native minimum remains unchanged. Compact/expanded share state. Browser drag/resize demonstrates the idea but does not prove AppKit geometry.

## Data and state boundaries

Fictional Northstar Studio and Mori fixtures only. Browser localStorage is a review mechanism under a project-specific namespace, not production storage. New files are retained as fixture data URLs with an explicit 8 MB per-file ceiling. Exported JSON is labeled a design fixture; native .dabinbackup has a separate verified contract. Native-only operations open labeled explanations instead of false success messages.

## Screen inventory

See screen-index.json and the root launcher. Every distinct route has its own standalone HTML file. Settings contains real product preferences, not designer viewport/theme controls. Robot motion controls belong to the explicitly labeled interaction study.

## Minimal-copy refinement

`refinement.css` is the final visual layer and is inlined by build.py into every screen. Page titles use short product names; redundant introductory sentences are omitted. Purple remains reserved for the active navigation indicator and primary action. Cards use 14px corners, 16px titles, two-line excerpts and larger fitted previews; tasks use distinct cards with time controls.

Robot is now a separate compact capture surface: click to paste, double-click for Inbox, file drop/import, editable capture, last saved item and Inbox link. Advanced motion/entry previews remain under the footer More menu. Native simulations stay explicitly labeled within their dialogs and specifications. All navigation and stored-data contracts remain intact.

## Task interaction refinement

`task-ui.js` and `task-ui.css` own task cards, focus timers, direct scheduling and icon controls. They are inlined into all screens after the baseline views/styles. Existing captures, stored drafts, source types, source files and original receipt dates are retained.

- Capture conversion happens in place; the same item becomes a task card. A brief transition and Undo confirm the change. Task detail opens only when requested (or when converting inside capture detail).
- Task cards always expose completion, duration, start/pause and schedule. Project selection uses named choices; priority uses accessible intensity icons. Main navigation retains labels for orientation.
- Focus sessions accept hours and minutes. The visible clock is HH:MM:SS; timestamp-based countdowns survive navigation and refresh. Expiry leaves the task open; task completion pauses its timer. Recurrences start without a copied timer.
- Workday plus optional time is a plan, independent of original receipt, deadline and reminder. Scheduling is not a notification request.
- Task title, steps, notes, priority, repeat and deadline retain explicit Save changes. Timer, schedule and project actions commit immediately, while preserving any other unsaved draft fields.
- Native minimum windows stack focus and schedule panels; shorter windows compress the task header/timer. Common icon targets are at least 32px on desktop and 44px on coarse pointers. Window geometry and scroll survive card updates.

See TASK_UX.md for implementation details and QA_REPORT.md for validation limits.

## Content provenance

Capture/task cards use a compact source-logo → destination-logo trail. Real local app marks identify products; names and individual paste timestamps are available on click. The direct + action records a destination without dropdowns. Unknown sources stay unknown, copying never implies pasting, and conversion preserves history. See CONTENT_TRAIL.md for the schema and native integration boundary.

## Shared project picker and viewport repairs

`project-picker.js` / `project-picker.css` own the searchable project switcher and inline creation across screens. `responsive.js` / `responsive.css` keep moved/resized frames and project panels inside the viewport, including after resizing. Project names appear in the Workspace and robot headers. Narrow forms stack and short dialogs scroll. See RESPONSIVE_QA.md for verification scope; rendered layouts remain unverified.
