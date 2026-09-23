# Paste this into Codex

Implement **DaBin as a working native macOS app** using this handoff package, `DaBin-macOS-Codex`. Locate the package in the attached/extracted files; resolve its relative paths from the package root. Use the repository selected by the project owner. Inspect the destination and its applicable repository instructions first; preserve any existing work.

Read, in order:

1. `implementation/PRODUCT_AND_DESIGN.md`
2. `implementation/NATIVE_BUILD.md`
3. `implementation/ACCEPTANCE.md`
4. `implementation/SOURCE_MAP.md`
5. The relevant files under `reference/prototype/`, especially `styles.css`, `model.js`, `app.js`, `daily.html`, `rest.html`, `capture.html`, `search.html`, `detail.html`, `reminders.html` and `assets/robot.svg`.

The assignment is implementation of the selected design. Do not restart visual discovery or produce another website. Build SwiftUI views with AppKit-managed floating panels and native macOS integration. Do not embed the HTML in WKWebView, Electron or a browser shell. Use macOS 14+ as the default deployment target and SwiftData for metadata unless a real repository constraint requires a documented alternative.

## Product locks

- **No sidebar, navigation rail, project hierarchy, assignees, completion states or required deadlines.**
- A tiny, movable metallic-purple robot bin is the resting desktop surface. Its body accepts drops; its separate handle moves it. Single-click opens capture, double-click opens Daily without flashing capture. Use the system double-click interval, not the prototype's hardcoded delay. Include accessible direct actions for both routes.
- One floating content panel switches among Daily, Capture, Search, Detail and Reminders. Top controls and Back provide navigation. Follow the selected edge-bin model; the bottom tray is an unselected concept.
- Capture URLs, plain text, image data, videos, PDFs, documents, `.ai`, arbitrary readable files and file promises. Each distinct dropped item becomes its own capture; alternate representations of the same item must not create duplicates. Report unsupported or failed items honestly.
- Save originals durably before reporting success. Copy file originals into managed application storage. Preview work is separate and never blocks or invalidates a saved capture.
- Freeze each capture's UTC timestamp, local Gregorian day and capture timezone at intake. Comments, reminders, travel and midnight rollover must never move it to another day.
- Daily opens on Today/All on a fresh invocation, with chronological captures, previous/next day, date picker, Today and All/Links/Files/Media. Back from Detail restores the previous view state.
- Show visible Comment and Reminder actions on every capture, including search neighbors. Both are optional.
- Contextual search shows only matching dates; for each hit include the immediate same-day capture before and after it, deduplicated. Type filters constrain hits, not neighbors. Port the supplied fixtures as unit tests.
- Use real OS reminders, with permission/error states and clear/cancel behavior. Notification clicks open the exact capture; a reminder never changes its capture day.
- Local first, no account, cloud sync, analytics or private-data uploads. Link previews may contact remote sites only when explicitly enabled; useful URL cards must work with previews disabled.
- Preserve the supplied robot identity and light/dark visual system. Do not ship fictional seed content or prototype review controls to normal users.

## Work and finish

Create a short implementation plan, then work through all milestones in `implementation/ACCEPTANCE.md`. First show a launchable native shell with the real-size bin and Daily panel. Continue through durable capture, previews, search, comments and notifications; do not stop after the shell.

Use built-in Apple frameworks where practical. Make routine choices from the supplied defaults without pausing for design questions. Record deviations in `IMPLEMENTATION_NOTES.md`; ask only if a missing decision genuinely blocks safe implementation. Keep source references unchanged.

Deliver:

1. A buildable `DaBin.xcodeproj` (or the repository's existing native project) with a shared `DaBin` scheme, native app source, asset catalog, tests and sandbox entitlements.
2. A reproducible command-line build/test path and README with the exact Xcode/SDK, deployment target, run steps, storage location, preview privacy, notification behavior and known limits.
3. A working debug `.app` at the documented build-products path when the machine supports it. Do not call it a signed distribution release unless signing/notarization were actually completed.
4. Native screenshot evidence at actual scale for the bin, Daily, Capture, contextual Search, Detail, Reminders and dark mode, plus check results in `QA_RESULTS.md`. Use fictional development fixtures only in an isolated test store.
5. Passing automated checks for immutable dates, search context, classification, managed-file persistence, failure recovery and notification reconciliation; hands-on native checks for drag/paste, click timing, focus, Spaces, display changes and accessibility.

The end-to-end acceptance scenario is: drop an image, PDF and `.ai` file; paste a URL and text; add a comment and future reminder; quit and relaunch; find the items on their original day; open every managed original after the source files have moved; search with correct adjacent context; exercise a scheduled reminder and open its capture. No sidebar appears anywhere.

Report what actually ran and where to open the app. If Xcode, GUI access, signing or notification delivery cannot be validated, name the specific limitation and continue all independent implementation work. Never substitute a browser preview, mocked OS call, or declared checklist item for native verification.
