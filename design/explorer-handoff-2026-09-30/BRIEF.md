# DaBin Explorer design handoff

Design DaBin’s project file explorer so freelancers can collect something, connect it to a project, act on it, and find it again. The Explorer should make the app’s local archive understandable and let people reuse saved material through ordinary macOS copy, paste, and drag interactions.

This is a focused addition to the existing native app. **Workspace → Library becomes Explorer; Clipboard, Shelf, Notes, Inbox, Today, Activity, search, settings, and the robot remain available.** Improve their connections without removing their features.

## Product decisions

- Projects are optional. Offer **All projects**, named projects, and **Unfiled**. Capture first; file later.
- Show one saved capture as one recognizable record, with its actual saved files, text or URL, comments, and task status connected. Avoid separate rows for internal JSON, index caches, or manifests.
- Offer **Group by Type** and **Group by Date**. These are alternate views over the same local files, not duplicate collections. Keep the actual path available through the selection.
- Create one readable **daily document per project per receipt date**, containing that day’s captions, links, comments, and task context. Include Unfiled. Name it with the ISO date so it sorts predictably.
- Keep each task’s original material connected when planning, rescheduling, completing, or reopening it. These actions never change its receipt date or duplicate its files.
- Copying or dragging out uses DaBin’s saved content. The source application/path is attribution, not a promise that the external original still exists.

## Local storage and daily documents

The hierarchy is `Projects / project / year / numbered month / named day`, with **Files**, **Media**, and a dated **Captures and Links.md** document. Unfiled follows the same year-to-day structure. Project folder names include a deterministic identifier; original filenames include the capture ID before the extension. These suffixes prevent collisions, including names that differ only in case. Show friendly labels in the UI and the real path in file actions.

```text
DaBin/
  Projects/
    Northstar — <project ID>/
      2026/
        09 September/
          30 Wednesday September 2026/
            Files/Proposal — <capture ID>.pdf
            Media/Landing reference — <capture ID>.png
            2026-09-30 - Captures and Links.md
  Unfiled/
    2026/…
```

The daily document includes original timestamps, type, available source, text or URL, available OCR, relative file links, comments, task status, checklist, and available scheduling information. Order entries chronologically, including child attachments under their original receipt dates and their parent task’s effective project. A task’s updated state belongs under its original receipt date. Moving it to another project updates the source and destination documents; it must not create another capture.

The document is a **generated readable view** of saved records. Edit captures and comments in DaBin. Preserve user changes made to generated files in Finder before regeneration in **Local edits**, with a recovery copy included by archive backup. Never silently treat external edits as structured task updates. Keep internal metadata outside the ordinary Explorer list.

Core Data and the existing capture store remain authoritative. Migration and file operations must verify results, retain recovery information, reject path traversal and symlink surprises, and handle duplicate filenames without overwrite. External originals are never relocated or deleted by filing a capture in DaBin.

## Compact and expanded layout

At compact width, use a project picker, short mode row, search/refinements, grouping control, and one readable item list. Selecting an item opens the existing detail route. Keep a visible Back action that restores the previous project, search, grouping, selection, and scroll position. There is **no permanent sidebar**.

At expanded width, show the same list beside a generous preview/details pane. The selected image, PDF, or text grows with the window; fit media without cropping. Keep comments and task controls close to the preview. Reuse the existing full detail page for complete editing rather than creating divergent task forms. The design may suggest an inspector, but its engineering status must be explicit.

Prefer one stable toolbar. Use labels for ambiguous choices such as Group by Type/Date; recognizable SF Symbols with hover tooltips and permanent accessible names for common actions. Keep touch targets and focus outlines consistent with DaBin’s current icon controls. Tooltips may be disabled in Settings, accessible names may not.

## Selection and useful actions

Frequent actions should be available on the selection: preview/open detail, copy, open saved file or URL, reveal saved location, copy path, choose project, and create/open a task. Preserve existing pin, snippet, Shelf, reminder, and removal actions.

Copying a file places its actual saved file URL on the clipboard. Copying a link produces the URL; copying text produces text. Plain-text copy is explicit. A daily document can be opened, copied as a file, or dragged as a file where implemented. A visible action menu provides alternatives to gestures.

Dropping into a project should name and highlight the destination before release. Dropping a saved DaBin item files it without duplicating it; dropping external content imports a managed copy. Dropping onto a task attaches it only when that target is explicitly available. No invisible destructive drop zones.

## States that need design

Provide usable states for no captures, empty project, filtered empty result, no selected item, importing, saving, failed save, missing saved file, unsupported preview, moved external source, generated document unavailable, and incomplete archive migration. Offer specific recovery actions, retaining the selection and query.

Distinguish **Remove from Shelf**, **Move to Unfiled**, **Move to Recently Deleted**, and permanent deletion. Collapse/minimize must never resemble deletion. Do not promise undo where the implementation cannot restore the complete operation.

## Features that must survive

Use the included `reference/BASELINE_FEATURES.csv` as the full preservation checklist. Particular risks for this feature are file batches, hourly auto-capture groups, task attachments, pin/snippet aliases, separate workday/deadline/reminder, project scratchpads, local OCR/search, export ignoring filters, and recoverable deletion/backup.

Preserve best-effort source attribution, local processing, opt-in automatic capture, exclusions/pause, screenshot protection, themes, opacity, Reduce Motion, robot placement, keyboard shortcuts, and direct/Store update boundaries. Do not introduce accounts, cloud storage, analytics, AI processing, folder watching, or external-file mutation through a visual redesign.

## Deliverables for Open Design

1. A clickable compact and expanded Explorer design with selection, project changes, type/date grouping, daily document, drag feedback, error and empty states.
2. A component specification covering normal, hover, pressed, selected, keyboard focus, disabled, loading, and error states in light/dark themes.
3. An old-to-new action map against the preservation matrix; no capability silently disappears.
4. A practical specification for native SwiftUI/AppKit implementation, including responsive breakpoints and keyboard behavior.

The supplied SVGs are **low-fidelity proposals with fictional data**, not app screenshots or proof of implemented interactions. Use `IMPLEMENTATION_STATUS.md` to distinguish current code from the design contract before presenting any action as available.
