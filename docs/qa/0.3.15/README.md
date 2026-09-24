# DaBin 0.3.15 release evidence

This directory records completed functional, visual, live-hover, build, package and Store-readiness checks for DaBin 0.3.15 (40). Public publication and the final installed-app update are recorded after the tagged release exists.

## Pre-publication result

- **30/30** registered optimized Release suites passed with no source changes during the final run at `20260924T051943963679Z`.
- Header interaction passed **39 checks** and all existing commands remained functional. The paired action/filter rows retain their 280 × 34-point geometry.
- Fresh rendering produced **46 production-view renders**. The exact Release build was also launched separately and received a real mouse-moved event over Settings: the short **Settings** tooltip appeared after dwell, kept **Settings and options** as the accessibility name, remained absent from the accessibility tree itself, and the native menu still opened afterward.
- The optimized direct build is **0.3.15 (40)** for ARM64, with production fingerprint `9678a70e2bb9ecc0e0e4a4df9f44d00dcbbe6c5eb3e5094126477e7aa3884192`.
- The ARM64 executable is **5,987,296 bytes**, SHA-256 `59a9db45185dc6ca8cba91bf82ae960acdceeae1f038bda0c0630a29afb14f8a`.
- The verified update ZIP is **3,391,579 bytes**, SHA-256 `b4e93f9d85147fc196b0a5e73038e70f4334003ac405fd5ad5323f7b96457b58`. Package QA passed isolated fresh installation, replacement, backup, clean-copy signature validation, extraction, manifest round trip, exact executable identity and document handoff.
- The unchanged one-page A4 PDF guide is **299,779 bytes**, SHA-256 `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291`.
- Static Store packaging passed all **20** checks. Release preflight retains the two external prerequisites already documented: a 10-character Apple Developer Team ID and full Xcode.
- GitHub publication, unauthenticated asset verification and the installed 0.3.14 → 0.3.15 self-update remain pending the tagged release.

The direct package is locally ad-hoc signed for this Mac. Developer ID signing and notarization, or Mac App Store distribution signing, remain separate trust boundaries.

## Artifact identities

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `full-run/report.json` | 28,088 | `b5dcde1016f3005217a840cbcced86a63575b0e391748358c5e48e015a61e29d` |
| `build-receipt-v0.3.15.json` | 9,147 | `8f3569afb337dfcedde2c851a6827d12877962757e8129470a85886c1f2f611d` |
| DaBin ARM64 executable | 5,987,296 | `59a9db45185dc6ca8cba91bf82ae960acdceeae1f038bda0c0630a29afb14f8a` |
| `DaBin-0.3.15-Update.zip` | 3,391,579 | `b4e93f9d85147fc196b0a5e73038e70f4334003ac405fd5ad5323f7b96457b58` |
| `update-manifest-v0.3.15.json` | 596 | `b3aa0541f398f54c28a4ca061bc710cd5677ee210fc78123ee879b3a9d35e8f5` |
| `DaBin-Quick-Guide.pdf` | 299,779 | `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291` |
| `release-ui-renders.json` | 47,546 | `9885809cbb5e879ad6b3380892e33d78d5ade51ff41fa768532ad9b5bc81ea47` |
| `local-live-hover-v0.3.15.json` | 1,240 | `ef51cbe6ded6a60bf68ce7e2eb2d1d7a2e818f46e5acc496b2f38a778cfce89d` |

## Files

- `full-run/`: complete 30-suite Release report, compile logs, suite logs and stable input hashes.
- `release-ui-renders.json`: manifest for 46 production-view renders.
- `local-live-hover-v0.3.15.json`: exact built-app pointer, accessibility, menu and archive verification.
- `renders/live-settings-tooltip-header-dark-380pt@2x.png`: privacy-safe header-only capture from the real hover check.
- `renders/`: retained light/dark tooltip, Daily and narrow Weekly renders.
- Build receipt, build/package logs, update manifest, unchanged PDF layout check and Store preflight logs complete the release evidence.
