# Research on global DaBin search by date

Research date: 3 October 2026. Status: proposal based on local source review and official product documentation. The native app and personal archive have not been changed.

Make Search a single place to find anything saved in DaBin, regardless of the project or calendar screen currently open. Arrange matching results in columns by date, with the newest matching date on the left. Add optional filters and useful result actions after the first search, so users can begin with their words rather than choosing where to look.

The working interpretation of “anything” is all saved DaBin content: captures, tasks, attachments, links, screenshots, supported indexed documents, snippet names and project notes. Whole Mac search, connected services and public web search would require separate scope and access decisions. They are not prerequisites for this proposal.

## What the current app already does

| Finding from source | Consequence for this proposal |
| --- | --- |
| Search and Command K inherit project, calendar, source app and type context. | A user can miss an item elsewhere in DaBin even though it matches the query. Start a fresh search with all those scopes cleared. |
| Search everything already retains the query while clearing scope. | Much of the global behavior is available; it should become the normal entry point. |
| Captures are grouped by immutable saved date, with the newest dates first. Items within a date currently run oldest first. | Reuse date grouping and present columns; choose newest saved item first within a date for a consistent chronological board. |
| Project scratchpads match separately and appear above capture dates. Their date is the last edit. | Include them in the corresponding date column, explicitly labeled Edited. |
| Explorer has an independent Find in this project field and a separate matching policy. | Route its search entry through global Search rather than retaining a competing search scope. |
| Week already has date-column components, while Explorer has recycled result rows. | Reuse interaction and presentation patterns, with bounded rendering for a potentially much larger history. |

Source references: [search entry state](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/AppState.swift:742>), [global reset](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/AppState.swift:802>), [matching and date grouping](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/Domain.swift:467>), [search presentation](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/SearchScreen.swift:106>), [project search field](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/ExplorerScreen.swift:95>), [independent Explorer matching](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/ExplorerQuery.swift:30>), [Week columns](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/WeeklyScreen.swift:25>).

Global matching currently considers capture metadata, original text, indexed text, comments, checklist text, effective project ownership and snippet aliases. It folds case and diacritics and requires every query word to match somewhere in the searchable fields. Deleted captures are excluded; completed tasks remain eligible. This is keyword matching, not semantic understanding. [Matching fields](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/Domain.swift:480>), [project ownership and snippets](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Sources/DaBin/AppState.swift:561>).

## Relevant research and product patterns

| Official source | Documented behavior | Proposed application to DaBin |
| --- | --- | --- |
| [Microsoft Research on Stuff I Have Seen](https://www.microsoft.com/en-us/research/blog/find-lost-data/) | Describes unified retrieval of personal information from different sources, with date and type sorting and refinement. | Search across saved formats together, using time as a retrieval cue. This historical research does not prove that columns outperform lists. |
| [Bear search guide](https://bear.app/faq/how-to-search-notes-in-bear/) | Search updates as users type; advanced operators combine text, content attributes and created or modified dates. | Keep ordinary search simple and make additional precision optional. Exact phrases and exclusions could follow later. |
| [Raycast File Search](https://manual.raycast.com/file-search) | Offers inline results, a richer details view, Quick Look and contextual actions. File content search has its own coverage requirements. | Preview and act on a result without adding a permanent toolbar to every card. Explain indexing limits clearly. |
| [Apple Finder organization](https://support.apple.com/guide/mac-help/organize-your-files-in-the-finder-mchle9f0a1b2/mac) | Supports grouping by attributes including dates and inspecting selected content in a Preview pane. | Date grouping and selection previews fit familiar Mac interaction. Finder column view represents folder hierarchy, not the proposed date layout. |

These sources support individual interaction patterns. The combined date-column design is a recommendation from this review, with usability benefits still to be tested.

## Recommended search experience

Every fresh Search entry opens the same global search: toolbar icon, Command K, global shortcut and the search entry inside Projects. No surrounding project, day, week, source app or type silently constrains the first query. Keep the originating screen and its state available for Back.

Use one search field labeled Search everything saved in DaBin. An empty field shows recent saved items in the same date layout, with older matching dates available through navigation. This is a proposed change; the current search algorithm returns no groups for an empty query. Typing replaces recent browsing with matching results immediately. Include supported indexed content in that initial pass rather than requiring a second content-search command.

The initial toolbar needs only the search field and Filters. Below it, show the total match count and number of matching dates. When narrowed, show each active refinement as a removable named chip and offer Clear filters. Filters can contain Project, Type, Date range and Source app. Do not require people to learn query syntax for routine narrowing.

Deliberate refinements remain active while typing and returning from a result within the same search session. Closing that session and starting a new search restores the global scope. A saved search, if added later, is an explicitly named exception whose visible chips explain its scope. Browsing search results must never change the capture destination.

### Date columns

Use one column per exact matching day. Display a readable date including the year when needed, the day match count and the date meaning. Hide days with no matches. Keep the newest matching date at the left and sort captures newest first within it. Avoid a relevance mode in the first version: predictable chronology is the requested organizing principle.

Captures stay on their original saved day, including their recorded time zone. Moving a capture to another project, editing a comment or completing a task must not move its search column. A deadline or planned workday is not its saved date. Project notes use their edited day and need an Edited label so those semantics remain visible. An honest fallback group is preferable to fabricating a timestamp for malformed or imported undated records.

Show two or three readable columns when the window has room, rather than squeezing seven days into a small board. Provide Older dates and Newer dates controls, with a visible range such as Dates 1 to 3 of 18. This is presentation paging: every query still searches the entire archive, and the total count includes dates outside the current page.

In a compact window, retain one readable date column and the same matching-date controls. Selection opens details with Back; an expanded window can show a preview alongside the board. Resizing preserves the query, refinements, selected result and date anchor. The concept deliberately illustrates compact and expanded layouts without changing search scope.

### Useful result behavior

Each result should show a recognizable title or preview, its project or Unfiled label, content type, capture time and a short matching excerpt. Explain whether a match came from the title, comment, checklist or extracted text when that distinction helps recognition. Existing indexed snippets can be reused; richer snippets across all fields would require work.

Selecting a capture opens its existing details; selecting a project note opens its Notes editor. Both restore the same query and date position on Back. Keep Open and Copy easy to reach, with Pin, File to project, Attach to task and other existing actions in a contextual menu. Action availability must follow the actual content type. Preserve parent-task ownership when filing attachments.

Move Show nearby captures into the selected result's contextual actions. Nearby items should be labeled as context and excluded from match counts. The date board initially contains only matching items.

## Additional functionality in order

| Stage | Deliverable | Why it belongs here |
| --- | --- | --- |
| First | Global entry points, common matching fields, one optional Filters control and clear result counts. | Removes hidden scope and inconsistent outcomes before adding visual complexity. |
| Next | Date columns, compact date paging, integrated project notes, previews and existing result actions. | Provides chronological recognition and useful action in the same place. |
| Later | Local recent searches, saved searches, exact phrases, exclusions and optional shorthand that becomes visible filter chips. | Adds speed and precision once the basic retrieval behavior is reliable. |

Recent and saved searches should remain local and removable. Natural language such as last week can eventually map to deterministic date chips; it does not require hosted AI. Typo tolerance and semantic matching are separate capabilities and should not be implied by this redesign.

## Feasibility and limits

The core change can use existing capture records, date keys and local indexes without rewriting stored captures or managed originals. Unifying note and capture results needs a presentation model; saved searches would need new preference storage. That is separate from a capture-data migration.

Do not copy Week's eager layout across years of search results. Render only the visible date page and recycle long columns, load previews on demand and cancel superseded query work. Measure search independently: the recent Explorer stress run does not establish performance for every global query. Do not discard matches merely to meet a rendering limit.

“Everything” must remain an honest description of saved scope and supported extraction. DaBin currently indexes images, PDF text and scanned pages, DOCX main-body text, supported plain text and RTF locally. Limits include 100 PDF pages, 300,000 extracted characters and 12 MiB text, RTF or DOCX input. DOCX headers, footnotes, comments and embedded-image OCR are not covered; some file formats and encrypted or malformed packages are unsupported. Media can still match saved metadata without audio or video transcription. Show indexing progress and available format status rather than treating incomplete extraction as proof there is no match. [Current format support and limits](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/docs/RELEASE_NOTES_0.4.20.md>).

## Validation before implementation is accepted

Use fictional archives and compare current search with the proposed flow. Ask users to find an OCR-only phrase from another project, a task checklist item, a completed task, an older capture and a recently edited project note. Check compact and expanded layouts, long titles, mixed-language queries, keyboard-only use and VoiceOver.

Engineering checks should verify that every fresh entry is global, completed tasks remain findable, deleted items stay excluded, parent attachments use live project ownership, notes appear on the correct edited day and counts include all matching dates. Test month and year boundaries, time zones and daylight saving, filter removal, no-match states, index completion, rapid query changes, date paging and restoration after opening details. Search must preserve capture routing and unfinished work.

Existing scope tests intentionally assert inherited context and will need explicit updates to match the new requirement. They should retain tests for deliberate refinements inside a session and Back restoration. [Search scope tests](</Users/roeylibfeld/Documents/KARI Creatives/DaBin/native/Tests/SearchScopeStateTests.swift:346>).

Measure unassisted success, time to find an older item, mistaken assumptions about scope and action count. Proposed goals are fewer scope mistakes and faster retrieval, not measured results. The local interactive concept uses fictional records; it is not a deployed app feature or a recruited usability study.

### Concept verification performed

Local browser checks passed for 14 fictional matching results across six dates, newest-date ordering, date paging in both layouts, project and type filters, inclusive date filters, chip removal, preview navigation, Edited labels and query changes. No JavaScript errors or horizontal overflow were found at 320, 360, 736 and 1060 pixels in light and dark appearances. The 736 pixel light layout and 320 pixel dark layout were visually inspected. These checks cover the concept's local interactions; they do not verify native performance, VoiceOver, actual document extraction or user usability. The concept makes no network requests and changes no native app or personal capture data.
