# Responsive and interaction QA — 30 September 2026

## Result
361 automated checks pass. These are JavaScript execution, geometry, persistence, markup, build-synchronization and source-level checks, **not browser-rendered layout measurements**.

## Viewport cases
| Width × height | Window bounds | Project panel bounds (top / bottom anchor) |
|---|---|---|
| 360 × 640 | Pass | Pass / Pass |
| 390 × 844 | Pass | Pass / Pass |
| 400 × 480 | Pass | Pass / Pass |
| 430 × 360 | Pass | Pass / Pass |
| 600 × 480 | Pass | Pass / Pass |
| 768 × 1024 | Pass | Pass / Pass |
| 1024 × 768 | Pass | Pass / Pass |
| 1440 × 900 | Pass | Pass / Pass |
| 1920 × 1080 | Pass | Pass / Pass |

Geometry assertions execute the same functions used by the product. They confirm mathematical bounds; they do not measure actual DOM rectangles, text wrapping or CSS layout.

## Repairs
- Moved robot.html's local project picker into shared sources, so navigation and rebuilding no longer lose it. Workspace collections show the selected project in the header.
- Kept window drag/resize geometry inside the current viewport, including after shrinking it. Expansion releases explicit dimensions; restoration rechecks bounds.
- Positioned project panels below or above their trigger, with viewport and keyboard-area bounds.
- Added Tab cycling, visible keyboard focus and existing Escape return focus. Reset invalid-name feedback when reopening creation; block duplicate, reserved and invalid project selections.
- Made long project names truncate within controls. Narrow forms stack, filter rows scroll locally, search fields can shrink, dialogs scroll within short windows, and touch icon targets are at least 44px.
- Preserved the current content, tasks, timer/schedule controls, logo trails, purple palette and no-sidebar layout.

## Behavior coverage
Project search and selection, creation and save persistence, duplicate/invalid-name rejection, escaped long names and save-failure rollback. Existing checks also cover capture conversion, source/receipt preservation, task timers, scheduling, recurrence, content trails, export and recovery. All 19 generated screen scripts match the shared sources.

## Limits
The project screenshot interface is unavailable. Access to the running Open Design app was not approved, so no rendered screenshots or live browser interactions were verified. Pixel-level overflow, rendered touch-target dimensions, native keyboard traversal, zoom, contrast in every state, and visual smoothness remain unverified. Native OS integration remains a separate release gate.

## Reproduce
Run `python3 open-design-v3/build.py` then `python3 open-design-v3/verify.py` from the project root. Results: `open-design-v3/qa-results.json`. Responsive assertions: `open-design-v3/qa/responsive_checks.py`.
