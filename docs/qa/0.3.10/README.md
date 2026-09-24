# DaBin 0.3.10 release evidence

This directory records the functional, visual, build, package and Store-readiness checks completed for DaBin 0.3.10 (35).

## Result

- **29/29** registered Release suites passed with **2,059 checks** and no source changes during the final run.
- Text-filter coverage checks its exact position before Links, text-only kind membership, contextual Search behavior, automatic hourly summaries, all seven Weekly dates, empty and sparse weeks, native hit targets, and the 380-point header.
- **34** release interface renders and **62** broader native interface renders passed. Original-resolution review covered the six centered filter icons in light and dark Daily at 380 points and Retina density, the selected Text state, the 428-point two-day Weekly view, and a 380-point constrained Weekly view.
- The optimized ARM64 Release build is 0.3.10 (35), source fingerprint `9d3a0f2ab06e2252760581e951bcf5fb8a0c35d15f7d9e9421a4c543047b2f8e`, executable SHA-256 `d2513dcb124068bf095d77118b9e6f3179c2ec9a7b3af04d32de0dad818c390b`.
- The update ZIP is **3,279,679 bytes**, SHA-256 `e1fa9fb3d741f5b705926cecef3374bab66f1ed65cb443ba033a178f8043b2eb`. Package QA passed isolated fresh installation, replacement, backup, strict clean-copy signature validation, extraction, manifest round trip, exact executable identity and document handoff.
- The unchanged one-page A4 PDF guide is **299,779 bytes**, SHA-256 `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291`; its retained geometry and extraction check remains one page with no boundary failure.
- Static App Store packaging passed **20/20** checks. Release preflight remains blocked by two external prerequisites: the owner's Apple Developer Team ID and a full Xcode installation.
- Release [v0.3.10](https://github.com/RoeyAsterix/DaBin/releases/tag/v0.3.10) is public and latest. Unauthenticated checks returned HTTP 200 for the release and all four assets; every downloaded asset was byte-identical to its verified local source, including the latest manifest URL.
- The installed 0.3.9 app found, downloaded and installed the public 0.3.10 package through DaBin's own updater. The installed app, embedded helper and exact 0.3.9 backup pass strict signature checks. All **29 archive files** and the preferences file remain byte-identical, the Desktop link is unchanged, and one ARM64 process is running.
- Live UI inspection verified the order **All, Copy/paste text, Links, Files, Media, Tasks** and accessibility identifier `filter-text`. On 23 September, Text showed one plain-text capture while All showed all four records. A subsequent update check reports 0.3.10 as current, and DaBin was left on today's Daily view with All selected.

The direct package is locally ad-hoc signed for this Mac. Developer ID signing and notarization, or Mac App Store signing, remain the public-distribution trust boundary.

## Files

- `full-run/report.json` and adjacent compile/suite logs: complete 29-suite optimized Release run and stable input hashes.
- `full-run/DomainTests.log`: text-only classification and contextual Search coverage.
- `full-run/HourlyGroupingTests.log`: copied-text filtering inside qualifying automatic hourly summaries.
- `full-run/WeeklyStateTests.log` and `WeeklyWindowTests.log`: Text-filter behavior across full, sparse and empty weeks.
- `full-run/HeaderInteractionTests.log`: six-button ordering and hit targets in the compact header.
- `release-ui-renders.json`: manifest for 34 release interface renders.
- `native-view-renders.json`: manifest for 62 broader native interface renders, including selected Text views.
- `renders/`: selected Daily and Weekly samples in light and dark appearances.
- `build-receipt-v0.3.10.json`: compiler, SDK, source inputs, source fingerprint and executable identity.
- `update-manifest-v0.3.10.json`: exact release version, filename, byte count, checksum and intended release URLs.
- `quick-guide-layout-check.json`: retained one-page A4 guide geometry and text extraction evidence for the byte-identical PDF.
- `app-store-preflight-static-v0.3.10.log`: 20 passing static source and packaging checks.
- `app-store-preflight-release-v0.3.10.log`: the two external signing and tooling prerequisites.
- `release-publication.json`: public release metadata and unauthenticated byte-identity checks for every asset and the latest manifest.
- `live-install-v0.3.10.json`: in-app update, backup, signatures, archive/preferences preservation, Desktop link, runtime and live Text-filter checks.
