# Copy this assignment into Codex

Implement the supplied DaBin design and user experience in the existing native macOS DaBin app. Use the extracted handoff folder accompanying this prompt; locate `START_HERE.md` there. Work in the current app repository and keep the handoff's `source/native/` frozen.

Read `DESIGN_UX_HANDOFF.md`, `open-design-v3/DESIGN.md`, `ACCEPTANCE_CHECKLIST.md` and `HANDOFF_QA.md`, then review the actual interactive HTML screens. Use `open-design-v3/FEATURES.csv` and `IMPLEMENTATION_MAP.md` to preserve all 80 existing features. Compare the live repository with the supplied native 0.4.2 (53) baseline before editing; preserve changes made after that baseline.

The direction is settled. Implement the design; do not restart discovery or replace it with a generic dashboard. The required experience is:

- A compact macOS companion, metallic purple robot identity, neutral surfaces, minimal copy, content-led cards and no permanent sidebar.
- Labeled top navigation for Inbox, Today, Workspace and Activity; direct icons for frequent actions, with accessible names and helpful states.
- Capture-to-task conversion visibly transforms the same item into a task card in place, with completion, hours/minutes timer, start/pause and schedule controls. Preserve receipt, original content, attachments and provenance; provide Undo.
- Project name replaces the generic Workspace heading. Clicking it opens the searchable project picker with selected-state feedback and inline New project. Selection persists across collections and navigation.
- Source app logo → paste destination logos on captures, tasks and the robot's last item, with readable history and times. Copying is not proof of pasting. Manual records stay labeled; confirmed receipts require a genuinely supported successful paste operation. Do not invent automatic cross-app detection.
- Compact and expanded layouts, bounded windows/popovers, long-name handling, recoverable drafts, keyboard access, dark mode and reduced motion.

Translate the reference into native SwiftUI/AppKit components and the existing state/services. Do not ship the HTML/localStorage implementation, a WebView wrapper, the fixed fixture date, fictional records, browser file limits or browser backup format as production behavior.

First report a concise implementation plan with the target native files, migration needs and any actual conflicts with newer repository code. Then proceed through shared tokens/shell, core cards and project selection, timer/scheduling and provenance state, remaining screens, robot behavior, and acceptance validation. Use the existing persistence and native services; do not build a parallel data store. New fields must decode old records safely and survive backup/restore, failed saves and restarts.

The timer and planned time are explicitly requested additions even though the older baseline source map lists focus timers as deferred. This does not authorize calendar sync, time tracking, AI, accounts, cloud services or unrelated roadmap features.

Review light/dark native windows at minimum and expanded sizes; test actual focus, popovers, resizing, task conversion, timer sleep/wake, provenance, recovery and accessibility. Preserve the existing automated suites and add meaningful tests for the new state transitions. Run the repository's documented build/QA commands and `git diff --check`. Report observed results, screenshots and remaining gaps separately; the supplied 361 checks are reference checks, not a native acceptance certificate.

Finish with implementation changes, migration behavior, executable validation results, screenshot paths and unresolved native gates. Do not publish, install over the user's app, replace a real archive or release a binary as part of this design implementation unless separately requested.
