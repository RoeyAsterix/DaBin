# DaBin 0.4.2 — connected daily work

Build 51 is a local development candidate. Publication, TestFlight delivery and Apple approval are separate steps.

- Inbox makes paste, file import, quick notes and task creation visible. Activity retains the date-based capture history.
- Today separates planned work, deadlines and reminders; adds priorities, effort, ordering, checklists, repeat rules and completed-task review.
- Workspace connects optional clients/projects with Library, Clipboard, Shelf and Notes. Recent copies stay accessible alongside named snippets.
- Project scratchpads autosave locally; unfinished note/task/comment/planning drafts recover after restart.
- Universal search includes project names, snippet aliases, task steps and saved scratchpads, with explicit project/application scoping.
- Shelf items can be attached to an existing task and exported as a verified ZIP. Removing a shelf reference keeps its saved original.
- Opt-in clipboard retention and confirmed clearing move eligible unfiled automatic copies to Recently Deleted. Tasks, reminders, pins, projects, snippets, shelf items and deliberately kept Inbox items are protected.
- Workspace content is included in verified archive backups. Conflicting authored notes are preserved and reported during restore.
- Header spacing is bounded, the drag affordance is visible, expanding preserves the restore frame, and occlusion no longer hides the content itself.
- Reopening resumes current work; Back restores search/project context; closing restores the working application's focus when appropriate.

Schema 9 remains compatible with older saved captures. Core workflows remain local. Imported files remain managed copies with original source provenance; this release does not add live folder synchronization or automatic external AI processing.

See [product review](review-2026-09-30/README.md), [implementation order](review-2026-09-30/IMPLEMENTATION-PLAN.md), and [roadmap](review-2026-09-30/ROADMAP.md) for evidence and limitations.
