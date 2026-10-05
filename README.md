# DaBin

DaBin is a little robot for the useful bits of your day. It keeps your ideas, links, images and files together on your Mac. Drop something onto the robot, keep it with a project, and find it again when you need it. It runs natively on Apple Silicon Macs.

Three labeled views organize the work, in order: **Projects** for project resources, clipboard history, named snippets, a collection shelf and autosaving notes; **Today** for all captures received today and workday planning; and **Inbox** for quick captures and the **Day / Week** calendar. Within Inbox, **To organize** keeps unfiled items from all dates, **Day** shows the selected date in a responsive card grid (one column in compact view), and **Week** opens the seven-day capture history. Week opens in full view on the current display, with all seven dates visible and cards sized to fit. Custom selections keep their chosen one to seven dates. Organization is optional.

Tasks keep their original content and attachments. A planned workday is separate from a deadline or reminder. Choose a priority, estimate effort, reorder today’s plan, add checklist steps, set a repeat rule, complete work or reschedule it. Project scratchpads and unfinished composer/detail drafts recover locally after restart.

The **Search** toolbar icon, **⌘K**, global shortcut and Projects search open one global search across saved DaBin content. Begin typing, or browse recent saved items with an empty field. Matching dates appear newest first in one to three readable columns, with **Older dates** and **Newer dates** navigation. **Filters** optionally narrows by project, type, source app or dates; removable chips make every refinement visible. Opening a result and returning keeps the query, filters and scroll position. A fresh search session clears those refinements without changing where new captures are saved. Wide windows show a preview alongside results. **Add** offers Paste clipboard, New note, Import files and New task; the gear opens Settings and **More** holds exports and recovery tools.

Removed captures go to **Recently Deleted**, with Undo for the latest removal and a separate confirmation for permanent deletion. A local `.dabinbackup` directory package includes capture metadata, saved originals, readable records, saved local edits and deleted captures. Restore verifies the package and adds missing captures; it rejects conflicts instead of overwriting existing data. Workspace notes, shelf references and snippet names are included. Device preferences and unfinished drafts are kept separately on this Mac.

Launching DaBin opens its main window every time; reopening a running instance resumes the current work. Afterwards, use the robot, menu bar or global shortcuts: **⌃⌥K** searches and **⌃⌥V** saves the current clipboard by default. Settings retains your saved shortcut choice, offers an alternate chord and lets you disable global shortcuts. Enabled macOS system shortcuts are checked before registration so Search cannot also switch the input language. **Quiet mode** opens the board promptly and suppresses automatic capture celebrations. The board supports dark mode and theme colors; new preferences default to an opaque background, while existing transparency choices are retained. The robot still follows macOS Reduce Motion.

DaBin recognizes text in saved screenshots, images, PDFs, Word `.docx` main-body text and supported plain-text/RTF documents entirely on the Mac. Search can find that content even when the filename or caption does not contain the query, and shows the matching line. Capture details expose searchable text and Settings can rebuild the local index. Captures use their original saved date; scratchpads use their last edited date. This is local text search, not semantic search or a search of every file on your Mac. No document, query or indexed text is sent to an external AI/OCR service. See [format support and limits](docs/RELEASE_NOTES_0.4.20.md).

**0.4.26, build 81 is installed and running locally.** Project names appear once in the dropdown with their item count; the repeated title and tagline are removed, giving previews more room. Five focused Release suites pass (921 checks), including narrow layouts, long names and live count updates. The previous app is backed up; Auto Capture remains paused. [Header verification](docs/qa/project-header-0.4.26-2026-10-03/README.md). The preview-first project workspace, multi-selection, ordering, task conversion/undo, native copying and ZIP export from [0.4.25](docs/qa/project-workspace-0.4.25-2026-10-03/README.md), and the persistent recording sign from 0.4.24 are retained.

The previous **0.4.23 (78)** performance update changed Explorer now recycles offscreen cards, preserves the cards you are reading when captures arrive, and supports keyboard navigation through recycled rows. Saving a capture no longer reloads the complete archive; hidden export menus and idle tooltips do less work. That cycle passed all **77/77 Release suites**. The final 1,000-capture stress run reopened every receipt and completed all 200 previews: peak observed memory fell from **792 to 224 MiB**, and maximum main-queue delay from **1.67 to 0.35 seconds**. These are synthetic workload measurements, not universal freeze prevention. A non-fatal AppKit row-height warning remains documented. [Performance verification and limits](docs/qa/performance-0.4.23-2026-10-02/verification.json), [QA results](native/QA_RESULTS.md). The [0.4.21 robot motion](docs/RELEASE_NOTES_0.4.21.md) is retained.

The project/date-scoped search and local Word text indexing from **0.4.20 (75)** are retained and were covered by the 0.4.23 full regression run. [Search format limits](docs/RELEASE_NOTES_0.4.20.md). This local update does not establish App Store approval or a downloadable release. Auto Capture remains paused and tooltips remain enabled; live Settings, Explorer scrolling and expand/restore respond, and the original Inbox was restored. No personal capture was edited for verification. The installer replaces only the app bundle and backs up the previous version; the personal archive was not independently byte-inventoried.

Unsaved-form errors, recovery controls, Undo and the click-to-dismiss task alarm remain available. The timeout governs brief DaBin UI messages, not macOS system notifications.

The **2 October App Store preparation** report covers **0.4.19 (74)** sources, not this newer candidate. Its 73 Release suites passed; Store signing, macOS 14 runtime QA and owner/Connect declarations remain separate gates. [Preparation status](native/APP_STORE_READINESS.md).

Previously approved source, guide and QA documentation are on `main`; the newer search, motion, performance, recording-sign and project-workspace changes are local pending publication. [Previous publication receipt](docs/qa/app-store-2026-10-02/publication.json). No 0.4.26 public binary release or App Store submission has been made.

The **Quiet Orbit** robot uses sharp metallic vector artwork, seven positions around a detected camera island, quiet idle behavior and small success/count feedback. Hover or drop still works directly on the robot. [Native UX/UI verification](docs/qa/quiet-orbit-2026-10-01/README.md).

## A little desktop buddy

Captures have larger fitted previews and a compact action rail. Turning a capture into a task transforms its card in place. Open its details to edit its title, attach more files or text, add a checklist and set reminders. A separate focus timer supports duration, pause, resume and reset; expiry leaves the task incomplete and shows the alarm robot until clicked. The alarm takes priority over Auto Capture feedback, without interrupting navigation or drafts. Work scheduling has an optional local time and stays separate from deadlines and notification reminders. A successful completion makes the visible robot happy. Countdown time starts when you save; it does not restart when reopened.

Explorer uses icon filters, preview-led visual cards, compact text rows and an expanded preview pane. Source badges use locally installed app icons when the saved source is available; website locations have a domain/globe fallback. DaBin shows its own verified storage destination. The source trail shows existing paste receipts without a manual-add button. Legacy manual events remain labeled “Recorded by you” and can still be removed to correct an old entry. Copying an item or switching applications never invents a paste event. App logos are loaded from local installed applications.

Auto Capture is beside the logo. The robot's full-view shell has a thin, continuous rounded rim; drag a visible edge or an outer corner to resize it, including inward from an expanded safe-area window. The grips stay within chrome and shallow padding so header buttons remain clickable. Expand/Restore fills the current display's safe area and returns to the prior window. Quiet Orbit manual reveal takes about half a second. Native window appearance follows the light/dark preference, and hover tooltips can be turned off without removing accessibility labels.

## Optional Auto Capture

Automatic **Clipboard** and **Screenshots** capture are separate opt-in choices, both **off by default**. Clipboard capture works without a screenshot folder. Screenshot capture requires a folder you explicitly choose; missing screenshot access does not stop an enabled clipboard channel. Enabling a channel establishes a new baseline: existing clipboard content and existing folder images are not imported. The board and Settings show the current state, and **Pause/Resume** controls the selected channels together. With a named project selected, the robot holds a sign with the project name in 10-point text for as long as a capture channel remains enabled. Pause keeps the sign and changes its status; disabling both channels removes it.

Screenshot-folder access begins only after you choose a folder in the macOS folder picker. DaBin retains that authorization as a security-scoped bookmark so it can monitor the chosen location while Auto Capture is enabled. New image files in that folder are treated as screenshot captures, so choose a dedicated screenshot folder. macOS does not provide a public notification for every system screenshot: DaBin can see images written to the chosen folder, while screenshots sent to the clipboard can arrive through clipboard monitoring. A screenshot saved somewhere else is outside the folder monitor.

DaBin records a best-effort source application when macOS makes one reasonably identifiable. Source attribution can be unavailable or imprecise, so it is descriptive rather than proof of origin. DaBin itself and common password managers are excluded by default. If the same image arrives through the screenshot folder and clipboard within a short interval, a normalized fingerprint suppresses the second channel's copy; repeating the image later or through the same channel remains a new action. Four or more successful automatic actions in one capture hour become an expandable hourly group on Daily. A brief nonactivating robot emerges from the primary display's camera island, or the external primary display's top-right, and climbs down and eats a generic paper token using ten shuffled eating reactions, with no repeats from the previous three. Rapid captures share the token's exact `×N` count; later arrivals roll into one bounded follow-up group. Opening the board takes priority, and capture feedback waits until the board closes.

Automatic captures use the same local archive as manual captures. An automatically captured link never requests a website preview, even if previews are enabled for manually saved links. When Quiet mode is off, the confirmation begins only after an item has saved. Its native panel requests exclusion from window capture and never contains the captured image or clipboard text. macOS does not provide a universal pre-screenshot notification: third-party or system screen recorders can still include visible overlays depending on their capture API.

Double-clicking the robot transforms its body into the existing DaBin view in about 1.15 seconds. The native robot frame reserves space outside cards and controls; Quiet Orbit keeps decorative movement small. The eyes follow the pointer gently while the view is visible. Closing uses a coordinated 0.78-second fold into a compact robot, followed by a shrinking tuck toward its home. Reduce Motion retains a 0.14-second fade and a static frame. These are native Core Animation layers; the app keeps its usual compact window, navigation, drag/drop and keyboard controls.

![DaBin robot and Daily board](design/robot-preview.png)

## Current source and local app

The local candidate is **0.4.31 (86)**, including navigation history, adaptive workspace zoom and restrained font scaling. [Latest local verification](docs/qa/zoom-typography-2026-10-04/README.md), [full QA results and remaining limits](docs/qa/full-qa-navigation-2026-10-04/README.md), and the [updated one-page guide](docs/DaBin-Quick-Guide.pdf) accompany the source. Git publication and downloadable binary releases are separate.

## Latest release files

**Download status:** this source update does not publish a 0.4.31 (86) binary release. The last recorded public download is 0.3.18. The links below must not be described as the latest local candidate or a notarized testing installer. Source and documentation publication is separate from downloadable releases and App Store submission. The [0.4.6 review record](docs/qa/release-review-2026-10-01/README.md) remains historical evidence rather than verification of this new build.

- [In-app update package for an existing DaBin installation](https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-Update.zip)
- [Unsigned Apple Silicon test package](https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-AppleSilicon.zip)
- [Latest release details](https://github.com/RoeyAsterix/DaBin/releases/latest)

These permanent links follow the newest public GitHub release. The current files are ad-hoc signed and are not notarized. A browser, messaging app, or AirDrop marks them as downloaded, so Gatekeeper blocks a normal first installation. Existing DaBin installations can update safely through **Settings → Get updates**. A public first-install package must be signed with a Developer ID and notarized before it is described as a direct installer.

## Start here

- [Current Mac App Store preparation and unresolved submission gates](native/APP_STORE_READINESS.md)
- [Current local search update and 75-suite verification](docs/RELEASE_NOTES_0.4.20.md)
- [Full 73-suite Release regression evidence](docs/qa/app-store-2026-10-02/tests/README.md)
- [Native app guide](native/README.md)
- [0.4.19 Smooth window corners and resize grips](docs/RELEASE_NOTES_0.4.19.md)
- [0.4.17 Preview-led Explorer cards](docs/RELEASE_NOTES_0.4.17.md)
- [0.4.18 Two-second UI messages](docs/RELEASE_NOTES_0.4.18.md)
- [0.4.16 Task timer alarm robot](docs/RELEASE_NOTES_0.4.16.md)
- [0.4.15 Preview-led collection cards](docs/RELEASE_NOTES_0.4.15.md)
- [0.4.14 Robot closing candidate](docs/RELEASE_NOTES_0.4.14.md)
- [0.4.13 Capture-trail cleanup candidate](docs/RELEASE_NOTES_0.4.13.md)
- [0.4.8 Performance candidate](docs/RELEASE_NOTES_0.4.8.md)
- [0.4.9 Click-to-open candidate](docs/RELEASE_NOTES_0.4.9.md)
- [0.4.10 Capture timestamps candidate](docs/RELEASE_NOTES_0.4.10.md)
- [0.4.12 Restored tooltips candidate](docs/RELEASE_NOTES_0.4.12.md)
- [0.4.11 Consistent robot candidate](docs/RELEASE_NOTES_0.4.11.md)
- [0.4.7 Projects and Auto Capture candidate](docs/RELEASE_NOTES_0.4.7.md)
- [0.4.6 Reviewed testing candidate](docs/RELEASE_NOTES_0.4.6.md)
- [0.4.5 Window resizing and display movement](docs/RELEASE_NOTES_0.4.5.md)
- [0.4.4 Open Design implementation notes](docs/RELEASE_NOTES_0.4.4.md)
- [Open Design QA and screenshots](docs/qa/open-design-2026-09-30/README.md)
- [0.4.3 Explorer candidate notes](docs/RELEASE_NOTES_0.4.3.md)
- [Explorer Open Design handoff](design/explorer-handoff-2026-09-30/README.md)
- [0.4.2 connected-workflow candidate notes](docs/RELEASE_NOTES_0.4.2.md)
- [Product review, evidence and roadmap](docs/review-2026-09-30/README.md)
- [0.4.0 local candidate notes](docs/RELEASE_NOTES_0.4.0.md)
- [0.3.18 release notes](docs/RELEASE_NOTES_0.3.18.md)
- [0.3.17 release notes](docs/RELEASE_NOTES_0.3.17.md)
- [0.3.16 release notes](docs/RELEASE_NOTES_0.3.16.md)
- [0.3.15 release notes](docs/RELEASE_NOTES_0.3.15.md)
- [Robot-led quick guide (PDF)](docs/DaBin-Quick-Guide.pdf)
- [Friendly product and guide copy](docs/DaBin-Friendly-Copy.txt)
- [Architecture](native/ARCHITECTURE.md)
- [QA results](native/QA_RESULTS.md)
- [Privacy policy](native/Resources/PrivacyPolicy.md)
- [Mac App Store readiness](native/APP_STORE_READINESS.md)
- [App Store Connect draft](docs/app-store/APP_STORE_CONNECT_DRAFT.md)
- [Current App Store listing and screenshot preparation](docs/app-store/APP_STORE_CONNECT_DRAFT.md)
- [Documentation index](docs/README.md)

## Build

DaBin targets Apple Silicon and macOS 14 or later. The local build uses Apple Command Line Tools:

```sh
cd native
./scripts/build.sh
./scripts/test.sh
```

The optimized app is written to `native/build/DaBin.app`. Full GUI QA needs an unlocked macOS session. The checked-in Xcode project provides the App Store build path when full Xcode and an Apple Developer team are available.

## Updates

The direct build has a user-initiated GitHub Releases channel under **Settings → Get updates**. It accepts only this repository’s fixed HTTPS release path, verifies the published byte count and SHA-256 checksum, then gives the bundled installer a private, one-use update document. The installer validates and consumes that document, re-verifies the package and application, asks before replacement, and backs up the previous installation. The capture archive remains untouched. There are no silent update checks.

Release 0.3.18 places **Get updates** at the top of Settings, with the installed version, live status, update check, conditional installation, and latest GitHub release link visible without scrolling. The repository’s permanent installer and direct-download URLs follow the newest public release while the in-app updater retains its exact versioned package and checksum validation.

The current personal release is ad-hoc signed for the owner’s Mac. General distribution still requires a stable Developer ID signature and Apple notarization. The Mac App Store configuration compiles without the direct downloader and helper; Store builds update through Apple.

## Repository scope

This repository contains the native source, resources, tests, build and release tools, design history, handoff documents, QA documentation, and the PDF guide. Generated builds, old ZIP packages, temporary renders, user data, and compiler caches are ignored. Release ZIPs belong in GitHub Releases.

No open source license has been granted in this repository.
