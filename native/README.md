# DaBin for macOS

A native, local daily capture board. DaBin stays invisible while idle. By default, reach any screen corner to reveal the metallic purple robot. On a Mac with a built-in camera island, you can instead let it peek out below the island. Drop onto its body or hover over it and press **Control-V** or **⌘V**. The robot watches the pointer, welcomes incoming content, chews while saving and reacts to the result. Double-click it to open Daily. The floating board starts at 75% opacity and can be adjusted in Settings.

## Run

Open **DaBin.app in your personal Applications folder** (`~/Applications/DaBin.app`) on this Apple Silicon Mac. A copy also ships at [build/DaBin.app](build/DaBin.app). The first launch is intentionally hidden: move the pointer into a screen corner. Reopening the app while hidden opens Daily. There is no permanent Dock icon, menu-bar icon, drop zone, or paste composer.

- Drag files from Finder or selected text from another app to the selected reveal target, then onto the robot and release. This also works while Daily or Week is open. The whole robot accepts drops, including its badge. It opens its lid for accepted content, digests while saving, reacts to the result, then retreats after the pointer leaves. Files are copied into the local archive; their originals stay in place. Multiple files from one paste or drop appear together in one caption card, with every item independently openable. The card shares its comment, reminder, minimize and remove controls.
- Hover over the robot to paste with **Control-V** or **⌘V**, without clicking. Leaving the robot releases this temporary keyboard focus; holding the shortcut does not create repeated captures. Clicking also focuses it; double-click for Daily. Return/Space on the focused robot also opens Daily.
- With **Daily** open, drop text, links, files, images or videos directly anywhere in the window, or focus Daily and press **Control-V** or **⌘V** (Edit → Paste also works). An accepted drag briefly outlines the board in your theme color. Successful captures appear on their receipt date with All selected; a slow import respects any navigation you make while it saves. Search, comments and task editors keep their usual text-paste behavior.
- In the **gear menu → Settings → Capture**, turn on **Auto Capture** if you want DaBin to save future clipboard changes and new screenshots written to a folder you choose. Use a dedicated screenshot folder because every new image there is treated as a screenshot. Auto Capture starts off and never imports clipboard content or folder images that were already present when monitoring began. The first-enable sheet explains local storage and asks for folder access. Settings and the app menu show whether monitoring is enabled, paused or needs permission; **Pause Auto Capture** stops both monitors immediately. DaBin and common password managers are excluded by default, and the exclusion list is editable.
- Automatic actions keep their timestamp, type, content and best-effort source application in the local archive. A screenshot arriving through both the selected folder and clipboard is normally kept once. At the fourth successful action in one local clock hour, Daily replaces that hour's individual cards with one live summary. Click it to expand every action; the minus button labeled **Collapse actions** returns to the same feed position. After a successful save, one click-through robot anticipates, emerges, celebrates and retreats against the built-in camera island; an external primary display uses its top-right. Twelve celebrations run in shuffled rotation without repeating the previous three. Rapid captures update one `×N` badge without restarting the current move. Reduce Motion uses a short peek, checkmark and fade.
- In an active DaBin window: **⌘O** opens Today, **⌘K** opens Search, **⌘⇧V** focuses the robot, **Escape** hides, **⌘Q** quits.
- Drag the **DaBin logo or the blank space beside it** to move the board anywhere on your displays (other views use their title). It remembers your position after hiding or restarting, and keeps the header in place as the content changes. If a display is disconnected, the board stays within an available screen.
- The opened Daily board stays available until dismissed. Its compact header keeps date navigation beside the DaBin logo, uses purple **1-calendar** and **7-calendar** icons for Daily and Weekly, aligns Add, Search, Export, Notifications and Settings above the filters as two identical 280 × 34-point rows, and keeps the neutral X at the far right. Header icons use 15-point symbols, 40 × 34-point targets and 30-point circular interaction surfaces. The active Daily or Weekly icon receives the same purple selected circle used by the filters. Hover for 220 ms to see a small label; keyboard focus reveals the same cue, and clicking dismisses it. Each icon keeps its complete accessibility name. Captures appear on their original local day, newest first. Browse the date and use the purple All, Text, Links, Files, Media, or **✓ Tasks** icons. Text uses the familiar aligned-text icon and shows copied, pasted or dragged plain text, including text converted to a task; links, newly authored tasks and text-document files have their own filters. Tasks includes both open and completed tasks on the selected day. Capture types sit below the time; tasks have their status toggle there. Empty days show a small bored robot; it rests when the board is hidden and stays still with Reduce Motion.
- In Daily, press the purple export icon between Search and Notifications to export the complete selected calendar date, regardless of the active type filter. **Copy Day** puts the chronological plain-text record on the clipboard. **Export Text File** writes those exact UTF-8 bytes to `DaBin-YYYY-MM-DD.txt` at a location you choose. Empty days explain that there is nothing to export and disable both actions.
- Individual caption cards use a thin continuous rounded frame in Daily, Search and Reminders. Carried tasks keep their stronger theme-colour outline, and automatic hourly actions use their existing outer action frame without a second nested border.
- Press the small purple **copy icon in the upper-right of a capture card** to put its original captured content on the macOS clipboard. Text, links and tasks copy their original value. Files, PDFs, images and videos copy DaBin’s saved local original, and one grouped drop copies every file in the card together. The icon briefly becomes a checkmark after a successful copy; missing local originals produce an error instead of reporting success.
- Use the compact **Daily / Weekly** control to switch between one day and a seven-day range. Daily → Weekly anchors the range to the selected day; Weekly → Daily returns to that same day. Switching preserves the selected date, type filter, Daily scroll position and unsaved drafts. Weekly renders only dates that contain a capture or task, including carried and reminder-day tasks; empty dates do not create columns. Filters change the cards inside those active dates without moving the columns. A completely empty range stays compact and shows one empty-week message. Pressing the centered **date** also opens the seven-day range ending on the selected day. The board grows to fit its active dates and folds back to its compact position. Click a day heading or Back to return to Daily, or a capture to open its details. Browse earlier weeks with the arrows or range calendar. Each visible day scrolls independently; on a narrow display, scroll horizontally when the active columns need more room. Filters, comments, reminders and task toggles work in Week too. Reduce Motion disables the unfolding animation.
- In Weekly, Search opens a small scope menu. Its day picker includes all seven dates in the range, including hidden empty dates. Choose **Search Day** for that exact date or **Search Week** for the full fixed range. The active content filter limits matches, and results retain their same-day neighboring context. Back returns to the Weekly range.
- Weekly's export menu uses the same day picker and offers **Copy Day**, **Download Day**, **Copy Week** and **Download Week**. Copy and download produce identical chronological UTF-8 content for the chosen scope. Downloads ignore the active filter and use `DaBin-YYYY-MM-DD.txt` or `DaBin-Week-YYYY-MM-DD-to-YYYY-MM-DD.txt`. Empty day and week scopes are disabled independently.
- Open a capture to see its **Source location**, with a copy button. New file imports retain their original path. Copied text retains a source only when the sending app supplies explicit origin metadata; ordinary text often has none. Old records cannot recover paths that were never saved. Promised-file staging folders are never presented as the original source.
- Previews fit their available space without stretching or cropping. PDF previews fit a complete page, with arrows to browse multi-page files. Document previews show a fitted page thumbnail; **Open original** opens the full document.
- In the **gear menu → Settings → Appearance**, toggle Dark mode and adjust the board transparency from 35% to 100% opacity. Under **Theme color**, choose Purple, Blue, Teal, Green, Rose or Amber, or pick a custom color. Changes apply immediately and are remembered on this Mac. **Reset** returns the accent to Purple.
- In the **gear menu → Settings → Your quiet corner**, choose **Screen corners** or **Below camera island**. Camera-island mode uses the built-in display's safe-area geometry and only activates where macOS reports a real camera cutout. An external display or a Mac without that geometry keeps using its screen corners. The choice is stored locally and can be changed at any time.
- At the bottom of **Settings → Application**, choose **Quit DaBin** to close every window and stop Auto Capture, corner monitoring, previews, update work, and all other DaBin background activity. Existing captures, settings, and saved reminders remain available when you open the app again. The same native safety checks used by ⌘Q protect an active import, removal, or unsaved edit.
- The transient robot blinks, glances and occasionally shrugs while it is visible; this ambient work stops when it hides. macOS **Reduce Motion** keeps the expressions but removes moving, repeated and keyframed reactions.
- In the **gear menu → Settings → Get updates**, choose **Check for updates** to read DaBin’s latest public GitHub Release. DaBin never checks silently. When a newer verified build is available, **Download & install** checks the release URL, exact size and SHA-256 checksum before opening the built-in installer with a private, one-use update document. The installer validates and consumes that document, then asks before changing the app.
- Changing a filter keeps the header in place and gently resizes the bottom edge. If the board reaches the bottom of the display, scroll through the results inside it. Reduce Motion makes resizing immediate.
- Use **Settings → Open local archive** to browse saved content in Finder. Each record also has **Show saved folder**.
- Press **+** in Daily to add a task, with an optional reminder. New tasks are saved to today, newest first. Press the red **Task** button to mark it green **Completed**, or press it again to reopen. Completing pauses alerts; reopening restores a future reminder.
- Open any capture and choose **Turn into task** beneath its title, or right-click its card in Daily, Weekly, Search or Reminders. Text, links, screenshots and files keep their original content, preview, source, comments, reminders and capture date. The same card gains the **Task / Completed** toggle and joins the **✓ Tasks** filter while remaining in its original content filter. A converted item appears individually outside its former file batch or automatic-hour summary so its task status stays visible. Converting while editing keeps your unsaved comment and reminder draft.
- Unfinished tasks **without reminders** carry forward above each later day's captures, with their **original creation date and a thin purple frame**. Tasks **with reminders** appear at the top only on their reminder date. Completing stops this highlighting; every task remains archived on its original creation day. Removing a reminder restores daily carryover. A board left on Today advances at midnight or wake; browsing an older day stays on that day.
- Every capture has **Comment** and **Reminder** buttons. Save changes in Detail. Dismissed edits remain in memory; quitting with unsaved edits asks first.
- Press the purple **up chevron** on any capture to minimize it; the **down chevron** expands it again. The choice is remembered. Its title, time, type/task toggle, Comment and Reminder controls remain available, and the full content still appears in search and Detail.
- Press the purple **trash icon** and confirm **Remove** to delete a capture and DaBin’s copies, comments and reminder. Original files at their source are kept. This cannot be undone. If local cleanup fails, DaBin reports it and retries on opening. Keep DaBin open until removal finishes.
- Search shows only matching dates, plus the immediate same-day capture before and after each hit. A type filter limits matches; neighboring context can have other types. Search opened from Weekly also names its selected-day or seven-day scope.
- Enable website preview fetching under the **gear menu → Settings**. It is off initially; URL cards and Open original already work. Enabling previews contacts websites for new and earlier saved links that need previews. Read **Settings → Privacy policy & data controls** for what stays local, optional website requests, backups and removal.
- Saving the first reminder requests macOS notification permission. A saved reminder remains visible if permission is denied; the app reports its notification state. Delivery is subject to macOS permission, Focus, and system conditions.

## What is included

Native SwiftUI content in AppKit panels; Core Data metadata; a dated local archive with readable records and managed originals; drag/paste and file-promise intake; PDF/image/video/system previews; contextual search; comments; UserNotifications scheduling; light/dark colors; a native layer-based robot character with Reduced Motion behavior; an Xcode project, source, tests, and the unchanged handoff.

The supplied robot SVG is preserved as an original handoff resource. The transient robot is drawn with native macOS layers so its face, lid, arms, intake and body can react independently. Normal app storage starts empty; review fixtures are isolated from it.

## Update the current installation

The direct GitHub build can pull a release from inside DaBin: open Settings and use the first **Get updates** card, choose **Check for updates**, then **Download & install**. The card always shows the installed version, status, and latest GitHub release link without scrolling. The app accepts only the fixed `RoeyAsterix/DaBin` HTTPS release path and validates the published size and SHA-256 checksum. It writes a small, private, one-use update document beside the downloaded ZIP and opens that document with its signed built-in helper. The helper validates the document and package location, independently rechecks the ZIP, asks for confirmation, verifies the ARM64 Release app, backs up `~/Applications/DaBin.app` under `~/Applications/.DaBinBackups/`, installs and verifies the replacement, then reopens Daily. It does not read, move or delete the sandboxed capture archive.

The repository also keeps permanent package downloads: [download the latest in-app update package](https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-Update.zip), or [download the latest unsigned Apple Silicon test package](https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-AppleSilicon.zip). Their URLs stay the same when a new public release becomes latest. The in-app updater continues to use the versioned package named in the public release manifest so its strict version, URL, byte-count, and checksum validation remains unchanged.

Release 0.3.18 restores update discovery on the first Settings screen and adds permanent repository download URLs. Verified release staging makes each stable alias byte-identical to its versioned package, while the published-release workflow repairs missing aliases automatically.

The current packages are locally ad-hoc signed and not notarized. They pass code-seal and package-integrity checks, but Gatekeeper rejects a normal first launch after a browser, messaging app, or AirDrop applies quarantine. They must not be presented as public direct installers. Existing installations should update from DaBin's **Get updates** card. A public first-install package requires Developer ID Application signing, hardened runtime, Apple notarization, a stapled ticket, and Gatekeeper validation. The direct update channel is compiled only by the standalone build script; the Xcode Mac App Store configuration excludes the downloader and helper because Store builds must update through the App Store.

## Build and test

Built here with Apple Swift **6.3.2**, Command Line Tools macOS SDK **26.5**, on macOS **26.6.2**, targeting macOS **14.0+**, ARM64. Full Xcode is not installed on this machine. Intel and older macOS runtime behavior have not been verified.

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

The Xcode project includes native XCTest smoke tests. Those Xcode commands were not run here. The optimized standalone command-line test suite was run; see [QA_RESULTS.md](QA_RESULTS.md) for passing and blocked checks. It records per-suite results and source fingerprints, and continues after a failing suite. Build, tests and the Xcode project use the same source inventory. See [ARCHITECTURE.md](ARCHITECTURE.md) for ownership and module boundaries.

Desktop/Documents synchronization on this Mac reattaches Finder metadata to app bundles, which fails strict signature verification. Use the installed personal-Applications copy; its signature remains verified. The ZIP contains the clean signed file contents, without those extended attributes. `install_app.py` copies a build into personal Applications and verifies it there.

## Mac App Store preparation

See [APP_STORE_READINESS.md](APP_STORE_READINESS.md) for the current audit and release gates. The source includes a bundled privacy policy, privacy manifest and Productivity category. The GitHub policy and support pages become public with this repository. Submission still needs full Xcode, an Apple Developer team, release signing, validation and App Store Connect metadata. `python3 scripts/app_store_preflight.py --static-only` checks source packaging; the release preflight intentionally fails while owner inputs are missing.

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

Edit comments and task status in DaBin. If generated files were changed externally, their old bytes are preserved under `Local edits/` before regeneration; outside edits are not imported into the app. Do not move or delete managed originals. Back up the full DaBin directory while the app is closed. Do not delete a database to fix a launch error.

For local maintenance with DaBin closed, the installed executable accepts `--organize-archive`. It updates dated folders without opening windows, contacting websites, reading the clipboard, or scheduling notifications.

There is no account, analytics, cloud sync, external AI processing, launch-at-login registration, automatic update check, or automatic upload. Clipboard polling runs only while the user-enabled Auto Capture service is active and unpaused. An explicit update check contacts GitHub; optional link previews contact saved websites only when enabled. No Accessibility, Screen Recording, camera, or microphone permission is needed by the app. Reveal detection reads pointer position and ordinary macOS screen geometry only. External file access comes from explicit paste/drop transfers, a user-selected Auto Capture screenshot folder, or a destination the user chooses for a day or week text download. Directories, aliases and symbolic links are rejected with an explanation; import their regular files instead. Source files are preserved.

## Verification and limits

See [QA_RESULTS.md](QA_RESULTS.md) for checks actually run and remaining native integration checks, and [IMPLEMENTATION_NOTES.md](IMPLEMENTATION_NOTES.md) for deliberate changes from the attached handoff.
