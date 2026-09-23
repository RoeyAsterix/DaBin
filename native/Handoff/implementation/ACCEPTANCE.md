# Build order and acceptance

All native checks below are **not run** at handoff time. Codex should record pass/fail/blocked, command or steps, OS/Xcode, fixture and evidence path in the app repository's `QA_RESULTS.md`. A mock proves logic, not real OS integration.

## Milestones

| Order | Deliverable | Exit condition |
| --- | --- | --- |
| 1 | Native project and window shell | App launches; actual-size robot moves; one 420 pt panel; menu recovery; no sidebar |
| 2 | Persistent capture | Text, URLs and managed files save durably with immutable dates; partial failures are honest |
| 3 | Daily and Detail | Date/filter browsing, originals, comments, optional reminder drafts and preserved navigation context |
| 4 | Native previews and contextual search | Real thumbnail/URL fallback pipeline; all supplied search cases pass |
| 5 | Reminder integration | Permission, schedule, edit, clear and cold-launch capture routing work |
| 6 | Native QA and handoff | Build/tests, actual-scale evidence, relaunch scenario and documented remaining limits |

Show a usable shell after milestone 1, but continue through milestone 6. Do not claim app completion from source files alone.

## Automated checks

| ID | Scenario | Required result |
| --- | --- | --- |
| A01 | Classify HTTP(S), text, MIME-less image/video/PDF/document/AI and unknown file | Correct kind and All/Links/Files/Media grouping; custom URI is not an auto-open link |
| A02 | Alternate representations of one item vs multiple items | One capture per logical item; distinct equal-content items remain distinct |
| A03 | Empty input, multiple URL lines, mixed prose | Reject whitespace; split all-URL lines; retain mixed prose as text |
| A04 | Comment/reminder update | ID, capture time, day and zone unchanged; only editable metadata updated |
| A05 | Midnight during async copy, DST, year boundary and travel | Original receipt day/time remains stable; no regrouping by current timezone |
| A06 | Search fixture file | Expected groups, hit IDs, neighbor IDs and ordering exactly match |
| A07 | Empty/diacritic/multiword search and filename match | Empty has no result groups; normalized AND matching; no all-days list |
| A08 | Copy originals, move source, reconstruct store | Bytes still match; all managed originals open/read after relaunch |
| A09 | Duplicate filenames and path traversal | Separate managed locations; no overwrite/escape; display filenames intact |
| A10 | Fail at staging/move/database save/preview stages | Never false success; recovery only touches owned imports; preview failure preserves original |
| A11 | Mixed batch: one item fails | Successful items remain; exact partial-failure feedback; retry does not duplicate them |
| A12 | Store cannot load or save | Visible recoverable failure; no silent reset or fictitious success |
| A13 | Rapid reminder edits/clear and out-of-order callbacks | Only latest persisted state wins; no duplicate pending request or resurrection |
| A14 | Notification denied, scheduling failure, past date, DST gap | Reminder state remains honest; validation is clear; captures unaffected |
| A15 | Startup reconciliation and notification click | Future requests reconcile; no overdue alert burst; exact capture route including cold start |
| A16 | Preview opt-in off / switched off during request | No new remote fetch; cancel pending work; URL original remains accessible |
| A17 | Geometry: negative coordinates, removed monitor, small visible frame | Bin/panel remain recoverable and within visible screen bounds |
| A18 | UI loading, error, empty and populated states | No fictional production seed; draft not lost on dismissal; one content panel |

Use temp directories and deterministic clocks. Store integration tests should reopen the database and compare attachment hashes, not just inspect in-memory arrays. Fault injection is required for failure recovery; a happy-path test does not prove it.

## Hands-on native checks

| ID | Scenario | Required result |
| --- | --- | --- |
| N01 | Single click, system-slow double click, double click after hover | Correct route; no composer flash; no duplicate window |
| N02 | Move handle vs drop target | Moving never captures; external drop never drags widget; off-widget clicks reach the other app |
| N03 | Typing in another app while bin idles/updates | Focus stays there; opening Capture/Search intentionally focuses editor |
| N04 | Finder multi-file drop: image, PDF, `.ai`, arbitrary file | Separate durable captures; unsupported preview is a fallback, not failed import |
| N05 | Browser URL drag, plain text paste, image bytes, file promise | Actual supplied representation captured; no duplicate alternatives; honest unsupported state |
| N06 | Save, quit/relaunch, move/remove source originals | Managed originals still open; dates/comments/reminders persist |
| N07 | Daily/filters, Detail/Back, search result/Back | Correct day, filter/query and scroll restored; fresh Daily is Today/All |
| N08 | Visible per-card actions in Daily and search neighbors | Comment/Reminder present and focus intended field |
| N09 | Link previews enabled/disabled, offline, metadata failure | Useful URL cards always; network privacy preference respected |
| N10 | Set reminder, close panel, quit app before due time | OS reminder integration exercised; record permission/Focus/OS delivery outcome honestly |
| N11 | Clear/edit reminder, click old notification | No duplicate/stale schedule; cleared state not resurrected; correct original capture opens |
| N12 | Space changes, fullscreen app, two displays, monitor unplug | Bin behavior matches documented policy; panel on-screen; menu recovery always available |
| N13 | Dark/light, Increase Contrast, Reduce Motion, VoiceOver, keyboard traversal | Readable controls, labeled actions, visible focus and no mandatory motion |
| N14 | Long text/filenames, many cards, large file, repeated imports | Readable scrolling; input remains responsive; progress and errors honest |
| N15 | Close/Escape/outside click with edits; Quit with unsaved draft | No silent loss of draft; stored originals unaffected |

Capture native screenshots of resting/drop bin, Daily, Capture, one-day/multiday contextual Search, Detail, Reminders, dark and constrained work area. Include one actual desktop-scale view to show footprint. Do not present browser images as native captures.

## Build evidence

The implementer must record the installed toolchain before selecting Swift language features. For the recommended project/scheme, an intended starting point is:

```sh
xcodebuild -version
xcodebuild -list -project DaBin.xcodeproj
xcodebuild -project DaBin.xcodeproj -scheme DaBin -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build
xcodebuild -project DaBin.xcodeproj -scheme DaBin -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData test
```

These are **future commands**, not commands executed for this handoff. Adapt to the actual project/toolchain and document the exact invocation. Use a valid development signing configuration for sandbox/notification/GUI integration; an unsigned compile-only check cannot close those gates. Never disable sandbox to make an acceptance test pass.

## Definition of done

- The native `.app` runs from its documented path and passes the full capture → edit → quit → relaunch → open-original scenario.
- Contextual search follows the day/neighbor contract exactly.
- All MVP functionality uses native persistence and system integration, with visible failure states.
- No sidebar or task-management UI appears; source robot, dimensions, typography and appearance are preserved.
- Screenshots and results identify what was actually tested. Blocked native checks stay visibly blocked.
- `README.md`, `IMPLEMENTATION_NOTES.md`, `QA_RESULTS.md` and build/run instructions are delivered. No unverified signing, native capability or release claim.
