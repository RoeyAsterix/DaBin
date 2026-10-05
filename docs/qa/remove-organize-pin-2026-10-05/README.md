# Remove To organize and Pin actions — 2026-10-05

Removed the redundant **To organize** shortcut from the Captions Day/Week toolbar and its selected label in the unsorted view. The existing **Captions** tab returns to that view while retaining date, filter and draft. Day/Week navigation, previous/next dates and the calendar remain directly accessible.

Removed **Pin/Unpin** from shared capture/Tasks/Captions menus, Projects Clipboard/Shelf cards and Explorer/search card menus. Stored pin metadata and existing badge/filter/sort/retention compatibility remain intact. Existing project, copy, reminder, comment, task conversion, snippet and delete actions are retained.

Six affected Release native suites passed on exact production fingerprint `dae2228aa8ea9dcd4e3dd556ccc8aeb7273e230b1471340feb3eebb1fa2cc8a1`: HeaderInteractionTests, CardDeletionInteractionTests, RedesignInteractionTests, ExplorerCaptureCardPresentationTests, WorkInboxTests and SnippetNamingInteractionTests. They cover 1,479 checks, including native menu dispatch, retained failed drafts, title/preview preservation, calendar return context and compact layouts. Card deletion's complete cleanup marker is present. This is a selected run of six of 126 registered suites, not a full current-source campaign. Reports and raw logs are in `runs/`; three header fixture renders are in `renders/`.

32 existing offline packaging guard tests and deterministic project generation passed. The actual unsigned arm64 Store Release app was compiled and packaging-checked, with embedded 0.4.33 (88), bundle ID, source fingerprint and executable hash verified against its receipt. It is unsigned, not installed or uploaded. Signing, installed sandbox behavior and Apple processing remain separate.

Prior strict zoom performance failure and native table warnings remain open. No performance benchmark, full hardware/OS matrix, human VoiceOver session or signed sandbox runtime was repeated for this small UI removal. The earlier drag-export fix is retained in this source; its prior 13-suite verification and unconfirmed receiving-app proxy error remain documented in `../drag-upload-2026-10-05/`.
