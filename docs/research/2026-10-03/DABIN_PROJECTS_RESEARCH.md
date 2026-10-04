# Research on improving DaBin Projects

Reviewed on 3 October 2026 for DaBin’s owner and the product, design and implementation team.

The recommended direction is one project screen for finding material and taking the next action. Remove Shelf from primary navigation while preserving its existing collected items. Use one search, one result list and contextual actions. Begin with capture destination, search consistency and project context; keep project organization optional.

Revised after the owner's UX simplification request on 3 October 2026. The earlier Overview / Materials / Tasks proposal adds too many destinations for a small desktop companion. The recommendation below replaces it with All items / Tasks quick views and an optional Resume row.

This brief combines a read-only review of DaBin 0.4.23 (78) source with official documentation from comparable products. The workflow problems are code-derived findings; their effect on users is a hypothesis to validate. No live usability sessions, participant interviews, new performance measurements or application tests were conducted for this research. The recommendations below are proposed changes.

## What DaBin already provides

Projects already connects Explorer, Clipboard, Shelf and Notes. It includes project colors, project-aware intake, managed local files, dated Markdown records, OCR/document search, previews, copy and drag-out actions, internal filing with undo, task conversion and attachments. Selected items are remembered per project. These capabilities should remain available through the redesign.

The useful distinction is between the project’s work and ways of viewing it. A screenshot can be a resource, a task’s attachment and a daily capture without becoming three independent copies. Clipboard, Shelf and date/type views should keep referring to those same records.

## Findings in the current implementation

| Finding | Practical risk to test | Recommendation |
| --- | --- | --- |
| The selected browsing project supplies Auto Capture’s destination. | Visiting Client B while working on Client A can route new copies to B. | Add an independent, visible capture destination. |
| Item selection is stored per project, but mode, query, date/source filters and grouping are shared. | A filter from one project can make another project appear empty. | Restore the whole working context per project and show removable filter chips. |
| Project identity is an exact name string; creating a project adds an empty scratchpad marker. | Rename, archive and client grouping would affect several stores and name-derived paths. | Introduce a stable project record before adding lifecycle actions. |
| Explorer, Clipboard, Shelf and Notes have equally prominent mode controls. | Users must decide which workspace to enter before finding an item; saved references and content types can seem like separate storage. | Consolidate around one project list, with task and secondary saved views. |
| A project opens its workspace mode and resources; there is no resume cue. | Users must reconstruct what they were doing. | Add one optional Resume row using the last relevant item, without a separate overview page. |
| Explorer’s ordinary selection is one item. | Filing a batch of client materials requires repeated actions. | Add familiar multiple selection and a contextual action bar. |
| Explorer and global search index different fields; global search includes checklist text that Explorer omits. | A task can be found globally but missed inside its project. | Share one search-field policy across scopes. |
| Explorer ZIP exports visible filtered items; Shelf exports the full shelf. | Neither clearly represents a complete project delivery. | Distinguish selected, visible and complete-project export. |

Evidence: [capture routing](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/ApplicationCoordinator.swift:68>), [workspace state](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/WorkspaceStore.swift:74>), [project creation](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/WorkspaceStore.swift:254>), [workspace controls](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/LibraryScreen.swift:55>), [Explorer search](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/ExplorerQuery.swift:46>), [global search](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/Domain.swift:480>), [Explorer export](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/ExplorerScreen.swift:359>).

## Patterns worth adapting

| Official source | Documented pattern | Proposed use in DaBin |
| --- | --- | --- |
| [Things project guidance](https://culturedcode.com/things/support/articles/8491676/) | Break large goals into tasks and concentrate on the next one to three steps. | Show a small Next actions section rather than demand a complete plan. |
| [Things scheduling](https://culturedcode.com/things/support/articles/2803579/) | Planned start dates and deadlines answer different questions. | Preserve DaBin’s work-day and deadline distinction in project task summaries. |
| [Linear project overview](https://linear.app/docs/project-overview) | A project overview combines summary, properties, documents, links and milestones. | Bring the brief, next task and key resources together; keep milestone planning optional. |
| [Notion linked databases](https://www.notion.com/help/guides/using-linked-databases) | Multiple filtered views can show the same underlying records. | Use project sections and saved views without duplicating captures or originals. |
| [Raycast Quicklinks](https://manual.raycast.com/quicklinks) | Named, searchable shortcuts to websites, files and folders can be pinned. | Make important project resources easy to recognize and open. |
| [DEVONthink import and indexing](https://www.devontechnologies.com/support/faq/copy-files) | Imported files are copies; indexed files are external references that can become unavailable. | Explain Saved copy versus Linked original if live folder references are added. |
| [OmniFocus project review](https://support.omnigroup.com/documentation/omnifocus/universal/4.3.3/en/print/) | Project review has an interval and an explicit reviewed state. | Later, offer an optional short review of next actions and waiting work. |
| [Dropzone floating Drop Bar](https://aptonic.com/blog/introducing-floating-drop-bar-in-dropzone-4) | File references from several locations can be gathered into a bundle and dragged onward. | Preserve batch gathering as an action on selected DaBin items; a separate permanent destination is not required for that job. |

These vendor patterns establish available approaches, not evidence that a particular DaBin redesign will improve task completion.

## Recommended project experience

### Projects home

Show Favorites and Recent projects first, with optional client grouping. Each row needs the project name, its existing color, a short next action and last meaningful activity. Status and an upcoming deadline are secondary. Raw capture counts should not imply project progress.

Keep All projects and Unfiled explicit. Completed or archived projects remain searchable and can be restored. A client label is enough initially; a separate client-management system is unnecessary for this workflow.

### Inside a project

Keep one compact project header, one scoped search field and one shared list. All items and Tasks are the only prominent quick views. Tasks is the existing task filter with a visible label, not a second task database; do not repeat it among type filters.

Use one Views menu for Recent copies, Pinned, Snippets, Collected items, the existing Project note and dated files. These reuse the same project scope and item details. Preserve the current Clipboard view's manually saved text and links as well as automatic clipboard captures; label provenance accurately. Advanced filters live in one Filters popover. Show named removable chips only when filters are active. Avoid a second row repeating every type icon in this project screen.

Keep the existing global Clipboard entry or quick-access command. It explicitly shows All projects and restores the previous project context when dismissed. A project-scoped Recent copies view must say that it is scoped; users should not mistake an empty project result for missing clipboard history. Reuse the application's existing Add and Search controls rather than add competing copies of them.

Show a single Resume row only when there is something useful to resume. It opens the previous item or task and restores its context. Keep the project note collapsed until opened; do not reserve an empty note panel or build a dashboard of counts and activity. All items initially opens the existing Explorer sorted by recent activity, with pinned resources reachable without displacing recent captures.

Add opens a small action menu: Paste, Add files, New note and New task. Direct drop and paste remain available without opening this menu. Clicking a result opens the existing details with copy, source, comments, reminders, task conversion and attachments. Keep a visible Copy action; place less frequent operations in the item's contextual menu.

Tasks uses the same list and inspector. Preserve checklists, attachments, recurring work, reminders, priorities, work-day planning and rescheduling. Task deadlines, planned work days and capture timestamps retain distinct meanings. Next, Waiting and Completed can be filters rather than another navigation row. Inbox and its Day / Week calendar remain available outside Projects.

### Do we need Shelf?

Shelf's useful job is gathering a chosen bundle before attaching, copying or exporting it. Its current implementation stores a persistent set of capture IDs: the content has already been saved by the ordinary capture pipeline. It is neither temporary file storage nor a separate archive. Removing shelf membership keeps the capture and managed files. [Shelf intake](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/ShelfCaptureController.swift:54>), [membership persistence](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/WorkspaceStore.swift:318>)

Remove Shelf as a main tab. For one-off work, let users select several items in the normal list; show an action bar only while items are selected. Offer Copy, Attach to task and Export ZIP, with filing and pinning in More. Selection remains separate from opening an item, and an accessible Select items command complements Command-click and Shift-selection.

Preserve all legacy shelf membership under Views → Collected items. This remains a persistent view, scoped to the current project; switching projects never moves or reassigns its members. Removing an item from this view changes only membership. Provide Clear collection with explicit wording that saved captures and original files remain. Do not merge collected items into Pins: a delivery bundle and a frequently reused reference have different purposes.

Defer new named collections, a Keep collection command and a floating shelf until testing shows users need to maintain several bundles across sessions. The first redesign can preserve the existing Add to collected items / Remove from collected items contextual actions for users who already rely on Shelf. Copying or exporting must not clear the collection automatically.

| Current control | Proposed place | What remains available |
| --- | --- | --- |
| Explorer | Default All items list | Local paths, daily files, search, previews, filing, copying and drag-out. |
| Clipboard | Views → Recent copies and global quick access | Latest content, provenance, copy, plain text and history search. |
| Shelf | Selection action bar; legacy Collected items view | Batch gathering, attachment, ZIP and persisted membership. |
| Notes | Add → New note; Views → Project note | Autosave, task conversion and saved project context. |
| Pins and snippets | Views menu and search | Stable favorites and reusable named content. |

This changes navigation, not ownership or storage. A project is a filing destination; a view filters existing work; selection chooses items for an action. Users should not have to choose all three before saving something.

### Representative workflows

- Capture client feedback: choose the intended capture project once, paste or drop, open the result, choose Turn into task and attach its supporting file.
- Gather a delivery: find items in one project, select them and Export selected items. The export explicitly names its scope and count; unrelated filters cannot silently change a retained selection.
- Reuse a reply: open Recent copies or search, copy the item, then return to the previous project selection and task. Snippets remain available for named reusable content.
- Resume interrupted work: choose the project and use Resume. No Overview-to-Materials hop is required.
- Write a note: use New note or open Project note. Autosave feedback explains what survives closing and restarting.

These are proposed flows, not measured reductions in interaction count.

### Compact and expanded windows

Keep the existing small window and avoid a permanent sidebar. At narrow widths, show one column; item details replace the list with a Back action. Expansion reveals the existing list-and-inspector arrangement using the same controls. Do not introduce additional navigation when the window grows. Selection, project, search, active filters and scroll anchor must survive both directions of resizing.

Use clear labels for navigation, consistent native symbols, tooltips and visible keyboard focus. Project color communicates identity but must be accompanied by its name. Active filters need names and a Clear action. Apple’s guidance recognizes the space cost of sidebars and recommends more compact navigation when room is limited. [Apple sidebar guidance](https://developer.apple.com/design/human-interface-guidelines/sidebars?changes=_11)

## Make capture destination explicit

Add a small Capture to control near Auto Capture. Browsing and capture routing become independent: visiting another project does not change where automatic copies are stored. An explicit Use this project for captures action changes the destination. Unfiled remains available whenever the user has not selected a destination.

Manual drops into a named project continue to use that project. Preserve the existing rule that automatic capture freezes its destination when the event begins, so a slow save does not follow a later selection change.

After saving, the robot’s confirmation and saved card can show the destination and offer Change project with Undo. New content is never held up by mandatory classification.

Later, offer opt-in local routing rules using an explicitly selected folder or a copied URL domain. Show the rule and allow correcting it. A source application alone is too weak a signal when the same browser is used for several clients. Ambiguous matches go to Unfiled. Automatic cloud classification would require a separate privacy and consent design.

## Project management and file safety

Add Rename, Favorite, Archive and Reactivate after stable identity is available. Start with Active, Waiting and Complete as work statuses; archiving separately controls visibility. Archiving must preserve captures, notes, files, links and tasks. It should explain whether active reminders continue, and changing that behavior must be explicit.

Multiple selection should support Command-click, Shift-selection and keyboard equivalents. The action bar offers File to project, Attach to task, Pin, Copy and Export. Show partial failures accurately. Existing task attachments inherit the task’s project; filing an attachment must not silently detach it.

For export, provide Selected items, Visible results and Complete project as explicit scopes. A complete export should include originals and a readable index of links, notes, comments and tasks, with the option to exclude internal material. Show the scope and item count before saving. A project delivery ZIP and a recovery backup serve different purposes.

Live working folders can be valuable later. Keep managed copies as the default and label any linked file clearly. A missing reference needs Locate file or Reconnect folder. Removing the reference must keep the external original. Do not add destructive original-file operations as part of the first project redesign.

## Implementation order

| Priority | Deliverable | Relative effort | Completion condition |
| --- | --- | --- | --- |
| First | Independent capture destination, visible scope/filters and shared search fields | Small to medium | Browsing cannot silently change routing; the same item matches the same text in project and global search. |
| First | Per-project context restoration | Medium | Switching clients and restarting preserves selection, query, mode and scroll anchor. |
| Next | One project screen, secondary Views menu and an optional Resume row | Medium | Finding, reusing and resuming content does not require choosing between four workspace modes. |
| Next | Stable project IDs, favorites, rename and archive | Medium to large | Existing archives, paths, notes, colors and task relationships migrate safely. |
| Next | Multiple selection and complete-project export | Medium to large | A batch can be filed or exported with accurate progress, recovery and scope. |
| Later | New collections, client templates and project review | Medium | Observed repeated workflows justify each added concept; legacy Shelf remains usable meanwhile. |
| Later | Linked working folders and local routing suggestions | Large | Permissions, moved files, unavailable volumes and ambiguous matches have reliable recovery. |

Effort is a relative engineering judgment, not a delivery estimate. Defer Gantt/dependency systems, client portals, whole-computer indexing and cloud AI until observed needs justify their cost.

## Architecture and migration

Extend the current persistence architecture with a ProjectRecord containing a stable UUID, display name, color, optional client label, status, favorite flag, archive date and stored folder location. Keep an optional project ID on existing captures during migration; map legacy names deterministically from both captures and scratchpad markers.

Store project view state by UUID: selected capture, active view, query, filters, grouping and scroll anchor. Keep the automatic capture destination in a separate preference. Preserve the existing shelfCaptureIDs set when consolidating navigation; expose it through Collected items without rewriting ownership or original timestamps. Ordinary multiselection is transient interaction state, separate from this persisted set. If named collections are justified later, they can also refer to capture IDs.

Current folder identity includes a hash of the project name. Preserve existing folder locations during migration. Renaming must reconcile metadata and file paths through a recoverable operation; it must not blindly regenerate paths or duplicate every attachment. Explorer should continue exposing the actual local path. Retain the current journal, byte verification, conflict preservation and external Markdown-edit protection. [Project archive implementation](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/ProjectFileArchive.swift:34>)

Large filing operations currently involve main-actor file work and repeated verification. Before enabling large batches, move that work behind an asynchronous, cancellable operation with progress while preserving integrity checks. This is an architectural risk identified from code, not a measured performance regression. Resume information should also avoid rescanning or decoding the full archive on every UI update.

## Validate the improvements

Compare the current four-mode workspace with the proposed single project screen in compact and expanded layouts. Test a task-first default only for users whose projects are primarily task lists. Keep all existing capture and file features available, and verify that users can find former Shelf, Notes and Clipboard actions through their new entry points.

Use fictional materials for three clients. Ask a small group of freelancers to:

1. Capture feedback, attach a document and create a follow-up task.
2. Gather links, screenshots and files into one project.
3. Switch to another project, inspect a resource and confirm where the next automatic copy will go.
4. Return to the original project after restart and resume the next action.
5. Find a checklist-only phrase from both project and global search.
6. File several items together, recover a failed move and undo a successful one.
7. Rename and archive a project without losing its resources or reminders.
8. Export a complete project while a content filter is active.
9. Select a delivery bundle, distinguish it from Pins, and reopen legacy Collected items after restart without losing captures.

Measure unassisted completion, destination mistakes, interaction count and time to resume. Proposed targets are zero silent routing mistakes and a meaningful reduction in time to resume; these are not measured results. Check compact/expanded layouts, continuous resizing, keyboard-only use, long names, mixed-language text, large histories, missing originals and interrupted operations.

Add targeted tests for migration, independent routing, context restoration, search parity, batch partial failure, parent-task ownership and export scope. Build on existing project picker, workspace, Explorer transfer/query and project archive regression suites. Pilot feedback should determine which later capabilities actually deserve implementation.

### Concept review performed

An interactive concept with fictional project content illustrates compact and expanded layouts. Browser checks passed for project-specific search restoration, the unchanged capture-destination indicator when switching projects, task filtering, access to legacy Collected items, filter removal, multiple selection and action counts, menu Escape/focus restoration, compact detail navigation and expanded inspection. Geometry checks found no horizontal overflow or clipped controls at preview widths from 320 to 780 pixels; light-theme screenshots were inspected. The inspector was adjusted to fit its content, and Resume hides when that item is already open.

These checks validate the concept's local interactions only. Copy, attachment and ZIP feedback are simulated; no application files, capture data, clipboard contents or installed version were changed. This is an expert UX review, not feedback from recruited users. The next step is to test these flows in the native app before removing existing navigation.
