# DaBin 0.3.18

DaBin 0.3.18 puts updates where they are easy to find and gives the repository permanent download links that always follow the newest public release.

## What changed

- Places **Get updates** at the top of Settings, visible immediately when Settings opens.
- Shows the installed version and current update status in one compact rounded card.
- Keeps **Check for updates** available without scrolling.
- Shows **Download & install** in the same card when a newer verified release is available.
- Keeps progress, success, failure, and up-to-date feedback in place.
- Adds an always-visible **Latest release on GitHub** link for direct builds, even before an update check.
- Keeps App Store builds on Apple’s update path while still showing their installed version and update status.
- Adds stable GitHub assets for the recommended installer/update and direct Apple Silicon download.

## Permanent downloads

- **Recommended installer or update:** `https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-Update.zip`
- **Direct Apple Silicon package:** `https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-AppleSilicon.zip`
- **Latest release details:** `https://github.com/RoeyAsterix/DaBin/releases/latest`

Each release also retains its versioned package names. The in-app updater continues to use the exact versioned URL, size, and SHA-256 from `DaBin-update.json`.

## Verification

Release verification covers the full optimized test suite, the first-screen Settings layout in light and dark appearance, the narrow Settings stress render, direct and App Store update-channel boundaries, ARM64 build identity, both package formats, stable-alias byte identity, public GitHub downloads, and a live update from 0.3.17.

The direct packages are locally ad-hoc signed for the owner’s Mac. Frictionless distribution to unrelated Macs still requires Developer ID signing and Apple notarization.
