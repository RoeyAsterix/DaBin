# DaBin navigation and adaptive zoom handoff

Prepared for Roey on 4 October 2026. This is a proposed product and engineering specification, not a release note. It refines two ideas: navigating with a mouse or trackpad alongside the existing arrows, and zooming workspace content while the floating window grows or shrinks with it. No implementation, deployment, or external assignment is performed by this document.

## Recommended experience

DaBin should feel comfortable with whichever input someone prefers. Back and Forward retrace visited views. Pinching makes workspace content larger or smaller; the floating window makes room where the screen allows. Existing buttons, manual resizing, and keyboard access remain available.

The main decisions are:

- Use one navigation history for buttons, mouse Back/Forward, keyboard shortcuts, and trackpad page swipes. Keep day/week paging as a separate action.
- Enable window resizing with workspace zoom by default, with a setting to turn the coupling off. Expanded windows stay expanded.
- Keep document magnification separate from workspace zoom. A gesture must reach only one owner, never both.

These are recommended defaults for implementation, not claims about the installed app. The numeric limits below are product proposals to validate with usability and performance tests.

## Current source baseline

Read-only inspection used the working tree at Git base `2fef249` on 4 October 2026. The tree contains substantial uncommitted and concurrent work; the commit alone does not identify all inspected code. Recheck the named symbols before implementation and preserve unrelated edits.

| Area | Observed source | Consequence |
| --- | --- | --- |
| Navigation | `AppState.back()` restores several route-specific return contexts. There is no corresponding forward-history implementation in the inspected files. | Add a shared history model; mapping new inputs to the existing method alone is insufficient. |
| Project state | `ProjectWorkspaceView` keeps filters, selection, density and sort in local SwiftUI state. | Move restorable presentation state into a suitable owner before promising exact Back restoration. |
| Native input | `DailyCaptureHostingView` and `DailyCapturePanel` handle native shortcuts and duplicate paste dispatch. | Extend this window-local boundary without bypassing child controls. |
| Window geometry | `CornerController` supports manual resizing and temporary Expand/Restore. `BoardResizeGeometry` fits frames to the display; its manual minimum is 380 × 430 content points plus robot chrome. | Reuse the geometry rules, with a dedicated zoom lifecycle. Some automatic layouts can currently be smaller than the manual minimum. |
| Project grid | Column thresholds are currently physical widths of 520 and 850 points, with fixed card metrics. | A wider window alone adds columns; it does not implement zoom. |
| Capture canvas | Untracked `CaptureExtendedCanvas.swift` contains image/PDF/text zoom state and input handling; an untracked unit test also exists. No canvas instantiation or assignment to `onOpenExtendedCapture` was found outside this scaffold during inspection. | Coordinate with its author. Do not describe it as shipped, integrated, or tested. Its test is not registered in the inspected default QA runner. |

## Navigation behavior

### Input mapping

| Input | Proposed action | Protection |
| --- | --- | --- |
| Existing Back control | Previous visited view | Use the shared history and enabled state. |
| Matching Forward control | Next view after going Back | Keep it in the same compact navigation group, not a second toolbar. |
| Mouse Back / Forward buttons | Same Back / Forward commands | Handle supported auxiliary-button events or driver-mapped shortcuts once. Leave middle/right click unchanged. |
| Trackpad page swipe | Same Back / Forward commands | Honor macOS page-swipe settings and native direction; do not require a particular finger count. |
| Command–[ / Command–] | Back / Forward | Respect a focused editor's claimed shortcut and modal UI. |
| Existing day/week arrows | Previous / next day or week | Preserve their current meaning and bounds. They are not Forward history. |

Keep existing arrow controls. Make the Back/Forward group available on navigable top-level views as well as details, with unavailable actions disabled and accessible labels. Retain separate labels such as “Previous day” for date controls. Avoid adding a permanent gesture hint or another project title.

Back means “where I was,” not “an earlier date.” Deliberately choosing a different day/week can create a visited state, so Back can return to that date; it must not invent an unvisited next day when Forward history is empty. PDF page arrows remain document controls.

### History and restoration

Use a bounded, session-only history: at most 100 entries including the current entry. Do not persist browsing history to disk or include file bodies, clipboard contents, or draft text in snapshots.

Record deliberate transitions between views, projects, captures, and selected day/week destinations. Before leaving, update the current entry with its latest presentation state. Filter changes, query typing, selection changes and scrolling update the current entry rather than creating a history entry for every interaction. Zoom stays outside history. Re-selecting the same destination is a no-op. After Back, deliberate navigation to another destination removes the old Forward branch; live capture arrivals, preview completion and timers do not.

Each restorable entry needs the route and workspace mode, applicable project identity, selected item, project filters/date range/sort/density, search query and scope, source/origin filters, timeline dates, multi-selection, expanded groups, focus target, and viewport anchor. Use stable item identity plus a local offset, not only a raw scroll position. Respect the current data model; do not assume projects already have immutable UUIDs.

Restore view state without reversing edits to the archive. Drafts stay in the existing draft owners and retain save/error status. Do not copy stale content back from history. Preserve the existing task → attachment → task, search → result → search, creation-return, and Settings/Trash-return journeys. For a direct-open detail with no previous entry, seed its known parent/origin once; otherwise Back at the history root does nothing.

If an item or project was deleted or renamed, resolve against current data, pruning invalid entries. Fall back to the nearest valid parent when necessary; never reopen a different item by list index or resurrect removed data. Restore only still-valid selections. If the anchor vanished, keep the nearest surviving neighbor visible. Restore focus after layout without selecting or overwriting text automatically.

### Gesture safety

Apple documents native gesture delivery through the responder chain and gesture phases. Use those mechanisms instead of a global input hook or a custom blocking event loop. [Apple gesture handling](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html)

- Only handle events belonging to the active DaBin content window. No new Accessibility or Input Monitoring permission should be required for these local interactions.
- A horizontal gesture that begins over a horizontal scroller or live document canvas stays with that surface for its entire lifetime. In the first release, reaching its edge must not transfer the same gesture into page navigation. Reserve other child gestures when that child actually claims them or text selection/reordering is active; a card being drag-capable must not by itself disable swipe or pinch over it.
- Use native page-swipe recognition where available. A supported scroll-based swipe path must consult `NSEvent.isSwipeTrackingFromScrollEventsEnabled`, check dominant horizontal intent and cancellation, and never interpret ordinary wheel ticks or momentum as navigation. System gesture configuration belongs to the user. [AppKit swipe setting](https://developer.apple.com/documentation/appkit/nsevent/isswipetrackingfromscrolleventsenabled), [macOS gesture settings](https://support.apple.com/en-gb/102482)
- Commit at most one history move per gesture. Cancelled swipes leave state unchanged. Do not hard-code a raw `deltaX` sign across devices and natural-scrolling configurations.
- Block navigation during sheets, modal confirmations, onboarding, active dragging/resizing/reordering, marked-text composition (IME), or an unresolved editor validation failure. Preserve normal text editing and the app's current draft recovery behavior.
- Use one command dispatcher and de-duplicate responder/menu delivery. Test actual mouse drivers: extra-button numbering and shortcut translation are not universal.

## Workspace zoom and window size

### Scope and controls

Workspace zoom changes card sizes, previews, note/content text and their layout metrics. Navigation chrome, resize grips and the robot retain their normal interaction sizes. The robot's frame follows the window's geometry; zoom must not replay its open/close animation or stretch a bitmap of the whole interface.

Start at 100%, allow 75–200%, and support continuous pinch changes. Discrete Zoom In/Out steps are 75, 90, 100, 110, 125, 150, 175 and 200%; from an in-between value choose the next step in the requested direction.

| Input or state | Proposed behavior |
| --- | --- |
| Pinch over the workspace | Enlarge/reduce content around the pointer location reported by the event. |
| Command + mouse wheel over the workspace | Same workspace zoom; plain scrolling stays scrolling. Do not intercept Control + scroll, which may be used for system accessibility zoom. |
| Command–Plus / Command–Minus | Step workspace zoom in/out when the workspace owns the command. Also accept Command–Equals for Zoom In. |
| Command–0 | Reset workspace content to 100%; update floating geometry only if coupling is enabled. |
| View menu | Explicit “Zoom Workspace In,” “Zoom Workspace Out,” and “Reset Workspace Zoom” commands, including current percentage. These remain usable when a document viewer owns generic zoom shortcuts. |
| Floating window, coupling on | Resize the content area proportionally, then fit the outer frame to the display and usable minimum. |
| Floating window, coupling off | Zoom content inside the existing frame. |
| Expanded window | Zoom content only; do not shrink, leave expanded mode, or replace its saved Restore frame. |

Make ownership visible: native document-viewer controls are labeled for the document; workspace menu controls always mean workspace. A live document canvas gets first refusal for its own pinch, wheel and generic zoom shortcuts. Those events must not also resize the workspace. Do not change the in-progress canvas's existing wheel policy as an incidental part of this work. External apps opened to view files are unaffected.

Add two settings under “Navigation and zoom”:

- **Trackpad Back and Forward** — on by default; helper text: “Use your Mac's page-swipe gesture to revisit views.” This does not enable a gesture disabled in macOS.
- **Resize window with workspace zoom** — on by default; helper text: “Make room as content gets larger. Expanded windows keep their size.”

Switching coupling on/off must not immediately resize the window. Rebase the next interaction to its current geometry. Mouse buttons, keyboard commands and arrows remain available when trackpad navigation is off.

### Geometry and anchoring contract

At the first coupled zoom, capture a normal-window reference: content size, zoom factor and top-left position. Compute subsequent desired content sizes from that reference and the ratio of target/reference zoom, then add the existing robot chrome and fit to the current display. Do not repeatedly multiply an already-clamped frame; that causes drift. Automatic undersized layouts adopt the manual minimum on the first actual coupled size change, not merely on gesture begin.

Preserve the floating window's top-left position where possible. Shift it only as needed to keep controls within the display's usable area. A screen boundary stops window growth, not content zoom. On reversal, the frame shrinks once its computed size is below that boundary. Minimum size similarly stops shrinking before content reaches its own zoom limit. Do not automatically move to another display unless the current display becomes unavailable; then end the gesture, fit onto a surviving display, preserve scale and establish a new geometry reference.

Manual resize establishes a new size/zoom reference; manual movement updates the position reference. Reset computes the 100% size from that reference, subject to current bounds. Without an intervening resize, display change or expansion, 100% → 150% → 100% should recover the same fitted frame, including after a temporary screen clamp.

Expand preserves the current normal frame. While expanded, changing zoom must leave that saved frame untouched. Restore returns to the saved frame, fitted to the current display, keeps the current content zoom, and establishes a new reference at that size/zoom so the next gesture does not jump. Treat native macOS full-screen as content-only too if it is supported separately from DaBin's current Expand action.

Keep the content item under the pointer stable; keyboard/menu zoom anchors the focused visible item, otherwise the viewport center. Reconcile layout and scroll after changing the frame. If exact anchoring is impossible at a content edge, use the closest valid position. Preserve selections, editing focus, text insertion point and project identity throughout.

Use zoom-aware layout metrics and logical content width, not just `scaleEffect` on the whole board. Keep grid column count stable during a gesture, then reflow once on completion if the final constraints require it, restoring the item anchor. Keep previews dominant, preserve distinct task/note/capture styling, and keep existing minimum control hit areas. Settings and system dialogs do not inherit workspace scaling.

### Lifecycle and responsiveness

One physical gesture has one owner, chosen at its start: document interaction, workspace zoom, page navigation, or scrolling. Do not reclassify a gesture midstream or let two controllers own window geometry. Reject navigation input during active zoom rather than queueing it for later, and defer automatic route-driven window fitting. Manual drag/reorder, opening/closing transitions, sheets and loss of window focus must end or reject the session cleanly.

Track native magnification phases and coalesce visual updates to the display cadence. A cancelled zoom retains the last valid visible size/scale, clears transient flags and persists once; a cancelled navigation swipe never commits a move. Wheel sessions finish after 200 ms without a qualifying event, ignoring momentum for workspace zoom. No per-tick preference writes, preview decoding, archive saves, network requests or uncapped task creation. [AppKit magnification entry point](https://developer.apple.com/documentation/appkit/nsresponder/magnify(with:))

Keep reusable view identities, list virtualization and thumbnail caches. Avoid rebuilding every project item per tick. Respect Reduce Motion: direct pointer tracking remains, while decorative easing, bounce and transitional effects are removed. Do not add a toast on every change. If a temporary percentage label is used, hide it within two seconds after input ends and respect the existing tooltip preference.

Workspace zoom is one local preference across workspace routes, separate from per-document zoom and from navigation history. Back/Forward must not restore historical geometry or undo zoom. A coupled zoom establishes an explicit normal-window size that subsequent routes retain; existing automatic route sizing can continue before a user chooses an explicit size. Restore history anchors under the current zoom. Save zoom and normal geometry only at completed interaction boundaries, validate saved values, and clamp geometry when displays change. Collapsing to the robot keeps the preference for reopening.

## Engineering handoff

| Integration area | Existing source | Required work |
| --- | --- | --- |
| Route and history state | [AppState.swift](../native/Sources/DaBin/AppState.swift) | Add typed snapshots, one navigation dispatcher, bounded history and restoration. Audit direct route writes; distinguish user navigation from background updates. |
| Native event ownership | [DailyCaptureView.swift](../native/Sources/DaBin/DailyCaptureView.swift) | Route auxiliary buttons, keyboard, swipe and pinch locally with child-responder precedence and duplicate suppression. |
| Visible controls and preferences | [BoardView.swift](../native/Sources/DaBin/BoardView.swift), [SettingsScreen.swift](../native/Sources/DaBin/SettingsScreen.swift) | Compact Back/Forward controls, menu commands, setting persistence, help and accessible enabled states. |
| Window lifecycle | [CornerController.swift](../native/Sources/DaBin/CornerController.swift), [BoardResizeGeometry.swift](../native/Sources/DaBin/BoardResizeGeometry.swift), [RobotAppFrameView.swift](../native/Sources/DaBin/RobotAppFrameView.swift) | Separate zoom from manual resize. The current `beginBoardResize()` clears expansion state; calling it unchanged for every pinch would violate this specification. |
| Project rendering | [ProjectWorkspaceView.swift](../native/Sources/DaBin/ProjectWorkspaceView.swift), [ProjectWorkspaceCard.swift](../native/Sources/DaBin/ProjectWorkspaceCard.swift) | Hoist restorable local state, scale metrics and thresholds, retain stable identities and selection. |
| Viewport restoration | [ExplorerViewport.swift](../native/Sources/DaBin/ExplorerViewport.swift), [SearchColumnViewport.swift](../native/Sources/DaBin/SearchColumnViewport.swift) | Coordinate history/zoom anchoring with live-capture insertion anchoring; preserve horizontal scroll behavior. |
| Document zoom coordination | [CaptureExtendedCanvas.swift](../native/Sources/DaBin/CaptureExtendedCanvas.swift) | Recheck in-progress integration, keep its state separate and explicitly resolve gesture/command ownership. Its 5–1600% media scale is not the workspace range. |

Recommended implementation order:

1. Add history and restoration tests first, then wire existing buttons and keyboard commands. Preserve all current return journeys before adding gestures.
2. Add mouse support and trackpad navigation, with event ownership and device tests. Do not ship untested horizontal-scroll interception.
3. Add a separately testable workspace zoom/geometry model. Integrate scalable layout and content-only zoom before enabling window coupling.
4. Add coupled geometry, expanded-mode behavior, preferences and native interaction tests. Profile with auto-capture active before preparing a local candidate.

Use small, independently reviewable changes. Recheck concurrent source edits and coordinate file ownership before touching shared files. Keep this work separate from App Store submissions, robot redesign, archive migration and document-viewer completion.

## Acceptance and release gates

Use fictional projects, isolated stores/preferences and injected capture events. Do not operate stress tests against the user's live archive or clipboard. Register new suites in the actual QA runner; a test file on disk is not evidence that it ran. Serialize native GUI tests and use the repository's build/source verification process so results describe the candidate actually reviewed.

| Test | Required result |
| --- | --- |
| Project → filtered last-week results → capture → Back → Forward | Restore the same project, filters, selection, scroll anchor and capture through buttons, mouse, keyboard and swipe. |
| Task → attachment; search → result; new item → return; Settings/Trash → return | Existing return context and unsaved draft/error state survive. No unintended save, discard or parent loop. |
| Back, then new navigation; rapid repeat input; automatic captures arriving | Forward clears only for new deliberate navigation. One physical action causes one transition; background arrivals add no history entries. |
| Day/week and PDF arrows | Still page their own dates/pages; Forward never fabricates an unvisited destination. |
| Empty history, deleted target, renamed project, vanished anchor | Safe disabled/no-op/fallback behavior; no crash, wrong item, restored deleted data or stale private text. History remains within 100 entries. |
| Horizontal week columns, filter strips, document pan, text selection and reorder | No accidental route change, including at scroll edges and during momentum. Cancelled swipe leaves the current view untouched. |
| Floating zoom 100% → 150% → 100%, repeated 50 times | Correct content scale, preserved anchor and original fitted frame; no cumulative geometry drift. |
| Minimum size, screen limit, menu bar/Dock, multiple display layouts and display disconnect | Controls remain reachable; no NaN/negative geometry or hidden close button. Relocate only if the current display disappears, preserving scale and safely rebasing. |
| Expanded zoom and Restore; coupling off/on; manual resize between zooms | Apply the geometry contract exactly; preserve Restore frame and avoid a jump when changing modes. |
| Document pinch/scroll versus workspace pinch/scroll/shortcuts | Exactly one owner; independent scales; workspace menu commands remain accessible; plain workspace scrolling stays intact. |
| Selection/draft during zoom; robot opening/closing; deactivation or sheet during gesture | No lost input, stretched robot, fighting animations, stuck interaction flag or follow-up event replay. |
| Relaunch, Reduce Motion, VoiceOver, IME composition, non-US keyboard and tooltip-off | Valid local preference restoration; named controls and usable shortcuts; no interrupted composition, unwanted animation or helper messages. |

For performance, use a reproducible fixture with 5,000 mixed items, then run ten minutes of injected auto-capture at one item every two seconds while navigating and zooming. Include a burst of 100 arrivals during a gesture. Measure a warm baseline and at least five repeated interaction cycles. Proposed targets on the reference Mac are p95 input-to-visible-update ≤50 ms and p95 frame interval ≤33 ms during steady gestures, with no main-thread stall over 100 ms attributable to this feature. Investigate monotonic memory growth across cycles; report actual hardware, OS, scale, measurements and limitations rather than promising the app can never freeze.

Add pure tests for history branching/pruning, bounded snapshots, finite zoom input, anchor math and round-trip geometry; native tests for event dispatch, focus, cancellation, sheets and Expand/Restore; and physical trackpad/mouse tests with natural scrolling on/off and supported page-swipe settings. Synthetic events do not replace hardware verification. Run relevant navigation, search, draft, resize, robot-transition and auto-capture responsiveness regressions, plus any capture-canvas tests that are integrated by then.

Before marking implementation complete, provide source-bound test results, documented device coverage, fictional-data visual evidence at 75/100/150/200%, and any unresolved limitations. Keep capture-exclusion protections enabled; use isolated native render fixtures when the live panel cannot be recorded. Building, installing, publishing or submitting a candidate requires the authority of the implementation task, not this planning document.

## Copyable developer brief

Implement the proposed navigation and adaptive workspace zoom behavior in this handoff. Start by re-inspecting current DaBin sources and coordinating concurrent edits. Preserve arrows, manual resizing, robot presentation, drafts and local privacy. Introduce bounded session history with Back/Forward parity across inputs, then workspace zoom with optional floating-window coupling and explicit document-gesture precedence. Verify the acceptance matrix with isolated data and actual devices. Report what was implemented and tested separately from what was installed or released; do not infer deployment or submission permission from this handoff.
