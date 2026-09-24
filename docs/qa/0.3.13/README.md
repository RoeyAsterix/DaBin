# DaBin 0.3.13 release evidence

This directory records the completed functional, visual, build, package, publication, live-update and Store-readiness checks for DaBin 0.3.13 (38).

## Result

- **30/30** registered optimized Release suites passed with **2,706 checks** and no source changes during the final run. The report covers the exact successful run from `20260924T044253444484Z`.
- The native header suite passed **31 checks**, including the shared 280-point row contract and real clicks at the redistributed Add, Search, Export and Notifications positions. The unlocked two-display regressions also passed **214 general window**, **97 Weekly window** and **110 filter-resize** checks.
- Both icon rows now occupy **280 × 34 points**. Every control uses the same 15-point SF Symbol in an 18-point canvas, a 40 × 34-point target and a 30-point circular selected or hover surface. The five primary actions and six filters meet the same outer edges while retaining their order and behavior.
- Fresh rendering produced **42 release interface views**. The retained feature subset covers empty and populated Daily at 1× and 2×, narrow 380-point Weekly and the representative 428-point two-day Weekly board in light and dark appearances. All inspected headers are centered, unclipped and visually balanced.
- The optimized ARM64 direct build is **0.3.13 (38)**. Its 78 receipt inputs total **1,246,040 bytes** and have production-source fingerprint `5f15ba6f71e53b59c8e99312c64654f4cab8edc7d6cfa012f87c2cdd9a07fa66`. The full source-and-test run fingerprint is `6b15c5656fa278e97071390c6c2b4de1788c2b75b5fa304e39390aafde42d9c0`.
- The ARM64 executable is **5,794,496 bytes**, SHA-256 `a85a557812a41c7783bfe411c1a25f1ade6088de9969d0f09f96b5a307455314`.
- The verified update ZIP is **3,363,483 bytes**, SHA-256 `56f3474526ae6509971f0dec5357de665a719282a88bf1b75c30b57c12cebbbd`. Package QA passed isolated fresh installation, replacement, backup, strict signature validation, extraction, manifest round trip, exact executable identity and the sandbox-compatible document handoff.
- The unchanged one-page A4 PDF guide is **299,779 bytes**, SHA-256 `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291`.
- Static App Store packaging passed **20/20** checks. Release preflight remains blocked by two owner/environment prerequisites: a 10-character Apple Developer Team ID and a full Xcode installation.
- The public GitHub release is the current latest release. Its release page and all four assets returned HTTP 200 without authentication; each downloaded asset was byte-identical to its recorded local source. The 596-byte update manifest, SHA-256 `69634ac3b2f019f953a5d16e26eaf87dd711d491705c389100f465740784f12a`, matches the ZIP's name, byte count and checksum, and the `/releases/latest/` manifest is byte-identical to the tagged manifest.
- The installed 0.3.12 (37) app downloaded the public ZIP and updated itself to 0.3.13 (38) through its normal Settings flow. The installed executable matches the verified production build, strict deep signature checks pass, all 33 archive files and the preferences file stayed byte-identical, the Desktop link stayed intact, and the prior app was preserved as a verified backup. Live inspection confirmed the complete action and filter order, accessible controls, preserved settings and a subsequent update check reporting that 0.3.13 is current.

The direct package is locally ad-hoc signed for this Mac. Developer ID signing and notarization, or Mac App Store distribution signing, remain separate release trust boundaries.

## Artifact identities

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `full-run/report.json` | 25,014 | `766d3a88db30a63b4167d460c2a0dd08af6e20fcd39238ec3a5dc4a12b80f23a` |
| `build-receipt-v0.3.13.json` | 9,147 | `d43198d3380a99a411b4598cc8be6753323625d96d7cabb616f7a0cd7bb92c87` |
| DaBin ARM64 executable | 5,794,496 | `a85a557812a41c7783bfe411c1a25f1ade6088de9969d0f09f96b5a307455314` |
| `DaBin-0.3.13-Update.zip` | 3,363,483 | `56f3474526ae6509971f0dec5357de665a719282a88bf1b75c30b57c12cebbbd` |
| `update-manifest-v0.3.13.json` | 596 | `69634ac3b2f019f953a5d16e26eaf87dd711d491705c389100f465740784f12a` |
| `DaBin-Quick-Guide.pdf` | 299,779 | `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291` |
| `release-ui-renders.json` | 44,934 | `11b8005bdc0932802e46ad6b3245f03832d39d4e3ca35815e20ccad59efa28be` |

## Files

- `full-run/report.json` and adjacent compile/suite logs: complete 30-suite Release run, stable input hashes and individual outcomes.
- `full-run/HeaderInteractionTests.log`, `WeeklyWindowTests.log`, `FilterResizeTests.log` and `WindowTests.log`: compact-row geometry, real native actions and narrow/two-display regressions.
- `release-ui-renders.json`: manifest for 42 release interface renders.
- `renders/`: ten retained light/dark Daily and Weekly views at the compact widths relevant to this change.
- `build-receipt-v0.3.13.json`: compiler, SDK, source inputs, source fingerprint and executable identity.
- `update-manifest-v0.3.13.json`: intended release version, filename, byte count, checksum and GitHub destinations.
- `build-v0.3.13.log` and `package-v0.3.13.log`: optimized build and isolated update-package verification.
- `quick-guide-layout-check.json`: retained one-page A4 guide geometry and extraction evidence for the byte-identical PDF.
- `app-store-preflight-static-v0.3.13.log`: 20 passing source and packaging checks.
- `app-store-preflight-release-v0.3.13.log`: the two remaining external signing and tooling prerequisites.
- `release-publication.json`: unauthenticated GitHub release, latest-manifest and byte-identity verification.
- `live-install-v0.3.13.json`: in-app update, installed-binary, backup, archive, preferences, Desktop link and live header verification.
