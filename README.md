# DaBin

DaBin is a private work inbox for Apple Silicon Macs: save what matters, find it again, and resume the work attached to it. Paste or drop text, links, images, videos, PDFs and files, or use **Add → New note**. The purple robot remains a quick capture target, while three labeled views make the archive easier to use: **Today**, **Library** and **Follow-ups**.

Captures stay on this Mac in a dated archive. **Today** shows what was received on the selected day, with automatic batches collapsed. **Library** covers all dates; pin useful captures or optionally assign a project. A project's pinned references, next actions and recent captures help you pick up where you left off. **Follow-ups** brings unfinished tasks and reminders together, with Complete and Snooze actions. Notes, source content and original capture dates stay attached.

The persistent **Search all captures** field searches the full archive from every view. Results show matches first; **Show nearby captures** adds optional same-day context. Icon filters narrow by content type; their hover labels can be disabled in Settings. The **Timeline** Day/Week control and calendar preserve date browsing. **Add** offers Paste clipboard, New note, Import files and New task. Preview-first cards expose copy, comment, reminder, task and more actions as icons. The gear opens Settings directly. **More** holds day/week text exports, Recently Deleted and archive backup/restore.

Removed captures go to **Recently Deleted**, with Undo for the latest removal and a separate confirmation for permanent deletion. A local `.dabinbackup` directory package includes capture metadata, saved originals, readable records, saved local edits and deleted captures. Restore verifies the package and adds missing captures; it rejects conflicts instead of overwriting existing data. Preferences are not part of the backup.

Today opens once on first launch. Afterwards, use the robot, menu bar or global shortcuts: **⌃⌥Space** searches and **⌃⌥V** saves the current clipboard. Settings offers an alternate chord and lets you disable global shortcuts. **Quiet mode** opens the board promptly and suppresses automatic capture celebrations. The board supports dark mode and theme colors; new preferences default to an opaque background, while existing transparency choices are retained. The robot still follows macOS Reduce Motion.

DaBin recognizes text in saved screenshots, images, PDFs and supported text documents entirely on the Mac. Search can find that content even when the filename or caption does not contain the query, and shows the matching recognized line. Capture details expose the searchable text and Settings can rebuild the local index. This is local text search, not semantic search. There is no cloud sync, and no recognized content is sent to an external AI or OCR service.

The working version is **0.4.1, build 49**, a local candidate. See its [release notes](docs/RELEASE_NOTES_0.4.1.md); this does not identify it as the current public GitHub release or an Apple-approved build.

## A little desktop buddy

Captures have larger fitted previews and a compact action rail. Turning a capture into a task opens its workspace, where you can drop or paste more files and text, set a date/time reminder or an hours:minutes countdown, and mark it complete. A successful completion makes the visible robot happy. Countdown time starts when you save; it does not restart when reopened.

Library uses icon filters and responsive columns. Source badges use locally installed app icons when the saved source is available; website locations have a domain/globe fallback. DaBin shows its own verified storage destination and does not claim to monitor pastes into other apps.

Auto Capture is beside the logo. The robot's full-view shell is thinner; drag its edges or corners to resize it, or use Expand/Restore to fill the current display's safe area. Manual island reveal takes 0.55 seconds. Native window appearance follows the light/dark preference, and hover tooltips can be turned off without removing accessibility labels.

## Optional Auto Capture

Automatic **Clipboard** and **Screenshots** capture are separate opt-in choices, both **off by default**. Clipboard capture works without a screenshot folder. Screenshot capture requires a folder you explicitly choose; missing screenshot access does not stop an enabled clipboard channel. Enabling a channel establishes a new baseline: existing clipboard content and existing folder images are not imported. The board and Settings show the current state, and **Pause/Resume** controls the selected channels together.

Screenshot-folder access begins only after you choose a folder in the macOS folder picker. DaBin retains that authorization as a security-scoped bookmark so it can monitor the chosen location while Auto Capture is enabled. New image files in that folder are treated as screenshot captures, so choose a dedicated screenshot folder. macOS does not provide a public notification for every system screenshot: DaBin can see images written to the chosen folder, while screenshots sent to the clipboard can arrive through clipboard monitoring. A screenshot saved somewhere else is outside the folder monitor.

DaBin records a best-effort source application when macOS makes one reasonably identifiable. Source attribution can be unavailable or imprecise, so it is descriptive rather than proof of origin. DaBin itself and common password managers are excluded by default. If the same image arrives through the screenshot folder and clipboard within a short interval, a normalized fingerprint suppresses the second channel's copy; repeating the image later or through the same channel remains a new action. Four or more successful automatic actions in one capture hour become an expandable hourly group on Daily. A brief nonactivating robot emerges from the primary display's camera island, or the external primary display's top-right, and climbs down and eats a generic paper token using ten shuffled eating reactions, with no repeats from the previous three. Rapid captures share the token's exact `×N` count; later arrivals roll into one bounded follow-up group. Opening the board takes priority, and capture feedback waits until the board closes.

Automatic captures use the same local archive as manual captures. An automatically captured link never requests a website preview, even if previews are enabled for manually saved links. When Quiet mode is off, the confirmation begins only after an item has saved. Its native panel requests exclusion from window capture and never contains the captured image or clipboard text. macOS does not provide a universal pre-screenshot notification: third-party or system screen recorders can still include visible overlays depending on their capture API.

Double-clicking the robot transforms its body into the existing DaBin view in about 1.15 seconds. The head, hands and feet have reserved space outside the cards and controls. The eyes follow the pointer gently while the view is visible. Closing reverses the transformation in 0.42 seconds. Reduce Motion uses a short fade and a static frame. These are native Core Animation layers; the app keeps its usual compact window, navigation, drag/drop and keyboard controls.

![DaBin robot and Daily board](design/robot-preview.png)

## Latest release files

- [In-app update package for an existing DaBin installation](https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-Update.zip)
- [Unsigned Apple Silicon test package](https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-AppleSilicon.zip)
- [Latest release details](https://github.com/RoeyAsterix/DaBin/releases/latest)

These permanent links follow the newest public GitHub release. The current files are ad-hoc signed and are not notarized. A browser, messaging app, or AirDrop marks them as downloaded, so Gatekeeper blocks a normal first installation. Existing DaBin installations can update safely through **Settings → Get updates**. A public first-install package must be signed with a Developer ID and notarized before it is described as a direct installer.

## Start here

- [Native app guide](native/README.md)
- [0.4.1 desktop buddy candidate notes](docs/RELEASE_NOTES_0.4.1.md)
- [0.4.0 local candidate notes](docs/RELEASE_NOTES_0.4.0.md)
- [0.3.18 release notes](docs/RELEASE_NOTES_0.3.18.md)
- [0.3.17 release notes](docs/RELEASE_NOTES_0.3.17.md)
- [0.3.16 release notes](docs/RELEASE_NOTES_0.3.16.md)
- [0.3.15 release notes](docs/RELEASE_NOTES_0.3.15.md)
- [One-page PDF guide](docs/DaBin-Quick-Guide.pdf)
- [Architecture](native/ARCHITECTURE.md)
- [QA results](native/QA_RESULTS.md)
- [Privacy policy](native/Resources/PrivacyPolicy.md)
- [Mac App Store readiness](native/APP_STORE_READINESS.md)
- [App Store Connect draft](docs/app-store/APP_STORE_CONNECT_DRAFT.md)
- [App Store screenshot drafts](docs/app-store/screenshots/1440x900/README.md)
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
