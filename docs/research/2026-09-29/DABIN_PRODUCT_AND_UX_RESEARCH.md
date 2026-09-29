# DaBin: product and usability research

Research date: 29 September 2026. This is a recommendation and concept, not an implemented app update.

**Recommendation**

Make DaBin the private work inbox for people who collect material while switching between projects. The promise to test is: **“Save it now. Find it later. Pick up where you left off.”** The product should make a saved screenshot, link or note useful again with very little organization work.

The next release should improve capture, retrieval and recovery before expanding the feature set. Then add lightweight project collections and a unified follow-up view. Keep the robot as a recognizable, optional companion; ordinary use should be immediate and understandable without learning its gestures.

**What this research establishes**

The review combines current native Swift source, release documentation, saved native QA renders and current public competitor documentation. It is an expert review, not a usability study with customers. The Mac was locked, so a fresh live walkthrough was unavailable. Current source includes 0.3.19 work; older product plans and screenshots are treated as historical where they conflict with the source. No production app code, settings or captures were changed.

The recommended initial audience is a hypothesis: independent Mac-based designers doing client research across several active projects. Researchers and consultants are adjacent audiences to test later. Neither competitor features nor this review establish willingness to pay or market size.

**What DaBin already has**

Mixed-content paste/drop capture; local saved originals; OCR and document-text search; daily/weekly browsing; contextual search; comments; reminders; capture-to-task conversion and task carryover; copy-original actions; day/week text export; optional clipboard and screenshot-folder capture; app exclusions; and cross-channel image duplicate suppression are already implemented. They should be made easier to discover and use, not presented as new features. See the [current README](../../../README.md).

Projects, tags, pinning, a system-wide capture/search hotkey, user-facing Recently Deleted and an integrated backup/restore flow were not found in the audited implementation. Ordinary Edit-menu Undo does not undo capture deletion. Existing text exports are not full restorable archive backups.

**Competitive evidence and its implications**

Listed prices are the public USD offers observed during this research; regional, tax and purchase-channel differences apply. Vendor descriptions establish advertised capabilities, not independently measured quality.

| Alternative | Verified offer | Implication for DaBin |
|---|---|---|
| Apple Spotlight | Searchable clipboard history on newer macOS; settings offer 30 minutes, 8 hours or 7 days. Included with the OS. [Apple guide](https://support.apple.com/en-za/guide/mac-help/mchl40d5b86b/mac), [settings](https://support.apple.com/en-lk/guide/mac-help/mchl54d95e8a/mac) | Clipboard recovery alone is a weak reason to buy another app. Demonstrate durable mixed-content retrieval and follow-through. |
| Paste | Clipboard history, pinboards, search and device sync; $29.99/year shown, with other purchase options. [Pricing/features](https://pasteapp.io/pricing) | Fast reuse and simple pinning are established expectations. |
| Unclutter | A quickly accessible shelf for files, notes and clipboard history; US App Store lists $19.99. [Product](https://unclutterapp.com/), [listing](https://apps.apple.com/us/app/unclutter/id577085396?mt=12) | A small utility benefits from a clearly understood job and immediate access. |
| Dropzone 5 | Drag/drop actions, temporary file holding, global shortcut, sharing service and Shortcuts integration; $35 lifetime and a 14-day trial. [Product](https://aptonic.com/) | A floating drop target is useful but not unique. Avoid competing by adding dozens of unrelated file actions. |
| Anybox | Native quick save/find, offline search, smart lists, web archives, images/files/notes and automation. $14.99/year; $39.99 lifetime displayed alongside a $59.99 reference price. [Product and pricing](https://anybox.app/) | Broad collecting and organization are available inexpensively. DaBin needs a clearer daily benefit. |
| ToMe | Share-sheet capture, Mac drag/drop, spaces, reminders, keyword and on-device semantic search, Spotlight and iCloud sync. Seven-day trial; paid subscription or one-time purchase. [Capture](https://savetome.app/features/capture), [search](https://savetome.app/features/search), [product](https://savetome.app/) | This is a close substitute. Saving many content types, private search and collections are not sufficient uniqueness claims. |
| mymind | Automatic tagging, OCR, collections and rediscovery; $79/year Student and $129/year Mastermind offers. [Plans](https://access.mymind.com/pricing) | Low-effort organization is an established product promise. Its success for DaBin still needs testing. |
| Screenpipe | Screen/audio history and searchable context; a broader continuous-capture product. [Product](https://screenpipe.com/) | DaBin can test a lighter intentional-capture workflow without taking on continuous screen/audio recording. |

Privacy needs specific language. Paste supports device storage and optional private iCloud; ToMe advertises on-device semantic search. mymind's AI policy describes Amazon Bedrock processing, a different architecture from offline processing. “Private” does not always mean “never uploaded.” DaBin can credibly describe its actual local archive and local OCR, with separate explanations for optional website previews. It should not promise an encrypted vault: the current privacy policy says the archive is not separately encrypted by DaBin. [Paste storage](https://pasteapp.io/help/where-paste-stores-your-data), [mymind AI policy](https://mymind.com/ai-usage-policy), [DaBin policy](../../../native/Resources/PrivacyPolicy.md).

One useful, limited customer signal is Paste's public request for selective sync. Comments mention sensitive content and irrelevant clipboard material crossing devices. It had 27 votes when checked, with comments spanning several years. This supports asking users about noise and control; it is not representative evidence of demand for DaBin. [Feedback thread](https://feedback.pasteapp.io/35).

**Specific friction in DaBin**

| Observed implementation | Likely user cost — a hypothesis to test | Recommended change |
|---|---|---|
| Three header rows with date navigation, five action icons and six type filters. [BoardView.swift](../../../native/Sources/DaBin/BoardView.swift), [BoardComponents.swift](../../../native/Sources/DaBin/BoardComponents.swift) | Many controls look equally important; unfamiliar symbols require exploration. | Labeled destinations, persistent search, one Add action, one Filter control and a More menu. |
| The plus button calls `openNewTask()`. [BoardView.swift:258](../../../native/Sources/DaBin/BoardView.swift#L258) | “Add” suggests any content, but produces a task form. | Add offers Paste, New note and Import files; Create task remains clearly labeled. |
| Daily's date opens Weekly; Weekly's date opens a calendar. [BoardView.swift](../../../native/Sources/DaBin/BoardView.swift) | The same visual object has different behavior. | A date always opens a date picker; Day/Week becomes an explicit timeline option. |
| Empty-state copy says to reach a corner even though direct board paste/drop works. [DailyScreen.swift](../../../native/Sources/DaBin/DailyScreen.swift), [DailyCaptureView.swift](../../../native/Sources/DaBin/DailyCaptureView.swift) | Onboarding teaches a hidden gesture before the obvious action. | “Drop anything here or press ⌘V.” Teach the robot after the first successful save. |
| Daily Search already spans all dates; Weekly requires choosing a day/week scope. Search retains the active type filter and automatically includes neighboring nonmatching captures. [AppState.swift](../../../native/Sources/DaBin/AppState.swift), [Domain.swift](../../../native/Sources/DaBin/Domain.swift) | Users can misread the scope or perceive irrelevant results. | Search all captures consistently; show every active filter, rank matches first, and reveal surrounding captures on request. |
| Clipboard capture starts only after screenshot-folder authorization succeeds. [AutoCaptureService.swift:130](../../../native/Sources/DaBin/AutoCaptureService.swift#L130) | Someone wanting only clipboard history must configure an unrelated folder. | Independent Clipboard and Screenshots switches, both off initially, with a shared Pause. |
| Cards repeatedly expose Comment, Reminder, collapse and trash. [CaptureCards.swift](../../../native/Sources/DaBin/CaptureCards.swift) | Large action areas reduce scanable content. | Title/preview/source first; Copy and More remain available; reveal secondary actions in details. Show an existing note or due date when relevant. |
| Removal explicitly cannot be undone. [BoardView.swift:62](../../../native/Sources/DaBin/BoardView.swift#L62) | A routine cleanup action carries avoidable risk. | Immediate Undo and Recently Deleted; permanent deletion remains explicit. |
| Default board opacity is 0.75. [ThemeSettings.swift:38](../../../native/Sources/DaBin/ThemeSettings.swift#L38) | Busy content behind the window can harm readability. | Opaque or nearly opaque by default; transparency remains optional. |
| Capture/search shortcuts are app-menu shortcuts; backup requires copying the archive while DaBin is closed. [ApplicationMenu.swift](../../../native/Sources/DaBin/ApplicationMenu.swift), [native guide](../../../native/README.md) | Access and ownership require knowledge users may never acquire. | Configurable system-wide shortcut, opt-in launch at login and integrated backup/restore. |

These changes follow recognition and progressive-disclosure principles: show the commonly needed actions clearly, and move less frequent controls one level deeper. Fewer visible symbols alone is not the goal; a hidden essential action can make a screen look cleaner while making it harder to use. [NN/g: icon usability](https://www.nngroup.com/articles/icon-usability/), [NN/g: progressive disclosure](https://www.nngroup.com/articles/progressive-disclosure/).

**Proposed interface**

Use three clearly labeled destinations:

- **Today:** the recent capture timeline, with date browsing and Week available within the timeline. Intentional saves are easy to see; passive captures stay in expandable groups.
- **Library:** every saved item across dates. Pins and optional project collections are views over the same items, not duplicate copies or required filing steps.
- **Follow-ups:** existing tasks and reminders in one actionable queue, each linked to its original capture. Show due and overdue work clearly; do not repeatedly crowd the Today feed with every unfinished task.

Keep **Search all captures** and **Add** available in every view. Searching should visibly switch to all-capture results unless the user deliberately applies a filter. Type, source, date and project are filter choices, not permanent toolbars. Let people open an item, copy it, preview it and return without losing their position.

At compact widths, retain text labels and show one content column. At larger widths, allow a detail panel. Preserve a compact capture surface; do not force a large dashboard on every save. Keep the robot's expressive capture interaction, but provide an immediate keyboard/menu-bar route and a quiet mode. Long transformations must not delay access to search or block input.

The companion interactive concept illustrates these decisions with fictional data. It is not a measured usability improvement or production build.

**Feature priorities**

| Order | Work | Status relative to current app | Why / acceptance condition | Relative effort |
|---|---|---|---|---|
| 1 | Clear Add, direct paste/drop onboarding, consistent dates, compact cards, readable default | Improve existing behavior | A new user saves and finds one item without explanation. | Small–medium |
| 2 | Global quick-access shortcut and unified search; visible filters; matches first, optional context | New access mechanism + improve existing search | Find and copy a known item without remembering its capture date. Existing OCR stays central. | Medium |
| 3 | Independent capture controls and noise handling | Improve existing Auto Capture | Clipboard-only mode works without a screenshot-folder grant. Pause is obvious. Duplicate grouping never silently removes intentional saves. | Medium |
| 4 | Undo / Recently Deleted and full local backup/restore | New user-facing recovery | Restore the record, original file, notes and reminder correctly after removal; verify a full archive restore. | Medium–large |
| 5 | Pins, then simple project collections | New organization | Keep recurring references close; collect a project's links, images and notes across days without obligatory tagging. | Medium |
| 6 | One Follow-ups view, one-click snooze, optional review of selected recent saves | Reorganize existing tasks/reminders; add snooze/review where missing | Original content stays attached. Users can defer or finish work without maintaining a second complex planner. | Medium |
| 7 | “Resume this project” view | New packaging of collections/context | Show a project's recent captures, pinned references and next follow-up together. Test whether it actually shortens resumption time. | Medium after collections |
| 8 | Native share action / browser save with source URL; local project suggestions; local semantic retrieval | Later experiments | Add only when observed missed captures, missing context or search failures justify them. | Medium–large |

Effort labels are relative planning judgments, not delivery estimates. Data recovery and search-index migrations require more care than visual changes. Build in small increments rather than attempting the whole table as one redesign.

For project suggestions, start with user-defined rules such as a chosen source folder or URL domain. Offer “Add to Website launch?” after saving, with an easy dismissal. Do not silently move captures or require a classification decision before saving. Semantic search can later help when users remember the idea but not the wording; ToMe already advertises it, so it is a potential usability improvement rather than a unique positioning claim.

Do not prioritize additional robot reactions, a generic AI chat panel, complex kanban/Gantt planning, team administration or continuous screen/audio recording. Phone capture and optional sync may become important, but validate how often work is lost between devices before taking on that scope. A later sync option would need explicit opt-in and a clear change to the local-storage promise.

**How to make it easier to sell**

Lead the product page with an outcome and demonstrate it:

> **DaBin — your private work inbox.**
> Save links, screenshots, files and notes as you work. Find them again and keep the next step attached.

For a short demo, show a designer saving a screenshot, a reference link and a note during research; switching tasks; finding the reference through a phrase in the screenshot; then reopening the related material and following up. The robot can be the memorable opening moment. The successful retrieval should be the payoff.

Use three proof points supported by the current product: local capture storage, on-device OCR/search, and no required account. Explain optional website requests separately. Test whether “Bin” sounds like permanent storage or Trash to first-time users; keep the name for now and use a clarifying descriptor rather than initiating a rebrand on instinct.

Test **$29 versus $39 one-time** for the Mac app with a full-feature 14-day trial and a clearly stated update policy. This is a pricing hypothesis informed by nearby utility prices, not proven willingness to pay. Keep export and access to existing material available after the trial. Consider recurring pricing only if later features create ongoing value that users want. Do not promise unlimited future development without a sustainable plan.

Begin acquisition with a small designer beta, a focused product page and concrete before/after demonstrations. Interview participants and ask permission before using their testimonials. The current research did not recruit, message, publish or upload anything.

Distribution needs verification, not assumptions from stale docs. Earlier README material describes an ad-hoc direct build. The existing “DaBin personal daily board” thread reports that Apple accepted the 0.3.19 build 46 upload on 27 September and was processing it; later visible turns do not establish tester availability. This research did not inspect live App Store Connect. Before inviting users, verify the actual clean install/TestFlight invitation path, processing status, support contact and privacy copy. TestFlight upload success does not establish a notarized direct-download package or a public App Store release.

**Validation plan and decision gates**

Recruit 8–12 independent Mac-based designers for discovery; use 5–6 initially for task-based usability sessions, then a two-week beta. Ask about three recent real examples of losing a saved reference or struggling to resume a task. Observe their current tools before presenting features. This sample is directional research, not a market-size survey.

Compare the current app and proposed flow using the same representative archive of approximately 100 mixed items. Counterbalance which interface people see first. Include a filename they know, a screenshot discoverable only through OCR, a date they cannot remember, and a source-app clue. Use synthetic material unless a participant deliberately chooses their own content.

Proposed success targets, not measured results:

- First useful capture and retrieval within 60 seconds, without coaching.
- At least 80% unassisted task completion and median known-item retrieval within 15 seconds in the test archive.
- New users correctly predict Add, date selection, search scope and removal behavior.
- Clipboard-only setup succeeds without folder permission; Pause and resume are understood.
- Accidental removal is recoverable and a backup round-trip preserves content and relationships.
- During the beta, users return to open, copy or act on prior captures on several separate days; raw automatic-capture counts do not count as evidence of value.

Track unsuccessful searches, manual-versus-automatic reuse, missed reminders and reasons for abandoning the app. Use observed sessions and participant-controlled local diagnostics; the current product has no analytics, so silent telemetry would contradict its existing promise. Discuss price after users have experienced a useful retrieval, and treat stated willingness to pay as weaker evidence than an actual purchase decision.

Ship the capture/search/recovery improvements first. Add collections if repeated cross-day project retrieval is observed. Prioritize semantic search if exact-word failures persist. Prioritize a phone companion only if cross-device collection is a repeated obstacle. Expand based on those outcomes rather than matching competitor feature counts.
