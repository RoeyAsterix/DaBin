# DaBin product review — implementation order

Scope: native macOS 14+ on Apple silicon. SwiftUI inside AppKit panels, Core Data capture receipts, local managed originals, system Vision/PDFKit text extraction. This is an internal expert review with synthetic workflow tests, not a study with recruited users.

## 1. Reliability and orientation

- Preserve the running personal archive and isolate review fixtures.
- Capture the old native UI and actual navigation counts before changing it.
- Fix the expanding header drag region, visible drag affordance, expanded-window restore geometry, and occlusion feedback loop.
- Resume the current route when reopening; restore the working app after dismissal only when DaBin still has focus.
- Preserve project/filter/selection while moving between search, details, compact, and expanded presentation.
- Recover unfinished composer and detail drafts locally; report persistence failures.

## 2. One connected workflow

- **Inbox:** fast note/task capture, paste/import/drop, optional filing and task conversion. Activity keeps the original date-based history.
- **Today:** deliberate workday planning, separate deadline/reminder, priorities, reorder, estimates, repeat rules, checklist, completed review, and rescheduling.
- **Workspace:** optional client/project context shared by saved resources, clipboard, shelf, and notes.
- Search the entire capture archive, recognized text, project names, snippet aliases, checklist steps, and saved scratchpads. Scope explicitly when desired.

## 3. Trustworthy persistence and file operations

- Keep originals in the existing local managed archive. Source paths are provenance; moving a source file does not break the saved managed copy.
- Keep shelf membership and snippet names as references, so removing them never deletes an original.
- Autosave per-project scratchpads and make failed saves retryable.
- Include workspace content in verified archive backups; reject conflicting authored text during restore.
- Preserve old schema data and recurrence lineage; avoid duplicating task attachments for every repeat.
- Offer opt-in retention and recoverable clipboard-history clearing with an exact confirmation count.

## 4. Verification and delivery

- Test data transactions, failure rollback, recurrence boundaries, clipboard serialization, source-filter intersections, recovery, and archive/ZIP round trips.
- Test native keyboard/AX interactions and layouts at minimum, laptop, and expanded sizes, with light/dark themes and mixed-language/long content.
- Run the existing native suites and build with warnings treated as errors; regenerate/check the Xcode project.
- Re-run representative workflows in the actual SwiftUI/AppKit application using a synthetic archive, compare screenshots and counts, and measure startup/search/idle behavior.
- Install the verified local build while preserving existing data and any unfinished live draft. Do not publish a release or claim App Store approval as part of this review.
