# DaBin 0.3.14 release evidence

This directory records the completed functional, visual, build, package and Store-readiness checks for DaBin 0.3.14 (39). Public publication and the live in-app update are recorded after the tagged release exists.

## Pre-publication result

- **30/30** registered optimized Release suites passed with no source changes during the final run at `20260924T050733548601Z`.
- Header interaction passed **39 checks**, including the unchanged 280 × 34-point action/filter rows, tooltip label inventory, edge anchors, delayed presentation, cancellation, keyboard-focus presentation path and activation dismissal. All existing header actions also passed.
- Fresh rendering produced **46 release interface views**. Four retained tooltip views cover the first primary action and last filter at the 380-point board width in light and dark appearance. Both labels are readable, pointed at the correct row and unclipped.
- The optimized direct build is **0.3.14 (39)** for ARM64, with production fingerprint `e39dd3182ad87aeb266805bfb038b432b42f3e4b23b9e3e5a8e76b9fd88891c4`.
- The ARM64 executable is **5,973,664 bytes**, SHA-256 `80fb1e1c39455ad765b313c714b9abe20a3f5e52548e3ad4a10bad697e901f0c`.
- The verified update ZIP is **3,391,196 bytes**, SHA-256 `38495e16b2b5d1629fccaa152815b6c1c7da2f7800ab370e51267504631a96c2`. Package QA passed isolated fresh installation, replacement, backup, strict clean-copy signature validation, extraction, manifest round trip, executable identity and document handoff.
- The unchanged one-page A4 PDF guide is **299,779 bytes**, SHA-256 `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291`.
- Static Store source packaging passed all **20** checks. Release preflight remains blocked by the two external prerequisites already documented: a 10-character Apple Developer Team ID and full Xcode.
- GitHub publication, unauthenticated asset verification, the installed 0.3.13 → 0.3.14 self-update, archive/preferences preservation and live pointer/Menu checks are pending the tagged release.

The direct package is locally ad-hoc signed for this Mac. Developer ID signing and notarization, or Mac App Store distribution signing, remain separate trust boundaries.

## Artifact identities

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `full-run/report.json` | 28,091 | `b4d9007ecbc46a1e1988465b57a52f9fc40a21f6d32f9d0cf2308d4f1ad0998d` |
| `build-receipt-v0.3.14.json` | 9,147 | `32937f4981c882a7931a097f7035e8743883809d142d20d15c4076c355bf4a84` |
| DaBin ARM64 executable | 5,973,664 | `80fb1e1c39455ad765b313c714b9abe20a3f5e52548e3ad4a10bad697e901f0c` |
| `DaBin-0.3.14-Update.zip` | 3,391,196 | `38495e16b2b5d1629fccaa152815b6c1c7da2f7800ab370e51267504631a96c2` |
| `update-manifest-v0.3.14.json` | 596 | `5533b478adec138554ec84fb7103d414c12f41ed67adcba1071b3348a061b65d` |
| `DaBin-Quick-Guide.pdf` | 299,779 | `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291` |
| `release-ui-renders.json` | 47,546 | `bfa054306c2b3b0a830524e05183760291e21baa3752e334c021265125bd9254` |

## Files

- `full-run/`: complete 30-suite Release report, compile logs, suite logs and stable input hashes.
- `release-ui-renders.json`: manifest for the 46 production-view renders.
- `renders/`: ten retained light/dark tooltip, Daily and narrow Weekly views.
- `build-receipt-v0.3.14.json`: compiler, SDK, source inputs, source fingerprint and executable identity.
- `update-manifest-v0.3.14.json`: intended public version, filename, byte count, checksum and GitHub destinations.
- `build-v0.3.14.log` and `package-v0.3.14.log`: optimized build and isolated update-package verification.
- `quick-guide-layout-check.json`: retained A4 guide geometry and extraction evidence for the byte-identical PDF.
- `app-store-preflight-static-v0.3.14.log`: 20 passing source and packaging checks.
- `app-store-preflight-release-v0.3.14.log`: the two remaining external signing and tooling prerequisites.
