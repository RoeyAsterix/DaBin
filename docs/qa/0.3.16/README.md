# DaBin 0.3.16 release evidence

This directory records completed functional, visual, live-interaction, build, package and Store-readiness checks for DaBin 0.3.16 (41). Publication and the final installed-app update are recorded after the tagged release exists.

## Pre-publication result

- **30/30** registered optimized Release suites passed with no source changes during the final run at `20260924T054439197741Z`.
- Header interaction passed **46 checks**. The purple `1.calendar` and `7.calendar` buttons switch Daily and Weekly in both directions, preserve 40 × 34-point targets, fit the 380-point Weekly header and keep every existing header command functional.
- Fresh rendering produced **50 release interface views**. Retained evidence covers Daily and narrow Weekly, light and dark appearances, native 2× output and both new mode-tooltip positions.
- A clean app extracted from the verified update ZIP passed a real pointer dwell, accessibility inspection and Daily → Weekly → Daily interaction. The tooltip remained absent from the accessibility tree, while the buttons exposed **Daily view**, **Weekly view**, selected state and stable identifiers.
- The candidate live check left all **33 archive files** and the preferences file byte-identical.
- The optimized direct build is **0.3.16 (41)** for ARM64, with production fingerprint `5f45db94220540928f16778d000e8e6dec2082260b4ca169cdd70a1b37dd4e86`.
- The verified update ZIP passed isolated fresh installation, replacement, backup, clean-copy signature validation, extraction, exact executable identity and update-document handoff.
- Static Store packaging passed all **20** checks. Release preflight retains the two external prerequisites already documented: a 10-character Apple Developer Team ID and full Xcode.
- GitHub publication, unauthenticated asset verification and the installed 0.3.15 → 0.3.16 self-update remain pending the tagged release.

The direct package is locally ad-hoc signed for this Mac. Developer ID signing and notarization, or Mac App Store distribution signing, remain separate trust boundaries.

## Artifact identities

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `full-run/report.json` | 28,089 | `79506dbca2e444fd6b41667c825520045c6617814f1ed2b01dc66bc46e781525` |
| `build-receipt-v0.3.16.json` | 9,147 | `f83ea96c594a3c6d1a10ba9e4a8eed87613ee86ff23429e8b6164cd977388b86` |
| DaBin ARM64 executable | 5,984,832 | `100a77fa2f09631fc3903f453e97f5bd8dc124a97fde50b5b59ee147eed0b158` |
| `DaBin-0.3.16-Update.zip` | 3,391,707 | `c938b966d6154f28f9c3273c4e0b577646ea7a3be50b120e56777d1085120992` |
| `update-manifest-v0.3.16.json` | 596 | `f4e4b3ba7eea6edc2ba002b2312ade603b5e032e95e0aa2b447d06184adf31d2` |
| `DaBin-Quick-Guide.pdf` | 299,779 | `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291` |
| `release-ui-renders.json` | 50,184 | `d07bb532562ed095dd621280b3b4f333cfb5722158f5e2cb4dcc950ba8aca5c3` |
| `local-live-mode-v0.3.16.json` | 1,330 | `4b225b69a3c8343a9052ec728c4f57d7fe1d49a60548ae6d354cd94f589931ce` |
| Live Weekly-tooltip header | 47,944 | `1802ed2c6433644f2bd97da1fb52dfde0d14550e6a9b3a8d14417bc48fb56b96` |
| `RELEASE_NOTES_0.3.16.md` | 1,448 | `e2aa1a0d5d5651e46b4756a11f4b4d1d537120dad4ef6934f945d0187853b18c` |

## Files

- `full-run/`: complete 30-suite Release report, compile logs, suite logs and stable input hashes.
- `release-ui-renders.json`: manifest for 50 production-view renders.
- `renders/`: retained Daily, narrow Weekly, 2× and mode-tooltip views in light and dark appearance.
- `renders/live-mode-weekly-tooltip-dark-380pt@2x.png`: privacy-safe header-only capture from the real pointer check.
- `local-live-mode-v0.3.16.json`: packaged-app pointer, accessibility, mode-switch, archive and preference verification.
- Build receipt, build/package logs, update manifest, unchanged PDF layout check and Store preflight logs complete the release evidence.
