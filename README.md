# DaBin

DaBin is a native Apple Silicon macOS app that turns things you paste or drag into a private daily board. Move the pointer into any screen corner and a small purple robot appears. Drop text, links, images, videos, PDFs, documents, or several files onto it; double-click the robot to browse Daily.

Captures stay on the Mac in a dated archive. Each card can hold a comment or reminder. Tasks carry forward until completed, unless they have a reminder date. Daily includes type filters and contextual search; Today opens a seven-day view. The board supports dark mode, theme colors and adjustable transparency.

![DaBin robot and Daily board](design/robot-preview.png)

## Start here

- [Native app guide](native/README.md)
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

The direct build has a user-initiated GitHub Releases channel under **Settings → Software updates**. It accepts only this repository’s fixed HTTPS release path, verifies the published byte count and SHA-256 checksum, then opens a bundled installer that asks before replacing the app. The installer re-verifies the package and application, backs up the previous installation, and leaves the capture archive unchanged. There are no silent update checks.

The current personal release is ad-hoc signed for the owner’s Mac. General distribution still requires a stable Developer ID signature and Apple notarization. The Mac App Store configuration compiles without the direct downloader and helper; Store builds update through Apple.

## Repository scope

This repository contains the native source, resources, tests, build and release tools, design history, handoff documents, QA documentation, and the PDF guide. Generated builds, old ZIP packages, temporary renders, user data, and compiler caches are ignored. Release ZIPs belong in GitHub Releases.

No open source license has been granted in this repository.
