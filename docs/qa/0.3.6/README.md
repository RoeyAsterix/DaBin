# DaBin 0.3.6 release evidence

This directory records the functional, visual, build, package and Store-readiness checks for DaBin 0.3.6 (31).

## Result

- **26/26** registered Release suites passed with **2,038 checks** and no source changes during the final run.
- Capture-action, filter-resize, Daily, Weekly and window coverage verifies that the added card spacing does not clip controls, disturb filter transitions, lose offscreen-window recovery, or change capture behavior.
- **34** production interface renders passed. Original-resolution review covered framed caption cards in Daily and Search, a minimized carried task with its complete rounded bottom edge, and expanded hourly actions without a nested duplicate frame, in light and dark appearances.
- Search caption cards were also rendered at native 2× density in both appearances. Their 0.75-point outline remains continuous, evenly inset and legible without overpowering the content.
- The optimized ARM64 Release build is 0.3.6 (31), source fingerprint `783f074b0a0c5ba52378ffc1ad07aeb69228864d05f03b23e77119c5a4084e3c`, executable SHA-256 `054497fee397658bfd54ef76e77440a5320a2c05a426ce725dc890a42a4db2e6`.
- The update ZIP is 3,197,313 bytes, SHA-256 `1f6f5c49bc6dd6c3466c8d94debc07da776297edcf45c9257fcc8b12f41e5b80`. Package QA passed isolated fresh installation, replacement, backup, strict signature validation, extraction and exact executable identity.
- Release [v0.3.6](https://github.com/RoeyAsterix/DaBin/releases/tag/v0.3.6) is public and latest. Unauthenticated checks returned HTTP 200 for the repository, release, four assets and latest manifest; every downloaded asset was byte-identical to its verified local source.
- The installed 0.3.5 app found and installed the public 0.3.6 package through DaBin's own updater. The final app and embedded helper pass strict signature checks, the previous 0.3.5 app is backed up exactly, the Desktop link is unchanged, one ARM64 DaBin process is running, and the follow-up update check reports 0.3.6 as current.
- All 29 archive files and the preferences file remained byte-identical. Live Daily inspection showed the thin rounded caption-card frame with the existing controls and content intact.
- Static App Store packaging passed **20/20**. Submission remains blocked by the owner's Apple Developer Team ID and a full Xcode installation.

The direct package is locally ad-hoc signed for this Mac. Developer ID signing and notarization, or Mac App Store signing, remain the public-distribution trust boundary.

## Files

- `full-run/report.json` and adjacent logs: complete registered-suite run.
- `release-ui-renders.json`: 34 production board renders.
- `renders/`: selected original-resolution Daily, Search, minimized-task and expanded-hour samples.
- `build-receipt-v0.3.6.json`: compiler, SDK, source inputs and executable identity.
- `update-manifest-v0.3.6.json`: exact update asset identity.
- `release-publication.json`: public release metadata and unauthenticated byte-identity checks.
- `live-install-v0.3.6.json`: in-app replacement, backup, archive, preferences, shortcut and runtime verification.
- `app-store-preflight-static-v0.3.6.log`: 20 passing source packaging checks.
- `app-store-preflight-release-v0.3.6.log`: the two external signing/tooling prerequisites.
