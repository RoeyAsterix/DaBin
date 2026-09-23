# DaBin 0.3.7 release evidence

This directory records the functional, visual, build, package and Store-readiness checks for DaBin 0.3.7 (32).

## Result

- **26/26** registered Release suites passed with **2,038 checks** and no source changes during the final run.
- Application lifecycle, update configuration, Daily, Weekly, filter-resize and window coverage confirm the broader behavior remains stable and the new icon does not alter header layout or panel behavior. The installed-app menu interaction is checked after publication.
- **34** production interface renders passed. Original-resolution review covered the compact Daily header at native 2× density and the 900-point Weekly header in light and dark appearances.
- The settings wheel uses the outline `gearshape` SF Symbol at 13 points with the same 30 × 30-point target and muted colour as adjacent header controls. Its help and accessibility label are **Settings and options**.
- The optimized ARM64 Release build is 0.3.7 (32), source fingerprint `a2fde0f178bfc50ebc7fa2c03788908b437225dadd8f0c0c3cbb5eec3ac5990a`, executable SHA-256 `e02c499b89cfb5b85e720954843e366739e8eb1616362f2bffaaf7bd3ac499db`.
- The update ZIP is 3,198,381 bytes, SHA-256 `1a4154cabbc8f8fc9acba9e68a816ef79693f973d9fc21e424e7db2088f5b40a`. Package QA passed isolated fresh installation, replacement, backup, strict signature validation, extraction and exact executable identity.
- Release [v0.3.7](https://github.com/RoeyAsterix/DaBin/releases/tag/v0.3.7) is public and latest. Unauthenticated checks returned HTTP 200 for the repository, release, four assets and latest manifest; every downloaded asset was byte-identical to its verified local source.
- The installed 0.3.6 app found and installed the public 0.3.7 package through DaBin's own updater. The final app and embedded helper pass strict signature checks, the previous 0.3.6 app is backed up exactly, the Desktop link is unchanged, one ARM64 DaBin process is running, and the follow-up update check reports 0.3.7 as current.
- In the installed app, the wheel was visible and aligned, exposed the accessibility label **Settings and options**, opened its menu, and successfully opened Settings. All 29 archive files and the preferences file remained byte-identical.
- Static App Store packaging passed **20/20**. Submission remains blocked by the owner's Apple Developer Team ID and a full Xcode installation.

The direct package is locally ad-hoc signed for this Mac. Developer ID signing and notarization, or Mac App Store signing, remain the public-distribution trust boundary.

## Files

- `full-run/report.json` and adjacent logs: complete registered-suite run.
- `release-ui-renders.json`: 34 production board renders.
- `renders/`: selected native 2× Daily and compact Weekly samples in light and dark appearances.
- `build-receipt-v0.3.7.json`: compiler, SDK, source inputs and executable identity.
- `update-manifest-v0.3.7.json`: exact update asset identity.
- `release-publication.json`: public release metadata and unauthenticated byte-identity checks.
- `live-install-v0.3.7.json`: in-app replacement, wheel/menu interaction, backup, archive, preferences, shortcut and runtime verification.
- `app-store-preflight-static-v0.3.7.log`: 20 passing source packaging checks.
- `app-store-preflight-release-v0.3.7.log`: the two external signing/tooling prerequisites.
