# DaBin 0.3.18 release evidence

This directory records functional, visual, build, package, stable-download, publication, and installed-update checks for DaBin 0.3.18 (43).

## Result

- The exact source passed **30/30 registered optimized Release suites** with no source changes during the run.
- Software update coverage passed **34 checks**. Update configuration and stable-release staging passed **21 checks**.
- The production renderer completed **50 views**. The first Settings screen was inspected in light and dark appearance at the shipping 380 × 430-point size; the complete **Get updates** card is visible without scrolling or clipping. The 260-point stress render remains below the supported layout width.
- The static App Store source/package preflight passed all **20 checks**. Full Store release preflight remains blocked by the missing Apple Developer Team ID and full Xcode.
- The optimized direct build is **0.3.18 (43)** for ARM64 with source fingerprint `9fc4068359db0ca42297ae4e197aaa69f0268b370cd7c1030fe2d54b144c613d` and executable SHA-256 `096fa1475294e8e782836a72fe8f5e7b3db1e3d563566c7ac72f9c98c86494b1`.
- The update package passed isolated fresh-install, replacement, backup, helper-handoff, signature, extraction, source-freshness, and executable-hash checks.
- The standalone package passed ARM64, dependency, resource, signature, source-freshness, per-file-manifest, and ZIP round-trip checks.
- Both packages contain the exact same DaBin executable.
- The stable installer and standalone aliases are byte-identical to their versioned packages. Release staging contains all seven required assets.
- GitHub published v0.3.18 as the latest normal release. All seven bare `/releases/latest/download/` URLs returned HTTP 200 anonymously and matched the verified local assets byte for byte. The stable-alias workflow completed successfully.
- The installed 0.3.17 app discovered, downloaded, verified, backed up, and installed 0.3.18 through its own Settings flow. All 33 archive files, five originals, preferences, and the Desktop app link remained unchanged.
- In the installed build, **Get updates** is the first visible Settings section without scrolling, exposes its accessible check control and permanent release link, and reports **You’re up to date with DaBin 0.3.18.**

## Package identity

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `DaBin-0.3.18-Update.zip` | 3,414,052 | `2c5444c20fa44b87b77eaa90a225ee90d08186f9ac6bf846a08e0fa02c6ee406` |
| `DaBin-Latest-Update.zip` | 3,414,052 | `2c5444c20fa44b87b77eaa90a225ee90d08186f9ac6bf846a08e0fa02c6ee406` |
| `DaBin-0.3.18-AppleSilicon.zip` | 2,835,253 | `2dd604b8a4eb7f146c75f0efd223ecd3e95085a7a64b3fedeb89925fa2870201` |
| `DaBin-Latest-AppleSilicon.zip` | 2,835,253 | `2dd604b8a4eb7f146c75f0efd223ecd3e95085a7a64b3fedeb89925fa2870201` |
| `DaBin-update.json` | 596 | `9cf5c705bfa388b5bd2e65344770013af8acd248d0d0b77c47c757060e169fdb` |

The ZIP files remain outside Git and are published as immutable GitHub Release assets.

## Evidence map

- `full-run/`: complete optimized suite report, compile logs, and test logs.
- `release-ui-renders.json`: release render inventory and hashes.
- `renders/`: Settings renders relevant to the first-screen update control.
- `build-receipt-v0.3.18.json`: exact build inputs, compiler/SDK, source fingerprint, and executable hash.
- `package-update-v0.3.18.log`: update/installer package QA.
- `package-standalone-v0.3.18.log`: manual package QA.
- `package-comparison-v0.3.18.json`: executable identity across both package formats.
- `stable-aliases-v0.3.18.json`: all seven staged assets and stable-alias byte identity.
- `update-manifest-v0.3.18.json`: public updater metadata and exact versioned package checksum.
- `app-store-preflight-static-v0.3.18.log`: all 20 source/package checks passed.
- `app-store-preflight-release-v0.3.18.log`: the two external Store submission prerequisites.
- `release-publication.json`: latest-release metadata, workflow result, all seven permanent URLs, and anonymous byte verification.
- `live-update-v0.3.18.json`: installed 0.3.17 → 0.3.18 self-update, backup, archive, preferences, Desktop link, running process, and first-screen Settings result.

## Distribution boundary

The direct build and helper are locally ad-hoc signed for the owner's Mac. Full Store distribution still requires an Apple Developer Team ID, full Xcode, distribution signing, archive validation, App Store Connect submission, and Apple review. Frictionless direct installation on unrelated Macs additionally requires Developer ID signing and notarization.
