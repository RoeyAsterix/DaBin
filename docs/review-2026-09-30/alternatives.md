# Navigation and feature choices

These are design judgments grounded in the source and isolated native review. They are not claims about market research or measured user-study outcomes.

## A. Inbox / Today / Workspace — selected direction

A three-part labeled navigation row gives each destination one job:

- **Inbox:** receive and organize new material, with a small text composer and direct paste/file actions.
- **Today:** decide what to work on; tasks planned for today, reminders and overdue work remain distinguishable.
- **Workspace:** retrieve project material, clipboard references, saved snippets, temporary shelf items and project notes.

Activity remains a date-based receipt history available from Inbox. Search spans the archive, then returns to the user's previous context.

Expected interaction cost: one click to switch primary destinations. An inline note uses a field focus, typing and a commit instead of opening a menu and editor. Context restoration removes the observed extra filter-repair click. These improvements must be rechecked in the current app before calling them measured.

Benefit: clearer intent while preserving the compact window and avoiding a sidebar. Cost: state restoration and terminology must remain consistent across three surfaces. The current architecture can reuse existing captures and views; it does not require a new rendering stack.

## B. One activity feed with a view chooser

Keep the calendar feed as the main surface and switch to tasks or projects through one labeled view menu.

Benefit: the least permanent navigation chrome and continuity with the original “everything I did today” concept. Cost: switching destinations is normally two menu actions instead of one visible tab, and users must infer whether Today means recorded activity or planned work. This does not address the baseline ambiguity as directly as A.

Useful fallback if the smallest supported window cannot fit three labels without reducing hit targets. Prefer reducing spacing before hiding controls.

## C. Tiny capture bar plus a full workspace window

A narrow capture composer offers paste/drop/quick text; a separate full window handles planning and retrieval.

Benefit: minimal screen occupation during capture. Cost: another surface, extra open/close transitions, focus coordination, display placement, keyboard routing and draft handoff. The robot already provides a compact capture entry point, so a second tiny surface risks duplication.

Keep this as a later opt-in keyboard workflow. Resolve compact main-window layout and context retention first.

## Feature decisions and trade-offs

| Capability | Concrete benefit | Cost / complexity | Decision |
| --- | --- | --- | --- |
| Preserve drafts and project/filter context | Avoids lost writing and repeated navigation | Moderate: durable writes, stale references, recovery tests | Core requirement; verify restart and failure paths. |
| Inbox quick note and explicit Today planning | Separates capture from commitment | Moderate: clear filing/planned-state semantics | Include, with concise visible labels. |
| Project notes, snippets and shelf | Keeps reusable text and working files beside their source captures | Moderate: references, exports, missing-item handling | Include through existing local records; shelf removal must not delete captures. |
| Task checklist, estimate and priority | Makes a captured idea actionable without a separate task app | Moderate: editor density, validation and completion behavior | Use progressive disclosure; keep the basic task concise. |
| Recurring tasks | Useful for a small set of routines | High: calendar/DST, missed periods, duplicate occurrences | If included, require dedicated recurrence tests and one clear future occurrence. Avoid adding more scheduling rules during UI polish. |
| Bulk organization | Saves work for a large Inbox | Moderate: selection state, rollback, mixed eligibility | Keep only explicit, reversible actions with visible counts; verify single-item flows first. |
| More animation variants | Expresses the robot's character | Moderate rendering and interruption complexity; small productivity benefit | Prioritize responsive existing motion, reduced motion and idle efficiency. |
| Automatic website favicon requests | Helps recognize web sources | Network privacy, offline/error handling, cache invalidation | Prefer local app icons and domain fallback unless the user has enabled network previews. Never invent a paste destination. |
| Semantic cloud classification or collaboration | Could reduce manual filing or share work | High privacy, accounts, sync conflicts and operating cost | Defer; local capture and retrieval remain the core value. |
| New large animation/UI dependency | May speed a narrow implementation | High maintenance, bundle size and integration cost | Reuse native SwiftUI/AppKit and existing robot artwork. |

## Compact-layout guardrails

- Main header height must remain bounded when the window gets taller.
- A narrow window must retain meaningful working content below navigation; resizing cannot reserve most of the surface for chrome.
- Icon-only controls need a stable accessible name and optional tooltip. Destructive actions keep explicit labels or confirmation.
- The robot frame reserves its own edge space; decoration must not intercept content clicks.
- Expanded width should create useful columns, not larger empty gaps.
- Search and temporary editors return to the same project, filter and collection context.
