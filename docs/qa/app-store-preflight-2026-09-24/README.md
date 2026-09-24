# DaBin App Store preflight — 24 September 2026

This evidence set records the final local QA pass for DaBin 0.3.18 (45) before Apple Developer enrollment and distribution signing.

## Result

The current source has no known functional, compile, render, privacy-resource, static packaging, quarantine, or clean-copy integrity failure. It cannot yet be submitted because this Mac has Command Line Tools rather than full Xcode, no Apple Developer Team ID is configured, and no distribution signing identity is installed.

The final distribution-signed archive must still pass Xcode Organizer validation and live checks on macOS 14 and the current macOS release. The owner must also confirm the Bundle ID, legal publisher/copyright, support contact, App Store privacy answers, review contact, listing text, age rating, availability, and pricing.

## Final verified source

- Release test suites: **33/33 passed**
- Assertions/checks: **2,929 passed**
- QA source fingerprint: `b010397bddfe119fe589c1070828d9f437523aba481df60b600c4a5669bf68d8`
- QA report SHA-256: `cd250373061288d29b0b2d076edb198ce5ff0fb3660474d64007cbce08902cdb`
- Optimized build: ARM64, macOS 14 target, Swift warnings as errors
- Production build fingerprint: `3b14ec3991186b55b0550a15ab1b3d92615bfb905dde71cd3f175e56e7a26d45`
- Main executable SHA-256: `cfbf7a5d9250ae4a68d483e227aa28f4fa20b24e648a69c5b52a3a75623116a6`
- Build receipt SHA-256: `2d6c4d0d6351c0ea60cd2b12e83e0f2c0ef641dc1db6403c3a2d31ba1c3f9435`
- Receipt inputs: **86/86 matched** after the build

## Additional gates

- Store-only optimized compile without `DABIN_DIRECT_UPDATES`: passed, 61 sources, ARM64, no non-system dependencies
- Store-only binary SHA-256: `084f560e7d5b38e517a9e7702d9abea49a83330f2cf71bbc4e7e18d016cfbdb8`
- Static App Store preflight: **21/21 passed**
- Release UI renderer: **50/50 passed**
- Privacy renderer: **11/11 passed**, four PNGs and all nine policy topics
- Synthetic media integration: **39/39 passed**
- Notarized distribution tests: **21/21 passed**
- Clean copied app: zero extended attributes, strict signature verification passed, ARM64 only, Apple system dependencies only
- Quarantine detector: found the synthetic nested fixture and found none in the clean app
- Current local direct build remains ad hoc signed, so Gatekeeper rejection is expected and is not Store distribution evidence

## App Store review fixes included

- One-time first launch Daily presentation, followed by DaBin's normal quiet corner behavior
- Persistent menu bar status with Open Daily, Auto Capture state, Pause/Resume, Settings, and Quit
- Auto Capture consent remains explicit and off by default
- Reduce Transparency forces a solid readable board surface
- Export success and failure feedback is announced to VoiceOver
- Export-compliance declaration for absent/non-exempt encryption
- App Store archives default outside the File Provider source tree and are reverified after creation
- Distribution preflight rejects a quarantine attribute anywhere in the app bundle

## Evidence files

- `full-run-report.json` — complete registered Release suite result and input hashes
- `build-receipt.json` — production input and executable hashes
- `release-ui-renders.json` — 50-view render manifest
- `privacy-renders.json` and `privacy-render.log` — isolated privacy-policy render QA
- `app-store-preflight-static.log` — passing source/package checks
- `app-store-preflight-environment.log` — expected Team ID and Xcode environment blockers
- `environment.json` — selected toolchain and signing inventory
- `SHA256SUMS.json` — hashes for the evidence files

Draft 1440 × 900 RGB screenshots are in [`docs/app-store/screenshots/1440x900`](../../app-store/screenshots/1440x900/README.md). They use fictional isolated data and require a final comparison with the signed archive before upload.
