# DaBin v3 verification report

Design baseline: native DaBin 0.4.2 (53), commit b3f8507a77107474f923d9e4af5fc8ad4efe4a00. Review date: 30 September 2026. Fictional content only. No native app, user archive, production preference or installed application was modified.

## Executed checks

`python3 open-design-v3/verify.py` passes **218 assertions** with no failures. This total includes repeated link/markup checks; it is not 218 end-to-end scenarios.

- JavaScript syntax for all five editable scripts using the local JavaScriptCore engine.
- Rendering each of the 19 screen-markup functions without a JavaScript exception.
- Local route targets and complete generated HTML document boundaries.
- Fixture logic: monitoring defaults off, same-record task conversion, dual Media/Tasks filtering, one next recurring occurrence, original month-end recurrence anchor, no attachment duplication into the next occurrence, reminder timestamp retention, trash/restore preservation, retention protection, save-failure rollback, day/week export scope, retained project scratchpads, snippet alias/content separation, scratchpad search inclusion/exclusion, shelf membership removal, text escaping and mixed-script checklist content.
- The actual shelf ZIP writer was executed with local fixture assets, while the view was filtered to Links. Python verified ZIP CRCs, all three project-shelf entries, and exact SVG bytes.
- Resolved accent-text and primary-button contrast in light/dark for six source presets plus black, white, green and yellow custom extremes: all measured at least 4.5:1. A dark primary-button text issue found during this audit was corrected by choosing the higher-contrast foreground.

These checks use a minimal DOM stand-in. They **do not validate browser layout, event targeting, focus behavior or screen-reader announcements**. The complete assertion output is in qa-results.json.

## Visual and actual-scale review

The prescribed project screenshot command returned “unknown command”. No alternate browser was launched, and no rendered screenshot pass is claimed.

`../design-review.html` provides the original build-53 400 × 480 synthetic image beside the live redesigned Inbox in a 400 × 480 iframe. This is an actual-CSS-size comparison surface, not a new PNG export. Current source references remain unmodified under `../source/design/open-design-handoff-2026-09-30/reference-screens/`.

Static layout review added a short-window rule to reduce title/description and composer height. Container queries switch cards/details to one column below 700 px. Native 380 × 430 content minimum and 20 × 50 frame overhead are documented. Rendered overflow inspection at all requested widths, captured after images, continuous drag/resize and true 1×/2× backing-scale exports remain pending.

## Acceptance scenarios

“Logic checked” refers to executed fixture assertions. “Implemented” means the browser code/control exists; it does not imply a browser-click or native test was run.

| Scenario | Browser evidence | Remaining verification |
|---|---|---|
| A01 Robot intake and unreadable input | Drop/import/paste handlers and error paths implemented; robot entry explicitly simulated | Native promised files, stable corner hover, persistence-before-animation |
| A02 Feedback → project → task → attachment/comment/reminder | Connected screens; same-record conversion and receipt logic checked | Full browser click sequence; native provenance and notification delivery |
| A03 File batch intake/copy/minimize | File reader/group/member routes implemented; binary copy opens native contract | Multi-file pasteboard atomicity, unreadable member, native clipboard |
| A04 Project shelf export despite Links filter | ZIP writer executed; complete shelf, CRC and SVG bytes checked; membership keeps capture | Native save panel, verified managed-file paths, cancellation |
| A05 Find copy/plain text/return | Source/date/project/type filtering and clipboard fallback implemented | Real clipboard payload, focus/selection return in native task |
| A06 Pins/snippet alias/new copy | Separate Recent/Pinned/Snippets; alias/content preservation checked | Incoming native clipboard capture while browsing, scroll stability |
| A07 Project scratchpads and conversion | Per-project storage, retained scratchpad and conversion checked | Full reload/restart with native store and interrupted write |
| A08 Today planning and task edits | Plan/priority/effort/reorder/complete controls; record logic checked | Full click flow, deadline/notification separation in native services |
| A09 Monthly recurrence with checklist/attachment | One linked next, month-end anchor, no next attachment duplication checked | Native calendar/time zone transitions and original-family navigation |
| A10 Countdown/detail draft/reopen | Saved target timestamp retention checked; explicit detail draft/save implemented | Actual notification schedule, timed restart and failed draft persistence |
| A11 Sparse weekly/scoped search/Back | Sparse columns, seven-date range and scope controls implemented | Browser focus/scroll restoration and native animation direction |
| A12 OCR/scratchpad/nearby context | OCR fixture excerpt; scratchpad search inclusion and exclusion checked | Native Vision/PDFKit progress, bounds, retry and actual OCR content |
| A13 Filter-independent day/week export | Day output equality under filter changes and week receipt inclusion checked | Native copy/save byte equivalence, future boundary, disk error/cancel |
| A14 Independent opt-ins/pause/revocation | Initial channels off checked; source switches/status contracts implemented | Security-scoped folder picker, revocation, actual fresh baseline |
| A15 Four actions/hour/dedup/robot burst | Group threshold rendering and ten motion studies implemented | Native clock-hour grouping, cross-channel dedup and exact burst lifecycle |
| A16 Trash/Undo/restore/permanent cancellation | Family trash/restore preservation checked; separate destructive dialogs | Native journaled cleanup, I/O errors and notification reconciliation |
| A17 Retention protection | Explicitly kept and pinned auto copies protected in checked logic; exact-count confirmation | Native age selection and protected-family retention suites |
| A18 Backup/corrupt/conflicting restore | Separate fixture JSON format; validation and additive conflict guard implemented | Verified native .dabinbackup checksums, corrupt package and full isolated-store restore |
| A19 Compact/expanded/display changes | Container layouts, resize/expand/header drag implemented; safe-area spec provided | Rendered geometry, multiple displays, unplug, Spaces and 1×/2× |
| A20 Entry shortcuts/focus/hide/Quit | Browser shortcuts and hide/resume implemented; menu/Quit native dialogs | Native responder chain/global registration, Escape hierarchy, termination |
| A21 Direct/Store update variants | Both variants explicitly specified; no available-release claim | Compiled direct/helper vs Store boundary, verification, backup/install |
| A22 Accessibility/Quiet/transparency | Preferences and reduced-motion CSS implemented; color cases measured | Actual VoiceOver, keyboard/focus, OS accessibility preference inheritance |

No A01–A22 scenario is reported as fully native-verified. Some require macOS APIs that a web prototype cannot exercise.

## P0 / P1 / P2 review

### P0 — implementation and truthfulness

- Pass: distinct screen files; correct source identity; no permanent sidebar; preserved editable source package.
- Pass: all 80 rows have location, prototype/spec evidence and truthful status; no blank “TO COMPLETE” cells.
- Pass: no invented metrics, publication claims, live user data, cloud sync or remote AI.
- Pass: task conversion preserves source identity/date; input previews and work plans remain separate; native-only interactions are labeled.
- Pass: all generated scripts parse and screen-markup functions run; checked local links exist.
- Pending visual/native gate: rendered clipping/target review, native window transitions, all error scenarios, true backing-scale output and VoiceOver. These remain release-blocking for native implementation, not silently marked done.

### P1 — usability

- Four labeled destinations; no competing sidebar.
- Explicit empty recovery; one visible project context; distinct collection tabs.
- Source metadata remains best effort; no invented file path or destination.
- Long filenames wrap; preview images use contain; native PDF/video/unavailable behavior specified.
- Short-window chrome is reduced; retained context is stored independently from authored content.

### P2 — polish

- Thin metallic frame reserves head/hands/feet outside working content.
- Shared 1.65 px monoline icon grammar and consistent action areas.
- Motion is bounded and optional; no hidden permanent animation loop or sound.

## Native gates after implementation

From the actual native repository, with Apple tooling and an unlocked macOS session:

```
./scripts/test.sh --configuration Release
./scripts/build.sh
python3 scripts/generate_project.py --check
python3 scripts/app_store_preflight.py --static-only
```

Run `git diff --check` in that repository. Preserve the existing test inventory, particularly HeaderInteraction, WorkspaceWindow, ConnectedWorkflow, CaptureTaskConversion, TaskPlanning, WeeklyState/Window, DayExport/UI, LocalContentSearch, ClipboardRetention, ArchiveBackup, AutoCaptureService/HourlyGrouping, RobotLifecycle/AppFrame/WindowTransition, QuickAccess, ThemeSettings and update configuration. Historical baseline suite counts are not redesign results.


## Minimal-copy visual refinement — 2026-09-30

Updated all 19 standalone screens from shared sources. Added refinement.css, shortened headings and redundant introductory copy, enlarged fitted card previews, simplified the task list and header, and rebuilt robot.html as a compact capture surface. Advanced robot motion/entry controls are preserved under More. The launcher is shorter.

Validation: **220 passed, 0 failed** using verify.py. Added robot shared-draft persistence and failure-preservation assertions. CSS braces and standalone script boundaries are balanced. Existing task, retention, export and contrast checks continue to pass. Source robot artwork and native implementation references remain unchanged.

Visual QA: reviewed structure, density, breakpoint precedence, short-window scrolling and all meaningful controls statically. Rendered QA remains pending: the installed project wrapper does not expose screenshot rendering. Browser layout and native behavior are not certified by these checks.

Previous editable sources and HTML are archived at ../revisions/dabin-before-refinement.zip.


## Task cards and direct controls — current refinement

253 checks pass after adding distinct task cards, direct icon actions, project choices, hours/minutes focus timers and date/time scheduling. The original screenshot's work-plan dropdowns are removed from the task editor. Captures transform in place and support Undo; source content and receipt dates remain intact. Window geometry persists through updates.

Validation includes timer timestamp persistence, background delay, pause/resume, expiry without task completion, restart, completion stopping focus, recurrence isolation, duration/schedule form submissions, failed-save rollback, converted media/source preservation and balanced task form markup. The final form-structure check found and fixed an unclosed new-task timing container.

Rendering remains unavailable: the installed project command lists no screenshot/render interface and returns unknown command for its tools entry point. No alternate browser was launched. Layout assessment is static, including 400px/short-height and expanded container rules. Native focus-timer adoption, notifications and VoiceOver still require implementation verification.

## Content trail refinement — 2026-09-30

279 checks pass (0 failures). Capture cards, task cards, details and robot last-saved content now show original source app marks and recorded paste destination marks. New checks cover receipt attribution, local icons, unknown app fallback, repeated pastes, conversion/undo, safe escaping, recurrence isolation and failed-save rollback. All 19 standalone screens were rebuilt from the editable sources. Existing capture data is not backfilled with destinations.

Rendered review remains pending: the installed wrapper command inventory has no screenshot capability. Native cross-app paste detection is not implemented by the prototype or build-53 source. The new UI supports explicit manual destination recording and a future verified-receipt contract; clipboard copies are never logged as pastes.

## Responsive QA follow-up — 30 September 2026

361 automated checks pass after sharing the project picker and repairing viewport bounds. Nine viewport geometries cover 360×640, 390×844, 400×480, 430×360, 600×480, 768×1024, 1024×768, 1440×900 and 1920×1080. See RESPONSIVE_QA.md for repairs, exact evidence and limits. Geometry tests are not rendered CSS layout tests. Screenshot rendering remains unavailable and Open Design app access was not approved.
