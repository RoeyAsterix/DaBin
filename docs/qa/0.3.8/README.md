# DaBin 0.3.8 release evidence

This directory records the functional, visual, build, package, publication, live-installation and Store-readiness checks completed for DaBin 0.3.8 (33).

## Result

- **29/29** registered Release suites passed with **2,102 checks** and no source changes during the final run.
- The focused Day Export coverage passed **24 formatter/date-selection checks**, **22 popover/controller checks** and **18 real-window header-interaction checks**. It covers chronological complete-day output independent of active filters, today's current-time cutoff, past dates, text and image placeholders, exact UTF-8 copy/save equivalence, empty/success/cancellation/failure states, keyboard shortcuts, Escape dismissal, native placement beneath the icon and the accessible action contract. Outside-click dismissal is reserved for installed-app verification because the headless harness does not run AppKit's normal click-away event loop.
- General regression coverage passed **214 window checks across two displays**, **78 Weekly window checks**, **110 filter-resize checks**, **110 robot/drop checks** and **138 Daily-capture checks**.
- **34** production interface renders passed. Original-resolution review covered 380-point Daily and 900-point Weekly layouts in light and dark appearances, with native 2× Daily samples. The compact three-row header keeps navigation, Daily/Weekly, all five primary actions, filters and the neutral close button visible and aligned without the former dead area.
- The optimized ARM64 Release build is 0.3.8 (33), source fingerprint `b286601bf9262b09651661655e03b455a28832cd2996dc25827160af535f648c`, executable SHA-256 `49afd0e82795639d967511bdd74296262e6a169b05ebaf6e6270eb234b10516d`.
- The update ZIP is **3,270,792 bytes**, SHA-256 `d4700284846007251d75f033d4dcfb578bf221c85fb90282a497be9ae150ffef`. Package QA passed isolated fresh installation, replacement, backup, strict clean-copy signature validation, extraction, manifest round trip, exact executable identity and document handoff.
- The one-page A4 PDF guide is **299,779 bytes**, SHA-256 `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291`. The tracked and output copies are byte-identical and passed extraction, geometry, boundary and visual checks.
- Static App Store packaging passed **20/20**. Release preflight remains blocked by two external prerequisites: the owner's Apple Developer Team ID and a full Xcode installation.
- Release [v0.3.8](https://github.com/RoeyAsterix/DaBin/releases/tag/v0.3.8) is public and latest. Unauthenticated checks returned HTTP 200 for the repository, release, four assets and latest manifest, and every downloaded asset was byte-identical to its verified local source.
- The installed 0.3.7 app found and installed the public 0.3.8 package through DaBin's native updater. The installed app and helper pass strict signature checks, the exact prior app is backed up, one ARM64 process is running, the Desktop link is unchanged and the follow-up update check reports 0.3.8 as current.
- All 29 archive files and the preferences file remained byte-identical. Live UI inspection confirmed the three-row header, required primary-action order and accessible labels, disabled **Nothing to export** state, physical click-away dismissal, the Settings gear menu and Settings navigation.

The direct package is locally ad-hoc signed for this Mac. Developer ID signing and notarization, or Mac App Store signing, remain the public-distribution trust boundary.

## Files

- `full-run/report.json` and adjacent compile/suite logs: complete 29-suite optimized Release run and stable input hashes.
- `full-run/DayExportTests.log`: 24 export formatting, ordering, selected-date and filter-independence checks.
- `full-run/DayExportUITests.log`: 22 popover state, clipboard/save equivalence, empty and feedback checks.
- `full-run/HeaderInteractionTests.log`: 18 live compact-header, export-popover, keyboard and existing-action interaction checks.
- `release-ui-renders.json`: manifest for 34 production interface renders.
- `renders/`: selected Daily native 2× and compact Daily/Weekly samples in light and dark appearances.
- `build-receipt-v0.3.8.json`: compiler, SDK, source inputs, source fingerprint and executable identity.
- `update-manifest-v0.3.8.json`: exact release version, filename, byte count, checksum and intended release URLs.
- `release-publication.json`: public release metadata and unauthenticated byte-identity checks for all assets and the latest manifest.
- `live-install-v0.3.8.json`: in-app update, backup, strict signatures, archive/preferences preservation, Desktop link, runtime and live UI checks.
- `quick-guide-layout-check.json`: one-page A4 guide geometry, extraction and copy-identity evidence.
- `app-store-preflight-static-v0.3.8.log`: 20 passing static source and packaging checks.
- `app-store-preflight-release-v0.3.8.log`: the two external signing and tooling prerequisites.
