# DaBin 0.3.12 release evidence

This directory records the completed functional, visual, build, package, publication, live-update and Store-readiness checks for DaBin 0.3.12 (37).

## Result

- **30/30** registered optimized Release suites passed with **2,704 checks** and no source changes during the final run. The report covers the exact successful run from `20260924T041818917301Z`.
- Feature coverage includes **207 Domain**, **36 day/week export**, **28 export UI**, **138 Weekly state** and **29 native header interaction** checks. It verifies exact day/week scope membership, filter-independent export, copy/download byte identity, active-filter Search, same-day context, popover presentation, keyboard routing, accessibility, cancellation, failure and return to Weekly.
- The unlocked two-display window run passed **214 general window**, **97 Weekly window**, **110 filter resize**, **110 robot/drop** and **138 Daily capture** checks. Focus failures remained test failures.
- Fresh rendering produced **42 release interface views** and **62 broader native views**. The retained feature subset covers Search Day, Search Week, both Weekly action popovers, the 380-point narrow Weekly board and the 428-point two-day board in light and dark appearances. The popovers were rendered at native Retina density.
- The optimized ARM64 direct build is **0.3.12 (37)**. Its 78 receipt inputs total **1,243,682 bytes** and have production-source fingerprint `8bd0134c782ddbc2ee6989fe949e2c153acd71dad2f595fc8d7ddfe9e781ce30`. The full source-and-test run fingerprint is `a33224fbf3a2ccb8e33997de99794a1938a46aa79620c69d1b94a9934e25670e`.
- The ARM64 executable is **5,789,296 bytes**, SHA-256 `39fa0d88bf3a36bffbbe843e73f21e2ed6d398d7c5e312642203334b6f2692a2`.
- The verified update ZIP is **3,362,970 bytes**, SHA-256 `9c4956eb8c9a8273c94b1b6e8e00f48114fc202da28dccc31d5caf62410b0b1b`. Package QA passed isolated fresh installation, replacement, backup, strict clean-copy signature validation, extraction, manifest round trip, exact executable identity and the private document handoff.
- The unchanged one-page A4 PDF guide is **299,779 bytes**, SHA-256 `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291`. It is byte-identical to the prior verified guide.
- Static App Store packaging passed **20/20** checks. Release preflight remains blocked by two owner/environment prerequisites: a 10-character Apple Developer Team ID and a full Xcode installation.
- The public GitHub release is the current latest release. Its release page and all four assets returned HTTP 200 without authentication; each downloaded asset was byte-identical to its local source. The 596-byte update manifest, SHA-256 `cbaa9aabb1c06b89f3d68e627500fc6e83926c828c397800f6b4c2f56791beb2`, matches the ZIP's name, byte count and checksum, and the `/releases/latest/` manifest is byte-identical to the tagged manifest.
- The installed 0.3.11 (36) app downloaded the public ZIP and updated itself to 0.3.12 (37) through its normal Settings flow. The installed executable matches the verified production build, strict deep signature checks pass, all 29 archive files and the preferences file stayed byte-identical, the Desktop link stayed intact, and the prior app was preserved as a verified backup. Live inspection confirmed the Weekly day/week Search and copy/download controls and a subsequent update check reported that 0.3.12 is current.

The direct package is locally ad-hoc signed for this Mac. Developer ID signing and notarization, or Mac App Store distribution signing, remain separate release trust boundaries.

## Artifact identities

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `full-run/report.json` | 28,210 | `7c5cd483dfa3f46341b88d8edf546e0ae5084e6b5b5c076832c0452d19b3bf09` |
| `build-receipt-v0.3.12.json` | 9,147 | `46da96301628887047d085e5ba6e9e11188076a338f1725253bf4ea61e58cf83` |
| DaBin ARM64 executable | 5,789,296 | `39fa0d88bf3a36bffbbe843e73f21e2ed6d398d7c5e312642203334b6f2692a2` |
| `DaBin-0.3.12-Update.zip` | 3,362,970 | `9c4956eb8c9a8273c94b1b6e8e00f48114fc202da28dccc31d5caf62410b0b1b` |
| `update-manifest-v0.3.12.json` | 596 | `cbaa9aabb1c06b89f3d68e627500fc6e83926c828c397800f6b4c2f56791beb2` |
| `DaBin-Quick-Guide.pdf` | 299,779 | `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291` |
| `release-ui-renders.json` | 44,934 | `c188154615df198be544f3fa9eb6eb86a96ba580ad72587e285afb0792134e57` |
| `native-view-renders.json` | 58,174 | `0aca9e8dbdf06da775bd11614a6cdbf7b77b15cfc4add8e457f04bcb96595825` |

## Files

- `full-run/report.json` and adjacent compile/suite logs: complete 30-suite Release run, stable input hashes and individual outcomes.
- `full-run/DayExportTests.log`, `DayExportUITests.log`, `WeeklyStateTests.log` and `HeaderInteractionTests.log`: scoped Search/export behavior and native interaction coverage.
- `full-run/WindowTests.log`, `WeeklyWindowTests.log`, `FilterResizeTests.log`, `RobotDropTests.log` and `DailyCaptureTests.log`: unlocked two-display window and input regression coverage.
- `release-ui-renders.json`: manifest for 42 release interface renders.
- `native-view-renders.json`: manifest for 62 broader native interface renders.
- `renders/`: the light/dark Weekly Search and export popovers, scoped Search results, narrow Weekly board and representative two-day Weekly board.
- `build-receipt-v0.3.12.json`: compiler, SDK, source inputs, source fingerprint and executable identity.
- `update-manifest-v0.3.12.json`: intended release version, filename, byte count, checksum and GitHub destinations.
- `build-v0.3.12.log` and `package-v0.3.12.log`: optimized build and isolated update-package verification.
- `quick-guide-layout-check.json`: retained one-page A4 guide geometry and extraction evidence for the byte-identical PDF.
- `app-store-preflight-static-v0.3.12.log`: 20 passing source and packaging checks.
- `app-store-preflight-release-v0.3.12.log`: the two remaining external signing and tooling prerequisites.
- `release-publication.json`: unauthenticated GitHub release, latest-manifest and byte-identity verification.
- `live-install-v0.3.12.json`: in-app update, installed-binary, backup, archive, preferences, Desktop link and live feature verification.
