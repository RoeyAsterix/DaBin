# DaBin — spatial redesign

Open `index.html` for the overview or `daily.html` for the selected product surface. Serve the folder over a local HTTP server so browser storage and clipboard behavior use a stable origin.

## Product screens

- `rest.html` — movable capture bin
- `daily.html` — date-based archive
- `capture.html` — paste and file capture
- `search.html` — matching days with neighboring context
- `detail.html` — original, comment and reminder
- `reminders.html` — reminders linked to capture dates

Shared behavior lives in `app.js`, pure search/date/type logic in `model.js`, and styling in `styles.css`.

## Review

- `concepts.html` — edge-bin and bottom-tray footprint comparison
- `review/index.html` — 21 live review states
- `DESIGN_NOTES.md` — visual and interaction decisions, native boundaries
- `QA_NOTES.md` — checks and outstanding rendered verification
- `review/qa-results.json` — repeatable logic and smoke-check results

The original source package under `source/DaBin/` is unchanged. No external service or deployment is required. Starter data is fictional.
