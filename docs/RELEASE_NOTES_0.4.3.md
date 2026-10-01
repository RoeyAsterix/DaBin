# DaBin 0.4.3 Explorer candidate

Build 55 adds Explorer to Workspace on Apple Silicon Macs running macOS 14 or later. This is a local development candidate, not a claim of GitHub release, notarization, or TestFlight availability.

## Browse saved work

Explorer replaces the Library tab with compact file rows, type or date grouping, project search, a project selector with Unfiled, and an expanded preview pane from 760 points wide. Existing Clipboard, Shelf, Notes, Inbox, Today, Activity, tasks, settings, and recovery remain available. Compact rows open full capture details; wide rows preview in place and offer Details for editing.

Paste and Files save into the selected project. All projects intake saves to Unfiled. Incoming files keep their external originals. Dragging a capture onto another project moves its existing record and offers Undo. Native outgoing representations provide saved files, URLs, or original text to compatible applications. Existing captures can attach to tasks without duplicate file imports.

Daily files shows one Markdown document per project and receipt date. The document contains the full stored day, including text, links, comments, tasks, reminders, source information and file references. Filters can narrow which daily files appear; they do not trim the content of a file. Daily files can be opened, copied, dragged, revealed in Finder or exported together as a ZIP. The inspector limits very long previews; the saved file remains complete.

## Local storage

Saved originals live under Projects or Unfiled, followed by year, named month, named day, and Files or Media. Project folder suffixes distinguish names that collide on macOS; original filenames include their capture identity so a second file never replaces the first. The UI keeps readable titles.

Existing managed originals migrate with a journal, verified copy, committed database path, and removal of the unchanged former managed copy. Receipt dates and external source files stay intact. Task attachments follow their task’s project. Private per-capture recovery sidecars remain in the established Archive tree.

Daily Markdown is generated from stored captures. Outside edits are preserved under Local edits before replacement and included in capture backup recovery copies. Synchronization failures retain recoverable data and expose an archive warning. Trash and permanent deletion understand the new managed paths. Archive backups validate and restore both older and new layouts.

## Remaining scope

Physical file renaming, project rename/deletion, whole-folder import, ordinary task attachment unlinking, and multiple-row selection are deferred. The Open Design handoff labels these separately from implemented actions. Drag compatibility depends on the receiving application. Large existing-file relocations still perform synchronous verification; moving a very large file can briefly pause the interface. Core capture data remains local.

All 53 Release QA suites and 20 Explorer renders passed. Build 55 is installed locally; existing capture identities and attachment bytes were verified after migration. See [verification, screenshots and limitations](qa/explorer-2026-09-30/README.md).
