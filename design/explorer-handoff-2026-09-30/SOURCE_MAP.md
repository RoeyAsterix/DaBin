# Explorer source and native behavior

The implementation lives in the DaBin repository under `native/`. The handoff ZIP includes a snapshot of current runtime source, resources, and standalone local build scripts beside the design documentation and synthetic references. It is not an installer. `SOURCE_SNAPSHOT.json` records exact bytes; `NATIVE_BUILD_NOTES.md` describes its build scope. Use this map with the final implementation status.

## Ownership

| Source under native/Sources/DaBin | Responsibility |
|---|---|
| LibraryScreen.swift | Workspace mode shell and existing Clipboard, Shelf, Notes, project creation, and filters. Collection mode now hosts Explorer. |
| WorkspaceStore.swift | Keeps the serialized collection mode compatible while displaying **Explorer**; persists query, grouping, Unfiled scope, daily-file mode, and project selection context. |
| ExplorerScreen.swift | Search and intake toolbar; Type/Date grouping; **Daily files** toggle; compact rows and expanded split preview; actual file/path operations; visible-items ZIP. |
| ExplorerItems.swift | Capture rows, copy action, inspector, contextual actions, project picker, and highlighted project drop targets. |
| ExplorerQuery.swift | Project and Unfiled filtering, inherited task attachment project, text/OCR search, type/date grouping. |
| ExplorerTransfer.swift | Native item providers for outgoing file/URL/text; internal capture identity; fixed-destination incoming paste/drop/import; project move and guarded Undo; task attachment intake. |
| ProjectFileArchive.swift | Deterministic project/day paths, collision-safe saved filenames, generated daily Markdown, outside-edit preservation, and journaled original relocation. |
| CaptureStore.swift | Authoritative mutation and persistence coordination; managed paths, synchronization/retry, task relations, trash/restore, and old archive compatibility. |
| DailyArchive.swift and OriginalFileStorage.swift | Existing dated metadata archive, path/regular-file safety, staging and atomic file handling. |
| AppState.swift | Explorer input integration, route and current project, capture completion feedback, intake routing, and existing app actions. |
| CaptureClipboard.swift and WorkspaceClipboard.swift | Native system clipboard representations, explicit plain text and actual managed-path copy. |
| TaskAttachmentsView.swift | Existing task attachment UI; internal capture drops reuse the Explorer transfer path through AppState. |
| DetailScreen.swift and CapturePreviews.swift | Shared full editing route, responsive fitted preview, comments, reminders, task plan, source, and attachment details. |
| ArchiveBackup.swift and CaptureRemoval.swift | Existing backup/restore and recoverable-deletion semantics integrated with managed project originals. |

Keep these boundaries. A design prototype must not implement a second capture database, its own reminder scheduler, or an independent copy of task fields. The full detail page remains the complete editing surface; the expanded Explorer inspector is a selection preview with contextual actions.

## Current UI distinction from the concepts

The current implementation switches between capture rows and generated documents with the **Daily files** toggle. Grouping by Type/Date applies to capture rows and is disabled in Daily files mode. Active refinements determine which project/day documents appear; each displayed document contains the complete stored project day. Filtered rows do not create a truncated daily document.

At widths below 760 pt, activating a capture opens its existing detail page; activating a daily document opens the saved Markdown file in its default application. At 760 pt and wider, selecting a row shows an inspector beside the list. Complete editing remains behind **Details**. The SVG concepts explore an integrated Daily documents section and more exposed actions; those differences are design suggestions.

The project picker is a popover with All projects, Unfiled, named projects, and New project. The native code opens it after a short drag hover so named project and Unfiled drop targets can be reached. The item menu offers Move to project as the alternative to dragging. Task attachments follow the parent task’s project; moving an attachment independently is rejected with guidance. Live gesture verification remains separate from this code description.

Explorer’s ZIP action exports the visible capture set, or the visible daily documents when Daily files is selected. Each exported daily document is complete even though its in-app preview is bounded to 64,000 bytes. This is separate from existing **Shelf ZIP**, which exports the entire selected project shelf, and Day/Week text exports, which ignore active content filters. Preserve those distinctions.

## Transfer and data semantics

Outgoing native providers expose file URLs for managed files, URLs for links, and plain text for text captures. Internal drags also include a capture identifier so moving a saved item within DaBin does not import another copy. Normal copy/paste remains copy semantics. There is no simulated paste into another app.

Project drop intake fixes its destination when the action starts, so switching projects during a slow import cannot retarget it. File imports retain external originals. Internal task drops attach by record reference. Undo project move checks whether the item changed after the move and avoids overwriting later edits.

The physical explorer hierarchy is backed by actual managed originals and generated Markdown. Internal metadata, journals, temporary work, and hidden trash are not normal Explorer rows. The readable document is regenerated from saved captures; it is not a second editable task database. When the final capture leaves a project/day, remove its generated daily document after preserving any outside edits. Backup synchronizes readable documents first so external changes are included in recovery.

## Deliberately outside this implementation

- Rename a physical saved file, rename/delete a project, and bulk multi-selection operations.
- Import arbitrary folders, aliases, or symlinks, or watch arbitrary project folders for changes.
- Live references to external files, two-way Markdown synchronization, cloud sync, or file changes in external applications.
- Ordinary task attachment unlinking, general file utilities, focus tracking, calendar integration, or AI.

These may be considered in later design, but do not present them as available controls. Existing saved regular-file intake and per-item management remain the reliable path.

## Verification source

`native/Tests/ExplorerQueryTests.swift` covers filtering and grouping. `ExplorerTransferTests.swift` covers provider representations and identity/transfer behavior. `ProjectFileArchiveTests.swift` covers project paths, generated documents, migration, and file safety. Existing Workspace, WorkspaceWindow, ArchiveStore, ArchiveRecovery, task conversion, archive backup, and native rendering suites cover shared behavior. Final completed runs and limitations belong in `IMPLEMENTATION_STATUS.md`; the existence of a test file alone is not evidence it passed.

Relocating existing large originals currently performs file copy/hash work on the main actor. A large migration or project move can pause the interface; resource behavior under large histories needs measured verification. This is a known engineering limitation, not something to mask with an animation or promise of instant filing.
