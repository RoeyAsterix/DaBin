# DaBin Explorer design acceptance

These are design and later native QA requirements, not a claim that all checks have passed. The implementation status file and native QA receipts are the evidence of completed work.

## Core scenarios

| Scenario | Required result |
|---|---|
| Open a project with mixed captures | Files, media, links, text, and task state are understandable; every stored item remains reachable. |
| Switch Type to Date | Same captures and physical files; no duplicate import; selection retained where visible. |
| Select Unfiled | Only unassigned material; All projects stays distinct. |
| Paste text and import several files | Destination is clear; save feedback truthful; batch members accessible. |
| Move a capture to a project | Same identity/content/date; new physical location and both daily documents agree; failures recover. |
| View a receipt day | One project/day document contains complete chronological text, links, comments, file references, and task context. |
| Edit a comment or complete a task | The underlying saved record and generated document agree after save. |
| Edit a generated document externally | Original edits are preserved before regeneration; no silent structured-data import. |
| Copy or drag a saved file | Finder/accepting app receives the saved file; source original is unchanged. |
| Copy or drag text and links | Correct native representation; no unwanted rich-text conversion or simulated external typing. |
| Duplicate filenames and unusual project names | No overwrite, ambiguous path, traversal, or accidental source mutation. |
| Missing/unsupported file | Stable row; useful type/path/error; remaining metadata, comments, and tasks stay accessible. |
| Convert a capture into a task | Same capture/file; work plan appears; receipt day remains fixed. |
| Delete and restore | Existing Recently Deleted semantics; no external original deletion; regenerated document matches state. |
| Resize during selection/editing | Compact and expanded remain usable; preview grows; selection/query/project/draft survive. |
| Restart | Projects, grouping preference if persisted, captures, notes, tasks, files, and generated documents recover. |

## Responsive and visual review

Review compact 380 × 430 and 380 × 680, intermediate 760 × 680, expanded 1200 × 900, and wide-short 1200 × 430 content areas. Respect the native robot frame’s additional reserved edges. Test continuous resize and display scaling without obscured controls, clipped paths, or excess header space.

In compact mode, a single clear list and readable details take priority. In expanded mode, the preview grows with available space while the list retains readable filenames. An empty selection gets a useful hint, not a large unrelated illustration. Test light/dark and all existing theme colors, increased contrast, reduced transparency, and reduced motion.

Use long filenames, two identical filenames, emoji, multilingual text, long URLs, a multi-page PDF, portrait/landscape images, a large text note, no project, a missing managed file, many projects, and a large archive. Show full titles on demand without requiring tooltips.

## Preservation review

Map every row in `reference/BASELINE_FEATURES.csv` to its retained entry point. Verify Clipboard Recent/snippets, Shelf persistence/ZIP, scratchpad autosave, Inbox triage, Today planning, Daily/Weekly/search/export, task attachment navigation, reminders, OCR, privacy controls, backups, Recently Deleted, settings/update, and robot/window behavior.

Do not imply that creating these design files repeats the baseline QA. Native ingestion, macOS drag providers, Finder behavior, file migration, Core Data persistence, and permissions need separate engineering tests.

## Deliverable evidence

Provide prototype links or local files for each state, before/after captures at matching sizes, accessible names and keyboard order, a completed preservation map, and a list of intentionally deferred controls. Separate designer self-review from feedback collected from real users.

For the native implementation, report tested suites and check counts, build/lint/static checks, data migration coverage, actual copy/drag/resize/restart interactions, and unverified OS or target-app behaviors. Do not mark a scenario complete based solely on a wireframe.
