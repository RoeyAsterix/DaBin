# DaBin 0.3.4 release evidence

This directory records the final source, functional, visual, package, guide and Store-readiness checks for DaBin 0.3.4 (29).

## Result

- **23/23** registered Release suites passed with **1,932 checks**.
- Updater coverage includes **29 service checks** and **12 configuration checks**, including hostile handoff rejection and one-use consumption.
- Weekly coverage includes **103 state checks**, **78 live window checks**, **110 filter-resize checks** and **214 general window checks across two attached displays**.
- **28** production board renders, **10** direct native robot renders and **8** empty Daily/Weekly renders passed in light and dark appearances.
- The package exercised isolated fresh installation, replacement, backup, signature validation, exact executable identity and the extracted helper's LaunchServices document handoff.
- The ARM64 Release build is 0.3.4 (29), source fingerprint `52798f6254f2b08f47049508e1a924848adf474f0e29af5c01be74ab30b80152`, executable SHA-256 `fbe81f1c063795112596e43a4ddcb7d187d51903a8d87d3177f15c2ddd66ea99`.
- The update ZIP is 2,984,144 bytes, SHA-256 `6945e85bc95709771b3077bbadbab2af9f2d16a43aa4a8d25ab9ebf66192fa40`.
- Public release, asset and latest-manifest checks returned HTTP 200 without authentication; all four release assets matched the local verified bytes.
- A live 0.3.3 → 0.3.4 in-app update passed download, document delivery, confirmation, backup, replacement, reopen and current-version checks. Daily/Weekly interaction passed in the installed app, all 29 archive files remained byte-identical, and preferences plus the Desktop shortcut were preserved.
- Static App Store packaging passed **20/20**. Submission remains blocked by the owner's Apple Developer Team ID and a full Xcode installation.

The release package is locally ad-hoc signed for this Mac. Developer ID signing and notarization, or Mac App Store signing, remain the public-distribution trust boundary.

## Files

- `full-run/report.json` and adjacent logs: complete registered-suite run.
- `release-ui-renders.json`: 28 production board views plus native robot artifacts.
- `weekly-entry-renders.json`: eight empty Daily/Weekly views at wide and narrow sizes.
- Selected PNGs: original-resolution Daily and narrow Weekly inspection samples.
- `build-receipt-v0.3.4.json`: compiler, SDK, source inputs and executable identity.
- `update-manifest-v0.3.4.json`: exact public update asset identity.
- `release-publication.json`: public/latest release identity and unauthenticated byte checks.
- `live-install-v0.3.4.json`: installed app, helper, backup, archive, preferences, shortcut and live UI verification.
- `quick-guide-layout-check.json`: one-page A4 bounds and extraction result for the unchanged approved guide.
- `app-store-preflight-static-v0.3.4.log`: 20 passing source packaging checks.
- `app-store-preflight-release-v0.3.4.log`: the two external signing/tooling prerequisites.
