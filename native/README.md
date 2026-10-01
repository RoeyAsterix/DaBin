# DaBin for macOS

A native, private work inbox: save something, find it again, and resume the work attached to it. **Inbox**, **Today** and **Projects** organize the main window. Inbox opens once on first launch; after dismissal, DaBin keeps a compact menu bar status visible. Reach a screen corner to reveal the metallic purple robot, drop onto its body, or hover and press **Control-V** or **⌘V**. Double-click to resume your current work. New preferences use an opaque board; existing installations retain their saved transparency choice.

**0.4.19, build 74** is installed and running locally. Compact and expanded windows now share a continuous 21-point corner curve and a thin vector rim. Resize targets follow the visible edges, reach the physical outer corners and preserve the padded header controls; an expanded safe-area window can be resized inward. Two-second messages, preview-led cards, persistent recovery controls and the click-to-dismiss task alarm are retained. See the [release notes](../docs/RELEASE_NOTES_0.4.19.md).

All 18 selected Release suites pass across two frozen-input reports: 17 valid passing batch suites and the final focused closing suite with 400 checks. Native chrome QA covers 16 actual resize drags, preserved header click areas and eight compact/expanded light/dark render fixtures at 1×/2×, including immediate backing-scale updates and exact shared mask/rim paths. Earlier CPU recording failures and the corrected timing sampler remain documented; these previews are not live FPS measurements. Installed signatures and executable hashes match the build receipt; Settings shows 0.4.19 (74), with tooltips enabled and Auto Capture paused. A normal quit preceded replacement, with 0.4.18 backed up; the guarded installer did not modify the capture archive. Compact Explorer is restored after Expand/Restore. [Local installation verification and limitations](../docs/qa/local-install-0.4.19-2026-10-02/verification.json). This local build is not published; the public release remains 0.3.18.

## Run

Open **DaBin.app in your personal Applications folder** (`~/Applications/DaBin.app`) on this Apple Silicon Mac. A local build is written to [build/DaBin.app](build/DaBin.app). The first launch opens Inbox once. Later launches keep the board hidden until you use a screen corner, a global shortcut, reopen the running app, or choose **Open DaBin** from the menu bar. There is no permanent Dock icon or separate drop zone. The menu bar item shows Auto Capture state and provides Pause/Resume, Settings, and Quit.

- Drag files from Finder or selected text from another app to the selected reveal target, then onto the robot and release. This also works while Daily or Week is open. The whole robot accepts drops, including its badge. It accepts content through its intake, digests while saving, reacts to the result, then retreats after the pointer leaves. Files are copied into the local archive; their originals stay in place. Multiple files from one paste or drop appear together in one caption card, with every item independently openable. The card shares its comment, reminder, minimize and remove controls.
- Hover over the robot to paste with **Control-V** or **⌘V**, without clicking. Leaving the robot releases this temporary keyboard focus; holding the shortcut does not create repeated captures. Clicking also focuses it; double-click to resume the board. Return/Space on the focused robot also resumes it.
- With **Inbox** or **Activity → Daily** open, drop text, links, files, images or videos directly anywhere in the window, or focus Daily and press **Control-V** or **⌘V** (Edit → Paste also works). An accepted drag briefly outlines the board in your theme color. Successful captures appear on their receipt date with All selected; a slow import respects any navigation you make while it saves. Search, comments and task editors keep their usual text-paste behavior.
- Under **Settings → Automatic capture**, opt into **Clipboard** and **Screenshots** separately. Both start off. Clipboard capture works without granting folder access. Screenshots require an explicitly selected folder; choose a dedicated screenshot folder because every new image there is treated as a screenshot. Enabling monitoring never imports clipboard content or folder images that were already present. The first-enable explanation describes local storage; folder access is requested only for screenshots. The board and Settings report channel status, including when clipboard capture is working but screenshots need permission. **Pause/Resume** controls the selected channels together. DaBin and common password managers are excluded by default; the exclusion list is editable.
- Automatic actions keep their timestamp, type, content and best-effort source application in the local archive. A screenshot arriving through both the selected folder and clipboard is normally kept once. At the fourth successful action in one local clock hour, Daily replaces that hour's individual cards with one live summary. Click it to expand every action; the minus button labeled **Collapse actions** returns to the same feed position. After a successful save, one click-through robot peeks, climbs out, eats a generic capture token and retreats into the built-in camera island; external displays and displays without a physical notch use the top-right. Ten eating reactions run in shuffled rotation without repeating the previous three. Rapid captures update the token’s exact `×N` action count; arrivals after the eating window form one follow-up aggregate. Manual robot interaction and the open board take priority. Reduce Motion uses a short peek, checkmark and fade.
- From another app, **⌃⌥Space** opens archive search and **⌃⌥V** saves the current clipboard. Under **Settings → Quick access**, disable global shortcuts or choose **Control + Option + Shift** instead. A registration conflict is reported; menu bar access remains available. These shortcuts register explicit key chords and do not monitor general typing.
- In an active DaBin window: **⌘O** resumes DaBin, **⌘⇧D** opens Today planning, **⌘K** focuses global Search, **⌘⇧V** focuses the robot, **Escape** leaves search focus before hiding the board, and **⌘Q** quits. **Quiet mode** in Quick access suppresses automatic capture celebrations and opens the board promptly without the full robot transformation; capture remains enabled according to your chosen settings.
- Drag the **DaBin logo or visible header grip** to move the board anywhere on your displays. Resize from the visible rounded edges or physical outer corners, including inward from the expanded safe-area window. A shallow six-point padding band provides the grip without covering header controls. Expand/restore gives your workspace more room without losing its selection, search or project. It remembers your position after hiding or restarting. If a display is disconnected, the board stays within an available screen.
- The main window has three labeled views: **Inbox** for quick capture and organization, **Today** for planned work, and **Workspace** for saved resources. **Activity** in Inbox shows captures received on the selected date, newest first. **Filters** offers All, Text, Links, Files, Media and Tasks. Text includes plain text converted into tasks; Tasks includes open and completed tasks. Empty days offer Paste clipboard and New note. The small robot stays still with Reduce Motion.
- **Add** offers **Paste clipboard**, **New note**, **Import files…** and **New task**. The note editor saves a new text capture to today. Search, capture-note and task editors retain normal text-paste behavior; using Add → Paste clipboard explicitly saves a new capture.
- **Workspace → Library** shows saved captures across all dates. Use its optional project picker and pin filter. Clipboard, Shelf and Notes share that project context. Open a capture to pin it, assign an existing project, create a project name or remove its project assignment. Filing is optional and does not change the capture's date.
- Compact cards keep their content, saved note and reminder visible, with **Copy** and **More** actions. More contains editing, pinning, project assignment, task conversion, minimize and removal. Automatic hourly actions retain their surrounding group without a second card border.
- Use **Copy** to return original captured content to the macOS clipboard. Text, links and tasks copy their original value. Files, PDFs, images and videos copy DaBin's saved local original, and a grouped drop's copy control copies every file together. Successful copying briefly shows confirmation; missing local originals produce an error.
- **Activity → Day / Week** switches between one date and the seven-day range ending on the selected date. The date button opens a calendar in either mode; it does not unexpectedly switch modes. Weekly retains its existing active-date columns, including carried and reminder-day tasks. Click a day heading to open that date, or browse earlier periods with the arrows. Each visible day scrolls independently; narrow displays can scroll the columns horizontally. Reduce Motion disables the unfolding animation.
- The **Search** toolbar icon opens a focused search field, including from an unfinished task. In Weekly view it first offers **Search Day**, **Search Week**, or **Search All Captures**; **⌘K** always searches the full archive. The field appears when searching, keeping the normal header to two compact rows. Entering global search clears a stale type filter. Results show matches by default; **Show nearby captures** adds immediate same-day context. **Filters** can narrow matches by content type without silently limiting dates or projects. Back restores the originating view, project, filter and unfinished work. Search also finds named snippets, checklist text and project scratchpads; project and source filters are explicit.
- **More → Export** copies or exports the selected day or week as chronological UTF-8 text, regardless of the active type filter. Files use `DaBin-YYYY-MM-DD.txt` or `DaBin-Week-YYYY-MM-DD-to-YYYY-MM-DD.txt`. Select the date/range in Activity before exporting; empty day and week exports are disabled independently. The gear opens Settings directly; Recently Deleted and archive backup/restore live in More.
- Open a capture to see its **Source location**, with a copy button. New file imports retain their original path. Copied text retains a source only when the sending app supplies explicit origin metadata; ordinary text often has none. Old records cannot recover paths that were never saved. Promised-file staging folders are never presented as the original source.
- Previews fit their available space without stretching or cropping. PDF previews fit a complete page, with arrows to browse multi-page files. Document previews show a fitted page thumbnail; **Open original** opens the full document.
- In **Settings → Appearance**, toggle Dark mode and adjust the board from 35% to 100% opacity. New preferences default to 100%; existing saved opacity is preserved. Under **Theme color**, choose Purple, Blue, Teal, Green, Rose or Amber, or pick a custom color. Changes apply immediately and are remembered on this Mac. **Reset** returns the accent to Purple. macOS Reduce Transparency temporarily uses a solid surface and explains the override in Settings.
- In the **Settings → Your quiet corner**, choose **Screen corners** or **Below camera island**. Camera-island mode uses the built-in display's safe-area geometry and only activates where macOS reports a real camera cutout. An external display or a Mac without that geometry uses the top-right corner when camera-island mode is selected. The choice is stored locally and can be changed at any time.
- At the bottom of **Settings → Application**, choose **Quit DaBin** to close every window and stop Auto Capture, corner monitoring, previews, update work, and all other DaBin background activity. Existing captures, settings, and saved reminders remain available when you open the app again. The same native safety checks used by ⌘Q protect an active import, removal, or unsaved edit.
- Double-clicking the robot expands its body into the existing app view in 1.15 seconds. The head, hands and feet stay outside the live content. X, Escape and Command W perform a coordinated 0.78-second fold, compact-pose and shrinking tuck. Reduced motion uses a 0.14-second fade with a static frame.
- The transient robot blinks, glances and occasionally shrugs while it is visible; this ambient work stops when it hides. macOS **Reduce Motion** keeps the expressions but removes moving, repeated and keyframed reactions.
- In the **Settings → Get updates**, choose **Check for updates** to read DaBin’s latest public GitHub Release. DaBin never checks silently. When a newer verified build is available, **Download & install** checks the release URL, exact size and SHA-256 checksum before opening the built-in installer with a private, one-use update document. The installer validates and consumes that document, then asks before changing the app.
- Changing a filter keeps the header in place and gently resizes the bottom edge. If the board reaches the bottom of the display, scroll through the results inside it. Reduce Motion makes resizing immediate.
- Use **Settings → Open local archive** to browse saved content in Finder. Each record also has **Show saved folder**.
- Use **Add → New task** for a task with an optional reminder. New tasks are saved to Inbox with their creation date; choose a separate workday in task planning. Completing pauses task alerts; reopening from Detail or More restores a future reminder.
- Open any capture and choose **Turn into task** beneath its title, or right-click its card in Daily, Weekly, Search or Reminders. Text, links, screenshots and files keep their original content, preview, source, comments, reminders and capture date. The same card gains the **Task / Completed** toggle and joins the **✓ Tasks** filter while remaining in its original content filter. A converted item appears individually outside its former file batch or automatic-hour summary so its task status stays visible. Converting while editing keeps your unsaved comment and reminder draft.
- **Today** has Today, Upcoming and Completed scopes. Choose tasks from Inbox, set a workday, priority and optional effort, then reorder the plan. Deadlines and notification reminders stay separate. Tomorrow reschedules the workday without changing the original receipt. Recurring tasks create one linked next occurrence on completion. Unfinished or overdue work remains visible under Needs another look.
- Choose **More → Add/Edit note** or **Add/Edit reminder** on a capture, then save changes in Detail. Saved notes and reminders remain visible on compact cards. Unfinished composer and detail edits are saved privately in Drafts.json and restored after restart. Save applies detail edits to the capture. A failed draft save is reported and quitting asks before losing in-memory edits.
- **More → Minimize capture / Expand capture** changes its compact presentation and remembers the choice. Full content remains available in Search and Detail.
- **More → Move to Recently Deleted** asks before removing a capture from the active archive. The banner offers **Undo** for the latest removal. **More → Recently Deleted** lets you restore saved captures or permanently delete them with a separate confirmation. Permanent deletion cannot be undone; files at their original source are kept. Recently Deleted is not an automatic retention timer.
- Search also reads text recognized locally in screenshots, images, PDF pages and supported text documents (`txt`, Markdown, CSV, JSON, logs, XML/YAML, RTF and common source files). PDFs use their existing text layer and locally recognize image-only pages. An indexed-content hit shows the matching line on the result card. Capture Detail shows a preview and can copy all searchable text; **Settings → Rebuild text search** retries the archive. Recognition uses Apple frameworks on this Mac, never a website or external AI service. Very large PDFs are limited to the first 100 pages and indexed text is capped at 300,000 characters per capture.
- Enable website preview fetching under **Settings**. It is off initially; URL cards and Open original already work. Enabling previews contacts websites for new and earlier manually saved links that need previews. Automatically captured links never fetch website previews. Read **Settings → Privacy policy & data controls** for what stays local, optional website requests, backups and removal.
- Saving the first reminder requests macOS notification permission. A saved reminder remains visible if permission is denied; the app reports its notification state. Delivery is subject to macOS permission, Focus, and system conditions.

## What is included

Native SwiftUI content in AppKit panels; Core Data metadata; a dated local archive with readable records and managed originals; drag/paste, note and file-promise intake; PDF/image/video/system previews; global text search with optional nearby context; optional project workspaces, pins and named snippets; a collection shelf and autosaving notes; workday planning, deadlines, recurring tasks and UserNotifications reminders; Recently Deleted and Undo; verified local archive backup/restore; separate automatic capture channels; global shortcuts and Quiet mode; light/dark colors; a native layer-based robot character with Reduce Motion behavior; an Xcode project, source, tests, and the unchanged handoff.

The supplied robot SVG is preserved as an original handoff resource. The transient robot is drawn with native macOS layers so its face, lid, arms, intake and body can react independently. Normal app storage starts empty; review fixtures are isolated from it.

## Update the current installation

The direct GitHub build can pull a release from inside DaBin: open Settings and use the first **Get updates** card, choose **Check for updates**, then **Download & install**. The card always shows the installed version, status, and latest GitHub release link without scrolling. The app accepts only the fixed `RoeyAsterix/DaBin` HTTPS release path and validates the published size and SHA-256 checksum. It writes a small, private, one-use update document beside the downloaded ZIP and opens that document with its signed built-in helper. The helper validates the document and package location, independently rechecks the ZIP, asks for confirmation, verifies the ARM64 Release app, backs up `~/Applications/DaBin.app` under `~/Applications/.DaBinBackups/`, installs and verifies the replacement, then reopens DaBin. It does not read, move or delete the sandboxed capture archive.

The repository also keeps permanent package downloads: [download the latest in-app update package](https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-Update.zip), or [download the latest unsigned Apple Silicon test package](https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-AppleSilicon.zip). Their URLs stay the same when a new public release becomes latest. The in-app updater continues to use the versioned package named in the public release manifest so its strict version, URL, byte-count, and checksum validation remains unchanged.

Release 0.3.18 restores update discovery on the first Settings screen and adds permanent repository download URLs. Verified release staging makes each stable alias byte-identical to its versioned package, while the published-release workflow repairs missing aliases automatically.

The current packages are locally ad-hoc signed and not notarized. They pass code-seal and package-integrity checks, but Gatekeeper rejects a normal first launch after a browser, messaging app, or AirDrop applies quarantine. They must not be presented as public direct installers. Existing installations should update from DaBin's **Get updates** card. A public first-install package requires Developer ID Application signing, hardened runtime, Apple notarization, a stapled ticket, and Gatekeeper validation. The direct update channel is compiled only by the standalone build script; the Xcode Mac App Store configuration excludes the downloader and helper because Store builds must update through the App Store.

## Build and test

Full **Xcode 27.0** is installed and selected, with macOS SDK **27.0**. DaBin targets macOS **14.0+**, ARM64; the local candidate was built on macOS **26.6.2**. Intel and older macOS runtime behavior have not been verified.

From this directory:

```sh
./scripts/build.sh
python3 scripts/install_app.py
./scripts/test.sh
./scripts/render_qa.sh
```

The test suite uses temporary stores, private named pasteboards, fake notification clients and its own test windows. It never reads the general clipboard or personal captures. Run the full suite in an unlocked, logged-in macOS GUI session. `./scripts/test.sh --storage-only` runs the preference, privacy, storage, removal, service, input, task and lifecycle suites without window-focus checks. Window tests report all independent failures and still exit unsuccessfully if any check fails. Agent execution sandboxes may need scoped access to AppKit/pasteboard services; normal Terminal runs do not need special app permissions. The intentionally corrupt-store test prints expected Core Data diagnostics before passing.

The default build creates an optimized ARM64 Release application at `build/DaBin.app`, embeds the direct-channel update helper, ad-hoc signs both with App Sandbox enabled for the main app, and verifies a metadata-clean copy. All runtime dependencies are Apple system frameworks. Debug symbols stay outside the app. Use `./scripts/build.sh --configuration Debug` for an unoptimized development build. Quit DaBin before running the install script; it preserves an existing app in `~/Applications/.DaBinBackups/` and leaves your archive untouched. Set `DABIN_SIGNING_IDENTITY` to an available Developer ID identity to override the local default. This is a local Release candidate. Apple distribution signing, notarization, validation and Mac App Store approval remain pending.

With full Xcode, open `DaBin.xcodeproj`, select the shared `DaBin` scheme, and configure signing for your machine. The equivalent commands are:

```sh
xcodebuild -project DaBin.xcodeproj -scheme DaBin -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData build
xcodebuild -project DaBin.xcodeproj -scheme DaBin -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DerivedData test
```

The Xcode project includes native XCTest smoke tests; the Debug/XCTest commands above have not been verified in this preparation. The 2 October unsigned Xcode Release Store build and all 73 registered standalone Release suites pass; see [QA_RESULTS.md](QA_RESULTS.md) for results and blocked signed-runtime checks. Receipts record per-suite results and source fingerprints. Build, tests and the Xcode project use the same source inventory. See [ARCHITECTURE.md](ARCHITECTURE.md) for ownership and module boundaries.

Desktop/Documents synchronization on this Mac reattaches Finder metadata to app bundles, which fails strict signature verification. Use the installed personal-Applications copy; its signature remains verified. The ZIP contains the clean signed file contents, without those extended attributes. `install_app.py` copies a build into personal Applications and verifies it there.

## Mac App Store preparation

See [APP_STORE_READINESS.md](APP_STORE_READINESS.md) for the current **2 October, 0.4.19 (74)** audit and release gates. The source includes a bundled privacy policy, privacy manifest, Productivity category, export-compliance declaration, Store-only compile boundary, safe archive location check, and recursive quarantine gate. Apple Developer Team `8QG4967CSU` and Bundle ID `com.dabin.mac` are stored in `Config/AppStoreSigning.json` and applied to the generated Release target. [Current evidence](../docs/qa/app-store-2026-10-02/README.md) and [1440 × 900 screenshot drafts](../docs/app-store/screenshots/0.4.19-74/README.md) are tracked. The prior **0.3.19 (46)** TestFlight upload is historical; it does not establish distribution or acceptance of **0.4.19 (74)**. The current source passes 73 Release suites, 39 media checks, 77 offline Python tests and 51 unsigned Store packaging checks. Signed export, owner/Connect declarations and signed Sandbox/macOS 14 runtime verification remain pending. This preparation did not replace the installed personal app. `python3 scripts/app_store_preflight.py --static-only` checks source packaging.

A standalone download containing only the application and the PDF guide can be created after building with:

```sh
python3 scripts/package_standalone.py --guide ../output/pdf/DaBin-Quick-Guide.pdf
```

The packager checks system-only dependencies, Release configuration, source freshness, ARM64 architecture, ZIP hashes, executable permissions and the extracted signature. It excludes personal captures and preserves existing output ZIPs.

Additional real-media QA is available with `./scripts/test_media_integration.sh`. It uses synthetic local PDF, document and video fixtures. Add `--link-smoke` only to explicitly test a public Apple webpage using isolated preview preferences.

## Storage and privacy

Bundle ID: `com.dabin.mac`. Sandboxed storage is resolved through FileManager, normally:

`~/Library/Containers/com.dabin.mac/Data/Library/Application Support/DaBin/`

The browseable archive is organized automatically using the original capture day:

```text
Archive/
└── 2026/
    └── 09 September/
        └── 22 Tuesday September 2026/
            └── 21-47-00 - <unique capture ID>/
                ├── Capture.md       # readable content and annotations
                ├── Capture.json     # complete capture metadata
                ├── Content.txt      # exact text, when supplied
                ├── Link.webloc      # link captures
                └── Original/        # saved file, image, PDF, video, etc.
```

Numbered months and days keep Finder ordering chronological; English weekday/month names stay stable across locale changes. Separate capture folders prevent equal filenames from replacing each other. Comments, reminders, source locations, task status and preview metadata stay with their capture. Dates never move when a reminder or task changes. Day folders are created when content is saved for that date.

The transactional `metadata.store` remains the app’s index. `Previews/` is a disposable local cache; `Staging/`, `Imports/` and `MigrationStaging/` support recovery. `Deletions/` holds temporary removal intents so an interrupted cleanup cannot restore a deleted import. Legacy `Originals/<capture UUID>/` files are copied into dated folders only after byte verification and remain as safety copies. Conflicts are preserved and reported. If a readable-record write fails after a database commit, the saved capture remains intact and the folder is retried on reopening.

Edit notes and task status in DaBin. If generated files were changed externally, their old bytes are preserved under `Local edits/` before regeneration; outside edits are not imported into the app. Do not move or delete managed originals or delete a database to fix a launch error.

Use **More → Back up archive…** to create a local `.dabinbackup` directory package outside the live archive. It includes capture metadata, saved originals, readable records, saved local edits, available previews, project/pin state and Recently Deleted. It excludes preferences, credentials, the live SQLite files and transient import jobs. Keep the package's contents together. **More → Restore archive backup…** verifies its manifest, ownership and file checksums, then adds missing captures. Existing identical captures are retained; conflicting metadata or files stop restoration rather than overwrite them. Backup and restore wait for active import/removal work to finish. This is a local backup feature, not cloud sync.

For local maintenance with DaBin closed, the installed executable accepts `--organize-archive`. It updates dated folders without opening windows, contacting websites, reading the clipboard, or scheduling notifications.

There is no account, analytics, cloud sync, semantic search, external AI processing, launch-at-login registration, automatic update check or automatic upload. Clipboard polling runs only while the selected clipboard channel is active and unpaused; the explicit save-clipboard command reads the current clipboard once. An explicit update check contacts GitHub; optional link previews contact saved websites only when enabled. No Accessibility, Screen Recording, camera or microphone permission is needed by the app. Global shortcuts register only their chosen key chords. Reveal detection reads pointer position and ordinary macOS screen geometry. External file access comes from explicit imports, paste/drop transfers, a user-selected screenshot folder, or export/backup destinations and backup sources you choose. Regular capture import rejects directories, aliases and symbolic links; import their regular files instead. Backup restoration has its own verified directory-package flow. Source files are preserved.

## Verification and limits

### Workspace, clipboard and the collection shelf

The Workspace keeps a selected client or project while switching between Library,
Clipboard, Shelf and Notes. Projects are optional; **All projects** includes all
saved work. Use the project menu or adjacent folder-plus button to create a space.
The same project selection applies to notes and new captures. Global search also
matches named snippet aliases without changing the capture's original content.

Clipboard shows recent copied content first, regardless of pin count. The Recent /
Snippets button switches to named reusable content. Date, source application,
capture origin, content type and project filters can be combined. Recorded source
information is shown only when it is available; a manual note is not presented as
an automatically observed copy. **Copy as plain text** writes only text to the Mac
clipboard; use the normal Paste command in the destination application. DaBin does
not simulate typing into another application or require Accessibility permission.

Shelf items are **saved captures held for later organization**, not disposable
clipboard memory. Pasting, dropping or choosing files on the shelf uses the same
verified local import as ordinary captures. Adding an existing item to the shelf
stores its capture ID. **Remove from shelf; keep capture** removes only this
membership; the item remains in Library. **Move to Recently Deleted** is the
separate recoverable removal action. Imported files are managed local copies;
moving or deleting the external source does not remove the saved copy. **Copy saved
file path** and **Reveal saved file** refer to that managed copy. No shelf action
deletes the external original. An unavailable managed copy produces an explicit
failure while preserving its capture metadata.

The shelf's ZIP action exports the entire selected project's shelf even when a
content filter hides some items. Files are copied and verified; notes and links
are UTF-8 text. Equal names are disambiguated. Choose a new ZIP filename; an
existing destination is never silently replaced. The ZIP contains saved contents,
without absolute source paths. It is a collection export, not an archive backup.

Notes are an autosaving scratchpad per project, with a separate unfiled scratchpad.
They survive navigation and app restart. A failed write retains the pending text
in memory, displays **Not saved**, offers Retry save and participates in the app's
unsaved-work protection. **Save note** creates a normal capture, and **Make task**
opens the task while retaining its original text. The scratchpad remains available
after either action. Shelf memberships, snippet names, scratchpads, project and
filter context are stored atomically in `Workspace.json`, next to the capture
database, and included in the verified local archive backup. Restoring conflicting
authored scratchpad text or snippet names stops without replacing the current work.

See [QA_RESULTS.md](QA_RESULTS.md) for checks actually run and remaining native integration checks, and [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md) for deliberate changes from the attached handoff.
