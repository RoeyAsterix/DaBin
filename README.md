# DaBin

DaBin is a native Apple Silicon macOS app that turns things you paste or drag into a private daily board. Daily opens once on first launch so the app is easy to discover. After you close it, moving the pointer into any screen corner reveals a small purple robot. On a Mac with a built-in camera island, Settings can move its home below the island; displays without one use the top-right entry point for this setting. A compact menu bar item keeps Open Daily, Auto Capture status, Pause/Resume, Settings, and Quit available while DaBin runs. Drop text, links, images, videos, PDFs, documents, or several files onto the robot, or hover and paste; double-click it to browse Daily.

Captures stay on the Mac in a dated archive. Each card can hold a comment or reminder, and its upper-right copy icon returns the original captured text, link, task or locally saved file to the clipboard. Grouped drops copy all their files together. Open any capture and choose **Turn into task**, or use its card’s right-click menu; its original content, comments and reminders stay attached. Tasks carry forward until completed, unless they have a reminder date. Daily includes All, Text, Links, Files, Media and Tasks filters plus contextual search; Text isolates copied, pasted or dragged plain text. A compact Daily/Weekly control browses the seven-day range ending on the selected date, while Weekly displays only dates that contain captures or tasks. In Weekly, Search can target one explicitly selected day or the complete seven-day range, and Export can copy or download either scope. Switching views preserves the selected date, filter, scroll position and drafts. Downloads use chronological UTF-8 text and include the complete selected day or week regardless of the active filter. The board supports dark mode, theme colors and adjustable transparency. The native robot looks toward the pointer, opens up for incoming content, chews while saving and responds to the result. It follows the macOS Reduce Motion preference.

DaBin recognizes text in saved screenshots, images, PDFs and supported text documents entirely on the Mac. Search can find that content even when the filename or caption does not contain the query, and shows the matching recognized line in its original date context. Capture details expose the searchable text and Settings can rebuild the local index. No recognized content is sent to an external AI or OCR service.

## Optional Auto Capture

Auto Capture is **off by default**. If you turn it on, DaBin can save later clipboard changes and new image files written to a folder you choose as your screenshot location. Enabling clipboard monitoring establishes a new baseline: content that was already on the clipboard is not imported, and only subsequent changes are considered. Pause or turn off Auto Capture to stop its clipboard and folder monitoring immediately.

Screenshot-folder access begins only after you choose a folder in the macOS folder picker. DaBin retains that authorization as a security-scoped bookmark so it can monitor the chosen location while Auto Capture is enabled. New image files in that folder are treated as screenshot captures, so choose a dedicated screenshot folder. macOS does not provide a public notification for every system screenshot: DaBin can see images written to the chosen folder, while screenshots sent to the clipboard can arrive through clipboard monitoring. A screenshot saved somewhere else is outside the folder monitor.

DaBin records a best-effort source application when macOS makes one reasonably identifiable. Source attribution can be unavailable or imprecise, so it is descriptive rather than proof of origin. DaBin itself and common password managers are excluded by default. If the same image arrives through the screenshot folder and clipboard within a short interval, a normalized fingerprint suppresses the second channel's copy; repeating the image later or through the same channel remains a new action. Four or more successful automatic actions in one capture hour become an expandable hourly group on Daily. A brief nonactivating robot emerges from the primary display's camera island, or the external primary display's top-right, and climbs down and eats a generic paper token using ten shuffled eating reactions, with no repeats from the previous three. Rapid captures share the token's exact `×N` count; later arrivals roll into one bounded follow-up group. Opening the board takes priority, and capture feedback waits until the board closes.

Automatic captures use the same local archive as manual captures. An automatically captured link never requests a website preview, even if previews are enabled for manually saved links. The confirmation begins only after an item has saved. Its native panel requests exclusion from window capture and never contains the captured image or clipboard text. macOS does not provide a universal pre-screenshot notification: third-party or system screen recorders can still include visible overlays depending on their capture API.

Double-clicking the robot transforms its body into the existing DaBin view in about 1.15 seconds. The head, hands and feet have reserved space outside the cards and controls. The eyes follow the pointer gently while the view is visible. Closing reverses the transformation in 0.42 seconds. Reduce Motion uses a short fade and a static frame. These are native Core Animation layers; the app keeps its usual compact window, navigation, drag/drop and keyboard controls.

![DaBin robot and Daily board](design/robot-preview.png)

## Latest release files

- [In-app update package for an existing DaBin installation](https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-Update.zip)
- [Unsigned Apple Silicon test package](https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-AppleSilicon.zip)
- [Latest release details](https://github.com/RoeyAsterix/DaBin/releases/latest)

These permanent links follow the newest public GitHub release. The current files are ad-hoc signed and are not notarized. A browser, messaging app, or AirDrop marks them as downloaded, so Gatekeeper blocks a normal first installation. Existing DaBin installations can update safely through **Settings → Get updates**. A public first-install package must be signed with a Developer ID and notarized before it is described as a direct installer.

## Start here

- [Native app guide](native/README.md)
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
