# DaBin Open Design v3

Open ../index.html, then Open DaBin. Product screens are standalone HTML with inline styles/scripts; serve the folder through the project preview for consistent navigation, clipboard permissions and local asset ZIP export.

This is a browser design reference for the native macOS app. No native app was installed, built, published or modified. The supplied frozen source is preserved in ../source/.

- DESIGN.md: tokens, typography, layout and components.
- FEATURES.csv: all 80 preservation rows with locations/evidence/status.
- NAVIGATION_MAP.md: alternatives, old-to-new map and estimated interaction counts.
- IMPLEMENTATION_MAP.md: native owner for every feature.
- specs/FEATURE_CONTRACTS.md: complete feature state contracts.
- specs/ROBOT_MOTION.md: ten reactions, lifecycle, native placement and interruption.
- QA_REPORT.md and qa-results.json: performed checks, limits and remaining native gates.
- ../design-review.html: header comparison, component examples, current source references.

Editable sources: tokens.css, refinement.css, model.js, views.js, task-ui.js, task-ui.css, settings.js, interactions.js, events.js. Run `python3 open-design-v3/build.py` after edits. Root generated HTML files are delivery outputs. `verify.py` runs syntax, fixture behavior, route and markup checks using local JavaScriptCore; it does not render a browser.

## Local review flows

1. Inbox → capture a note → task icon → task card appears in place → set hours/minutes → Start or schedule → open task to edit steps.
2. Clipboard → Snippets → name/rename alias → Search → copy plain text.
3. Workspace → Shelf → filter Links → Export shelf; export still includes the full selected project shelf.
4. Notes → switch project → write → Save as note / Make task; scratchpad stays intact.
5. Task → reminder countdown → reopen; stored target time remains unchanged.
6. Capture → Recently Deleted → Undo or Restore; permanent deletion asks separately.

OS file promises, binary pasteboards, system notifications, native folder authorization, window/Spaces behavior, archive integrity and direct/Store updates require native implementation verification. Do not interpret a browser demonstration as completion of those gates.

## September 30 visual refinement

Shorter page titles, content-led cards, task cards with focus timers, quieter navigation, and a dedicated robot capture window. Robot motion and native entry previews are under the footer More menu. The editable final style layer is refinement.css. The original pre-refinement source snapshot is in ../revisions/dabin-before-refinement.zip (outside the delivery package).

Task interaction changes and native adoption notes: TASK_UX.md. Previous shared sources are preserved in ../revisions/dabin-before-task-cards.zip.

Content source and paste destination trail: CONTENT_TRAIL.md. Editable components: provenance.js and provenance.css. Real app icon originals and preview PNGs: assets/app-icons/. Existing captures are not backfilled with fictional paste events.
