# DaBin prototype QA

> **Superseded historical reference.** Follow [OPEN_DESIGN_HANDOFF.md](../OPEN_DESIGN_HANDOFF.md): DaBin is hidden at rest, reveals a purple robot at any screen corner, and captures drops/pastes directly into that robot with a digest animation. There is no separate capture area or composer. The code, screenshots, dimensions, and verification below describe an earlier rejected design; they do not implement or verify the new corner behavior.

## Verification status

Static checks completed on `index.html`, `styles.css`, and `app.js`. A live browser pass and screenshot capture could not be performed: the available computer-use surface reported **no browser available**, and its app inventory reported that the Mac was locked and could not be unlocked automatically. A Chrome headless attempt crashed and Quick Look rendering was sandbox-denied. No screenshot PNGs were fabricated. Re-run the interaction and visual checks below once the Mac/browser is available.

## Completed checks

- `app.js` passed the JavaScript engine's `--check` syntax validation.
- `index.html` begins with `<!doctype html>`; all 48 literal JavaScript ID lookups resolve to HTML IDs; no duplicate HTML IDs were found.
- CSS opening and closing brace counts match (288 each at final static re-check).
- Code-path review confirms separate move handle, robot body and paste control; drop and clipboard handlers; digest class with `prefers-reduced-motion` override; Daily/date/filter/detail/reminder/compact handlers; light/dark and narrow media-query declarations.
- The fictional seeded entries cover rich/fallback links and image, video, PDF, document, `.ai`, text, and unknown-file visual types. Card comments and reminders are optional and do not change the entry's `day`.

## Static findings addressed in the app

- Dark primary-button text now uses `--accent-on: #211d2d`: calculated contrast is 7.41:1 on its dark-mode base fill and 9.0:1 on hover.
- Robot single-click delay increased from 360 to 550 ms to better protect the double-click path. The no-flash outcome still needs a live timing test.
- Dropped `.txt`/`.md` files now classify as documents and therefore appear under Files.
- Tertiary metadata text was darkened in light mode (`#696c78`: 5.10:1 on window, 4.71:1 on sidebar) and lightened in dark mode (`#a2a2ad`: 6.03:1 on window, 6.35:1 on sidebar).
- Dropped image decode errors now replace the broken image with the type-specific image fallback while leaving its session-original openable.
- Newly dropped videos use a labeled VIDEO fallback instead of the seeded fictional poster treatment when no real poster is available.

## Remaining risk without a browser

- Interaction timing, viewport fit, visual rendering, and accessible focus behavior still need a real browser pass. `previews/index.html` provides four reviewable live frames in place of fabricated screenshots, but is not a PNG capture.

## Live pass required

- At desktop width: single robot click → paste composer; double-click at both fast and slow system-valid cadences → Daily without composer flash; move by handle; drop text, URL, image, video, PDF, document, `.ai`, text, unknown files; paste from focused robot and composer; digest and toast.
- Daily board: All / Links / Files / Media, previous/next and picked date, empty day, original-day persistence, detail comments/reminders and reminder list, compact toggle and placement.
- 360–430 px narrow layout, explicit `?appearance=dark`, OS dark appearance, reduced motion, keyboard navigation and Escape.
- Capture genuine PNG previews in `previews/` for Daily desktop, robot-only (`?view=desktop`), narrow, and dark once a browser is available.
