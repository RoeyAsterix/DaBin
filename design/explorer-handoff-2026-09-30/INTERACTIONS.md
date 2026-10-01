# DaBin Explorer interactions

The following interaction contract guides design and engineering. The implementation status file records which parts are available in the accompanying code revision. Keep proposed controls out of a claimed working prototype until they have an end-to-end behavior.

## Browse and resume a project

1. Open Workspace and choose Explorer.
2. Choose a project or Unfiled. All projects remains available.
3. Group the results by Type or Date. Filtering narrows this view without moving stored data.
4. Select a row to preview it. Open full details for comments, reminders, attachments, and the work plan.
5. Return or resize. Preserve project, refinements, grouping, selection, and drafts. New incoming captures must not steal selection or jump the user to the top.

Keep project names visible in All projects. Distinguish the receipt date from a task’s planned day, deadline, or reminder. A task made from an image belongs in both Media and Tasks filters but remains one saved item.

## Capture into a project

Offer Paste and Import files alongside drag-and-drop. When a project is selected, name that destination in feedback. With All projects selected, default new material to Unfiled rather than guessing a client.

The drop highlight belongs to the receiving area, not the whole screen. Show one clear saving state and success after persistence. A failed import retains enough context to retry. For multiple files, preserve the app’s batch relationship while allowing access to every member.

## Reuse saved material

| Selected content | Copy | Outgoing drag |
|---|---|---|
| Managed document or image | Actual saved file URL | File item provider understood by Finder and accepting apps |
| Link | URL | URL representation, with text fallback where supported |
| Text or note | Captured text | Text representation |
| Generated daily document | Actual dated Markdown file | The readable file, with no internal metadata export |

Receiving applications determine which representations they accept. Show a normal file affordance rather than promising every browser drop target accepts every type. Copy as plain text is a separate action where useful. Copy path and Reveal in Finder use the same saved file the normal Open action uses. The external original, when available, is a separate clearly labeled action.

Do not initiate typing into another app or request Accessibility permission solely to support reuse. Preserve native editing shortcuts inside text fields; Command-C/V must not unexpectedly copy/import the selected record while someone is editing a comment.

## File an item under another project

Provide a project action as the accessible alternative to drag filing. Show the new project after success and keep the selected item findable. The underlying capture ID, original receipt date, task relationship, comment, and reminder remain intact. Regenerate affected daily documents after saving.

A same-name file must get a unique safe destination; show the resulting name. A missing source, permission error, or interrupted move must leave a recoverable record and explain what was saved. Do not silently report a completed move after only the metadata changed.

## Read a daily document

The list label uses a friendly date, while the filename begins `YYYY-MM-DD`. Mark the item as a daily document with a document/calendar icon, a small capture count, and its project. Selecting it shows its readable contents and file actions.

Use this microcopy where needed: **“A readable copy of this day’s saved captures. Edit items in DaBin to update it.”** Editing a source capture updates the generated document after successful persistence. If an outside editor changed that file, preserve the prior file before replacing generated content and show the preservation location when relevant.

## Tasks and related records

The task toggle transforms the same capture. Keep its content preview, source, comments, and files. Reveal the work plan only when the item becomes a task. Deadline, planned day, reminder, recurrence, checklist, priority, and effort retain their existing meanings.

Opening an attachment exposes its task relationship and a route back. Existing saved material attached to a task must remain reachable through search and task details without duplicate file copies. Ordinary attachment unlinking is not part of the baseline feature set; propose it separately if needed.

## Keyboard and accessibility

- Tab order follows visible layout; focus is visible and never conveyed only by color.
- Icon-only actions have tooltips and stable accessible names. Tooltips can be off without removing names.
- Project and grouping menus support standard keyboard selection and Escape dismissal.
- Selection, task state, missing file, and migration/saving status have useful spoken labels.
- Compact detail has an obvious Back action. Escape dismisses the innermost transient interaction before any normal window close behavior.
- Preserve native copy/paste in editors and the app’s existing global shortcuts.
- Reduce Motion avoids animated relayout or sweeping preview transitions. Large text, long names, emoji, and right-to-left content must remain readable.

## Recovery language

Use concrete messages: “Saved to Northstar,” “Copied file,” “This saved file is unavailable,” or “Couldn’t update the archive. Your capture is still saved.” Tailor the latter to actual persistence outcome; do not claim data is safe without confirmation.

The generated document, original external file, managed copy, and DaBin record are different concepts. Explain them only at the relevant action. Ordinary browsing should stay friendly and uncluttered.
