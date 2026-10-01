# DaBin — current design and UX implementation contract

Date: 30 September 2026. Native reference: 0.4.2 (53), commit `b3f8507a77107474f923d9e4af5fc8ad4efe4a00`. This handoff transfers the latest browser design into the existing macOS app. It does not claim the native app has already been redesigned.

## 1. Source precedence and resolved conflicts

Use the latest explicit product requirements below and the shipped shared components for the redesigned experience. Preserve native feature and data-integrity contracts from the original brief and source. If newer repository behavior conflicts with this reference, describe the concrete conflict and retain user data while reconciling it.

| Older material | Current requirement |
|---|---|
| Daily-only concept; no tasks/composer/grouped files | Superseded. Preserve the full build-53 product and all 80 features. |
| Native source map calls focus timer deferred | Timer, hours/minutes and optional planned time are now required additions. Other deferred roadmap items remain out of scope. |
| Navigation map says Actions → Turn into task | Use the direct task icon and transform the existing card in place. |
| Generic Workspace heading / ordinary project select | Show selected project name and the shared searchable picker with inline creation. |
| Early 12px capture-card radius | Final capture-card refinement uses 14px; exact component styles in the final cascade win. |
| Robot single-click paste / older double-click Daily | Current design opens Inbox on double-click. Preserve native gesture disambiguation so the double-click does not cause duplicate capture. |
| QA totals 218 / 220 / 253 / 279 in prior notes | Historical. Current reference rerun: 361 passing checks; rendered/native validation is still pending. |

`open-design-v3/specs/FEATURE_CONTRACTS.md` remains the detailed existing-feature reference, supplemented by `TASK_UX.md`, `CONTENT_TRAIL.md`, project-picker components and `RESPONSIVE_QA.md`. Older planning/review pages are context, not an instruction to undo later refinements.

## 2. Product and visual direction

DaBin is a small local macOS capture and organization companion. Capture quickly, connect content to a project, optionally turn it into work, then retrieve it. Keep the compact metallic purple robot, thin app frame and no-sidebar constraint. Use short labels and reveal secondary details progressively; do not delete functionality to achieve minimalism.

| Token | Light | Dark |
|---|---|---|
| Canvas | `#FDFCFE` | `#1D1C21` |
| Surface | `#FFFFFF` | `#252328` |
| Foreground | `#2B2731` | `#EBEAED` |
| Secondary text | `#615A69` | `#A9A6AE` |
| Border | `#E3E0E6` | `#3C3940` |
| Soft selection | `#F3F1F5` | `#2D2A30` |
| Readable accent | `#6D5387` | `#AB92C6` |

Use SF Pro Rounded for display, SF Pro Text for body and monospaced numerals for clocks/receipts; the browser fallbacks are in `brand-spec.md`. Source-supported accent presets and custom preference handling remain functional settings. Keep the robot identity purple independent of the user's action-color preference.

Spacing steps: 4/8/12/16/20/28/32. Frame radius 17px, capture cards 14px, most inputs/buttons 8px. Main body 14px in compact views; card titles 16px; metadata 11–12px; headings 26–30px where appropriate. Read exact task/picker exceptions from their component styles. Use fitted, uncropped content previews, hairline boundaries and restrained shadows. Metallic gradients belong to the robot, not every content panel.

Keep primary navigation labeled. Frequent actions use recognizable icons with accessible names, hover help where enabled, selected/pressed/disabled states and visible keyboard focus. Secondary overflow menus are permitted for infrequent operations. Do not turn the entire product into icon-only navigation.

## 3. Screens and hierarchy

Each root HTML file is a reviewable surface. Native implementation should preserve these routes and behaviors within the existing app, not create 19 separate application windows.

| Reference | Native experience |
|---|---|
| `robot.html` | Compact capture companion: intake, paste/drop, capture editor, last saved item and Inbox access |
| `inbox.html` | New/unprocessed captures, composer, direct per-card actions |
| `today.html` | Planned work, unfinished/unplanned/completed sections, actionable task cards |
| `workspace.html` | Selected project heading and Library collection |
| `clipboard.html` | Same project context; Recent, Pinned and Snippets |
| `shelf.html` | Project collection, membership management and full-shelf export |
| `notes.html` | Persistent project or Unfiled scratchpad and conversion actions |
| `activity.html` / `weekly.html` | Immutable receipt-day archive / week view; scoped search/export |
| `search.html` | Archive retrieval with scope, refinements, nearby context and Back |
| `capture-detail.html` | Original content, source/history, project and actions |
| `task-detail.html` | Task plan, completion, timer, schedule, checklist and original content |
| `new-note.html` / `new-task.html` | Recoverable creation flows |
| `reminder.html` | Separate notification reminder configuration |
| `export.html` | Scope-aware copy/save export |
| `settings.html` | Actual product preferences and native service status |
| `recently-deleted.html` / `backup.html` | Recoverable removal, restore and native archive protection |

`index.html` and `design-review.html` are review aids. Their download links, comparison examples and design-study controls do not belong inside the shipping app.

## 4. Interaction contracts

### A. Capture → task

1. A capture exposes Copy, Project, Turn into task and Keep as direct actions.
2. Turn into task updates the same record. Its visible card immediately becomes a task: square completion control, title, project context, timer and calendar action. Do not require a detail-page detour from a list.
3. Retain record identity, original receipt time/day, source media type, text/files, source app and paste history. Task status is independent of content type; a media capture can also be a task.
4. Provide a brief restrained arrival transition and Undo. Reduced Motion gets immediate feedback. Conversion from capture detail may route to task detail.
5. Keep list position, current frame geometry and content scroll stable. Failed persistence must not announce success; keep recoverable input/state.

Canonical code: `task-ui.js` (`convertCapture`, `taskCard`, `refreshTaskUI`), `task-ui.css`, `model.js`.

### B. Timer and schedule

Every task card has visible completion, duration, start/pause and schedule controls. Hours/minutes entry accepts positive integer duration up to 10,080 minutes (168 hours), with minute input 0–59. An unconfigured Play opens duration setup. The running display is HH:MM:SS with stable monospaced width.

Persist the target end timestamp. Pause stores remaining seconds; resume computes a new end timestamp; reset returns to the configured duration. An elapsed session offers restart. Multiple tasks may retain independent timers. Do not write storage on every UI tick.

Timer expiry leaves the task open. Completing a task stops its timer. A recurring next occurrence begins without a running timer or inherited paste history. Notification reminders are independent: scheduling work or starting a focus session is not permission to create an OS notification.

Workday and optional local time are independent of receipt, deadline and reminder. Provide Today, Tomorrow, Choose date/time and Clear. Title/checklist/notes/priority/repeat/deadline use explicit Save changes; timer/project/schedule commit immediately while preserving those unsaved draft fields.

The prototype uses wall-clock timestamps. Native implementation must handle sleep/wake, restart, clock changes and local calendar/time-zone transitions deliberately, with tests. Do not turn the timer into a time-tracking ledger or calendar integration.

### C. Project selection

Within Workspace collections, replace the generic heading with the selected project name; fallback scopes are All projects and Unfiled. Keep Workspace as the labeled primary destination. The robot header shares the selection.

The heading is a button with folder mark, name and small chevron. Open an anchored searchable panel with direct project rows, current-selection checkmark and New project action. Creation is inline: name, confirm, cancel, concise validation. Successful creation selects the project immediately.

Retain selection across Library/Clipboard/Shelf/Notes and navigation. Long names truncate in the heading while remaining accessible. Search/empty states work; Arrow keys, Enter, Tab/Shift-Tab and Escape behave predictably; focus returns to the trigger. Keep the panel inside visible bounds, including near the bottom edge.

The reference trims and NFC-normalizes new names, rejects empty/duplicate/reserved names, and limits input to 180 characters. Preserve existing native project identities and relationships; do not migrate to name-based IDs merely because the browser fixture uses strings.

Canonical code: `project-picker.js`, `project-picker.css`, `responsive.js`.

### D. Source → destination trail

Show source app logo, directional arrow and up to three distinct destination logos; overflow becomes +N. Clicking the trail opens app names, individual paste timestamps and evidence labels. The adjacent + opens direct app choices or a custom product name. Show the same trail on captures, converted tasks, detail views and the robot's last saved item.

Repeated pastes into one app retain separate history events but share one compact destination mark. Unknown origins remain Unknown source; absent paste history is No pastes. Use a neutral fallback with the supplied product name for unavailable icons. Do not infer source product from the destination of a copied URL.

The current prototype only records manual destinations, labeled Recorded by you. `confirmed` is reserved for a supported successful paste with trustworthy evidence. Clipboard writes, opening an app or observing the frontmost app are not confirmation. Build 53 has no general cross-app paste detector. Keep manual logging useful while evaluating any native adapter; do not add broad monitoring as a shortcut.

Use the included original app icons for reference and native `CaptureApplicationIconCache` for installed products. Do not fetch remote favicons automatically. Icons identify products; their presence does not imply integration or endorsement.

Canonical code/data: `provenance.js`, `provenance.css`, `CONTENT_TRAIL.md`, `assets/app-icons/provenance.json`.

### E. Recovery and retained native behavior

Preserve grouped files, atomic native file-copy behavior, local OCR/search, pins/snippet aliases, per-project scratchpads, full-shelf ZIP export, filter-independent day/week exports, retention protection, Recently Deleted, explicit permanent deletion, verified backup/restore and direct/Store update boundaries.

Captures stay on their original receipt day. Recurrence creates one linked next occurrence without duplicating attachments. Removing shelf membership must not delete its capture. Converting a scratchpad retains its text. Default automatic-capture sources remain opt-in, and capture success/robot feedback occurs only after persistence succeeds.

Use the full 80-row preservation matrix rather than treating this overview as an exhaustive substitute.

## 5. Window, responsive and accessibility contract

Native minimum: 380×430 content / 400×480 outer frame, with approximately 10px sides, 32px head and 18px feet reserved. Only content scrolls; navigation/chrome remain bounded. At content-container widths above 700px, previews/details can use two columns. Smaller windows stack readable content. Browser narrow-width adaptations do not change the native minimum.

Clamp moved/resized windows when available space shrinks; keep compact and expanded geometry separate. Native geometry must use display visible frames, menu bar/Dock safe areas and real backing scales, not copy browser viewport arithmetic blindly. Preserve Spaces/full-screen/focus behavior and recover from display removal.

The previous geometry checks covered 360×640, 390×844, 400×480, 430×360, 600×480, 768×1024, 1024×768, 1440×900 and 1920×1080. These were mathematical assertions, not rendered measurements. Inspect real compact/expanded layouts, long names, content wrapping and short dialogs during implementation.

Desktop icons have at least 32px targets; coarse-pointer reference targets are 44px. Preserve keyboard shortcuts from the native source map and responder-chain text editing. Escape dismisses the innermost transient UI first. Name all icon actions for VoiceOver; selected states need shape/text as well as color. Respect Quiet, Reduce Motion, Reduce Transparency, increased contrast and tooltip preferences.

## 6. Native implementation and migration map

All native paths below are under `source/native/Sources/DaBin/` in this bundle. Locate their current equivalents in the active repository; do not overwrite newer code with the snapshot.

| Work | Reference modules | Existing native owners |
|---|---|---|
| Tokens, shell, navigation | `tokens.css`, `refinement.css`, `views.js` | `ThemeSettings.swift`, `BoardComponents.swift`, `BoardView.swift`, `BuddyControls.swift`, `AppState.swift` |
| Project heading/picker | `project-picker.js/css` | `LibraryScreen.swift`, `WorkspaceStore.swift`, `WorkspaceQuery.swift` |
| Capture/task cards and conversion | `task-ui.js/css`, `views.js` | `CaptureCards.swift`, `WorkspaceItemCard.swift`, `DetailScreen.swift`, `TaskEditorScreen.swift`, `TaskPlanning.swift` |
| Timer/schedule and drafts | `task-ui.js`, `model.js` | `TaskPlanning.swift`, `TaskPlanningEditor.swift`, `Domain.swift`, `AppState.swift`, `DraftArchive.swift` |
| Source/destination trail | `provenance.js/css` | `CaptureSourceView.swift`, `Domain.swift`, existing `CaptureApplicationIconCache` and transactional storage |
| Robot and window geometry | `views.js`, `responsive.js/css`, motion spec | `CornerController.swift`, `RobotCharacterView.swift`, `RobotLifecycle.swift`, `RobotAppFrameView.swift`, `BoardResizeGeometry.swift` |
| Recovery and service preservation | feature matrix/contracts | `CaptureRepository.swift`, `CaptureStore.swift`, `ArchiveBackup.swift`, `WorkspaceStore.swift`, native service owners |

Keep presentation separate from ingestion, notifications and archive ownership. Use the current Core Data versioned payload, Workspace sidecar and DraftArchive boundaries. The browser model is a UX example, not a production schema to transplant.

| Browser reference field | Native adoption requirement |
|---|---|
| `task`, immutable `id/date/time/type` | Map to existing native task/capture semantics; retain original identity and receipt. |
| `planned`, `effort` | Map to existing `TaskPlanning.plannedDay` and `effortMinutes`. |
| `scheduledTime` | Add optional planned local HH:MM if absent, separate from deadline/reminder; clear it with its workday. |
| `focus: {remaining, endAt?}` | Add optional task focus-session state and native lifecycle ownership; timestamps in the JS reference are epoch milliseconds. |
| `sourceProduct` | Optional explicitly supplied identity; do not replace original source receipt fields. |
| `pasteHistory[]` | Optional additive usage ledger: event ID, app identity, ISO timestamp, manual/confirmed kind, optional supplied label/context. |
| project string/scopes | Map to stable native project identity and existing selected-project persistence. |

Decode missing new fields with safe empty/nil defaults. Do not backfill fictional destinations or start timers on migration. Include new fields in snapshot encoding, save transactions, export/backup and additive restore as appropriate. Test old records, failed writes, conversion Undo, completion/recurrence, deletion/restore, interrupted drafts and conflicting backup restore. A separately linked usage ledger must remain referentially and transactionally consistent with capture recovery.

## 7. Implementation sequence

1. Compare repository state with the frozen baseline; inventory the 80 features and identify required additive data migrations. Preserve unrelated work.
2. Implement native tokens, compact shell and shared navigation. Review Inbox at actual minimum size before multiplying screen-specific styles.
3. Implement shared capture/task cards, immediate conversion and project picker; use them across relevant surfaces.
4. Implement persistent focus sessions, planned time and provenance ledger with rollback/recovery tests. Reuse existing native storage and services.
5. Bring Today, all Workspace collections, Activity, search, editors, settings and recovery into visual alignment without feature loss.
6. Integrate robot intake, identity, expressions and ten-reaction choreography using the native motion/lifecycle owners. Prototype study controls stay outside product UI.
7. Run rendered/native acceptance, fix failures, then produce screenshots, changed-file summary, migration notes and test results. Do not call the work flawless with pending gates.

## 8. Editable files and delivery boundaries

CSS cascade: `tokens.css` → `refinement.css` → `task-ui.css` → `provenance.css` → `project-picker.css` → `responsive.css`.

JavaScript order: `model.js` → `provenance.js` → `views.js` → `project-picker.js` → `responsive.js` → `task-ui.js` → `settings.js` → `interactions.js` → `events.js`.

`build.py` inlines these into each product screen. `verify.py` checks the generated/shared alignment. All supplied local assets and native reference files are preserved; `PACKAGE_MANIFEST.json` records their hashes.

Do not port the fixed date `2026-09-30`, Northstar/Mori fixture records, localStorage namespace, browser 8MB data-URL import ceiling, fixture JSON backup or native-simulation messages as real native behavior. No account, cloud sync, analytics, AI, new calendar service, installer or release is part of this handoff.
