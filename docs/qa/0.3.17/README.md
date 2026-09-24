# DaBin 0.3.17 release evidence

This directory records the functional, visual, build, package, and Store-readiness checks completed for DaBin 0.3.17 (42) before publication.

## Result

- The exact source passed **30/30 registered optimized Release suites** with no source changes during the run.
- Focused lifecycle coverage passed **35 application-lifecycle checks**. Auto Capture coverage passed **45 checks**, including immediate monitor shutdown and rejection of events after termination begins.
- The release renderer produced **50 production UI renders**. Settings was checked in light and dark appearance, normal and Retina scale, including its scrolled bottom state. **Quit DaBin** is visible, unclipped, and uses the existing compact Settings layout.
- The static App Store source/package preflight passed all **20 checks**.
- The optimized direct build is **0.3.17 (42)** for ARM64 with source fingerprint `5f2a3ac34abf5ad4e99f71c181daec3e43b511249dd22f13ca4201b6d4f4446d` and executable SHA-256 `dc8b6c54455729dc4b25db74166f110703f304296fa0bc4786cfa7c8d5a389f9`.
- The update package passed fresh-install, replacement, backup, embedded-helper handoff, signature, extraction, source-freshness, and executable-hash checks.
- The standalone package passed ARM64, dependency, resource, signature, source-freshness, per-file-manifest, and ZIP round-trip checks.
- Both packages contain the exact same DaBin executable and identify `~/Applications/DaBin.app` as the installation target.

## Distribution boundary

The build and both helpers are locally ad-hoc signed. Strict code-signature verification passes, but there is no Developer ID identity on this Mac. Full App Store release preflight remains blocked by the missing Apple Developer Team ID and full Xcode. A frictionless install on other Macs additionally requires Developer ID signing, hardened runtime, notarization, and stapling.

## Key artifacts

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `full-run/report.json` | 27,967 | `d06c0ae10d97875627e33b8120aeb29dcec32b909a0f6ed978b72ce58ac6aac0` |
| `release-ui-renders.json` | 50,184 | `371460b5e8b6e7c22701665b6b67a2bc0e6229397576bc822d962332840617fb` |
| `build-receipt-v0.3.17.json` | 9,147 | `0562cc8f79f0388d1e875c94f7a2a8566f5577a591820c901e0a6b53d8be9a7d` |
| `update-manifest-v0.3.17.json` | 596 | `c95320b7b0219a75b21951f5edbc4b428264ba393e3e63bba48346a3b50cbad4` |
| `package-comparison-v0.3.17.json` | 1,674 | `bf0664d608d451f7085deb5cc19730b65ab67c8a4223d9e8e83dbfea28730d98` |
| `DaBin-0.3.17-Update.zip` | 3,395,784 | `158324bf1f3cf798d5245c659b147352312cd00402df64630c37793b0e880e9e` |
| `DaBin-0.3.17-AppleSilicon.zip` | 2,816,983 | `c690cdfab583698f6642759b2e3b093815eb274d1df4952a3d1bdaa847f78457` |

The two ZIP files remain outside Git and are published as immutable GitHub Release assets. Public-byte, live update, direct-install launch, and complete-quit evidence is added after publication.

## Evidence map

- `full-run/`: optimized suite report, compile logs, and test logs.
- `release-ui-renders.json`: complete release-render inventory and hashes.
- `renders/`: the six Settings renders most relevant to this change.
- `build-receipt-v0.3.17.json`: exact build inputs, compiler/SDK, source fingerprint, and executable hash.
- `package-update-v0.3.17.log`: update/installer package QA.
- `package-standalone-v0.3.17.log`: manual package QA.
- `package-comparison-v0.3.17.json`: cross-package application identity.
- `app-store-preflight-static-v0.3.17.log`: all 20 offline source/package checks passed.
- `app-store-preflight-release-v0.3.17.log`: the two external App Store prerequisites.
