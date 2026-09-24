# DaBin

DaBin is a native Apple Silicon macOS app that turns things you paste or drag into a private daily board. By default, moving the pointer into any screen corner reveals a small purple robot. On a Mac with a built-in camera island, Settings can move its home below the island; displays without one continue using their corners. Drop text, links, images, videos, PDFs, documents, or several files onto the robot, or hover and paste; double-click it to browse Daily.

Captures stay on the Mac in a dated archive. Each card can hold a comment or reminder. Tasks carry forward until completed, unless they have a reminder date. Daily includes All, Text, Links, Files, Media and Tasks filters plus contextual search; Text isolates copied, pasted or dragged plain text. A compact Daily/Weekly control browses the seven-day range ending on the selected date, while Weekly displays only dates that contain captures or tasks. In Weekly, Search can target one explicitly selected day or the complete seven-day range, and Export can copy or download either scope. Switching views preserves the selected date, filter, scroll position and drafts. Downloads use chronological UTF-8 text and include the complete selected day or week regardless of the active filter. The board supports dark mode, theme colors and adjustable transparency. The native robot looks toward the pointer, opens up for incoming content, chews while saving and responds to the result. It follows the macOS Reduce Motion preference.

## Optional Auto Capture

Auto Capture is **off by default**. If you turn it on, DaBin can save later clipboard changes and new image files written to a folder you choose as your screenshot location. Enabling clipboard monitoring establishes a new baseline: content that was already on the clipboard is not imported, and only subsequent changes are considered. Pause or turn off Auto Capture to stop its clipboard and folder monitoring immediately.

Screenshot-folder access begins only after you choose a folder in the macOS folder picker. DaBin retains that authorization as a security-scoped bookmark so it can monitor the chosen location while Auto Capture is enabled. New image files in that folder are treated as screenshot captures, so choose a dedicated screenshot folder. macOS does not provide a public notification for every system screenshot: DaBin can see images written to the chosen folder, while screenshots sent to the clipboard can arrive through clipboard monitoring. A screenshot saved somewhere else is outside the folder monitor.

DaBin records a best-effort source application when macOS makes one reasonably identifiable. Source attribution can be unavailable or imprecise, so it is descriptive rather than proof of origin. DaBin itself and common password managers are excluded by default. If the same image arrives through the screenshot folder and clipboard within a short interval, a normalized fingerprint suppresses the second channel's copy; repeating the image later or through the same channel remains a new action. Four or more successful automatic actions in one capture hour become an expandable hourly group on Daily. A brief nonactivating robot emerges from the primary display's camera island, or the external primary display's top-right, and plays one of twelve shuffled success reactions. Rapid captures share that popup and update its `×N` count.

Automatic captures use the same local archive as manual captures. An automatically captured link never requests a website preview, even if previews are enabled for manually saved links. The confirmation appears only after an item has saved and is excluded from screen capture while visible.

![DaBin robot and Daily board](design/robot-preview.png)

## Start here

- [Native app guide](native/README.md)
- [0.3.16 release notes](docs/RELEASE_NOTES_0.3.16.md)
- [0.3.15 release notes](docs/RELEASE_NOTES_0.3.15.md)
- [One-page PDF guide](docs/DaBin-Quick-Guide.pdf)
- [Architecture](native/ARCHITECTURE.md)
- [QA results](native/QA_RESULTS.md)
- [Privacy policy](native/Resources/PrivacyPolicy.md)
- [Mac App Store readiness](native/APP_STORE_READINESS.md)
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

The direct build has a user-initiated GitHub Releases channel under **Settings → Software updates**. It accepts only this repository’s fixed HTTPS release path, verifies the published byte count and SHA-256 checksum, then gives the bundled installer a private, one-use update document. The installer validates and consumes that document, re-verifies the package and application, asks before replacement, and backs up the previous installation. The capture archive remains untouched. There are no silent update checks.

Release 0.3.16 replaces the text Daily/Weekly segment with matching purple `1` and `7` calendar icons. They use the same symbol size, circular selected/hover states, pressed feedback, keyboard focus and short delayed tooltips as the other header icons, while keeping full **Daily view** and **Weekly view** accessibility names. All 30 optimized Release suites, 50 release renders, public asset verification and the installed-app update passed. The verified updater preserved all 33 archive files and preferences byte for byte, along with the existing Desktop link.

The current personal release is ad-hoc signed for the owner’s Mac. General distribution still requires a stable Developer ID signature and Apple notarization. The Mac App Store configuration compiles without the direct downloader and helper; Store builds update through Apple.

## Repository scope

This repository contains the native source, resources, tests, build and release tools, design history, handoff documents, QA documentation, and the PDF guide. Generated builds, old ZIP packages, temporary renders, user data, and compiler caches are ignored. Release ZIPs belong in GitHub Releases.

No open source license has been granted in this repository.
