# DaBin 0.4.25 (80) — preview-first projects

Named projects have a unified, preview-first workspace. Files, images, captures,
links, tasks, task attachments and the project's live notes appear together.
The all-project Explorer keeps its existing presentation.

- Larger local previews, quieter project-color frames, clear receipt timestamps,
  responsive grid/compact layouts, and fewer permanent controls.
- Click a file preview to open its saved original; click its title for details.
  Text opens its capture details; project notes open the existing editable notes.
- Select multiple cards with their checkboxes, Command-click previews, or use
  Shift-click for a range. Command-A on a focused card selects visible items.
  Filters clear hidden selection. Bulk actions appear only after selection.
- Reorder with the card handle or Move earlier/later. Order is saved per project
  in the backup-compatible workspace record. Reordering is available in All,
  Any date, My order; it never changes a receipt date or original file.
- Make selected captures into tasks in one metadata transaction. Original text,
  file bytes, kind and receipt are retained. Promoted attachments retain their
  current inherited project. Undo is independent of ordering and refuses to
  discard later saved or unfinished task edits. Live project notes stay editable;
  use their notes editor to save a copy as a task.
- Copy original items (native file URLs, links and text), or copy one readable
  summary. The destination application decides which native clipboard types it
  accepts. Project notes retain their position in the ordered copy.
- Export the entire project or only selected items as one local ZIP. Includes
  original files, text, links, task/checklist metadata, project notes, a readable
  index and an ordered manifest with content hashes. Whole-project actions ignore
  view filters. Missing or changed originals fail the export instead of silently
  producing an incomplete package. Existing destinations are never overwritten.
- Native recycled list rows and the existing bounded thumbnail cache keep rich
  previews limited to the viewport. New capture grouping preserves old row
  identities instead of rebuilding every row after an insertion.

No cloud indexing, upload, public release, or App Store submission is introduced.
Installed locally with a prior-app backup. All 16 focused Release suites pass;
see the [verification record](qa/project-workspace-0.4.25-2026-10-03/README.md).
