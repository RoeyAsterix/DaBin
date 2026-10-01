# DaBin notarized distribution verification — 1 October 2026

## Apple review

Apple accepted submission `9f13f408-52bf-4386-a8c9-3fdb1ae72250` for 0.4.6 (61). That obsolete candidate was withheld from public release: the final replacement test rejected a backup confirmation spelled `/tmp` when its expected directory used `/private/tmp`. These names identify the same directory on this Mac. No unverified package was published.

## Packaging correction

The replacement gate now parses exactly one absolute backup confirmation and compares filesystem identity with the one discovered backup. Missing paths, different backups, symlinks, duplicated confirmations, and prefix-only matches remain rejected. The following exact byte manifests, strict signatures, notarization ticket, Gatekeeper and distribution-policy checks remain required.

The actual previously shipped 0.3.18 updater reproduced the spelling change in an isolated destination. Replacement succeeded and preserved the previous app's exact bytes. Thirty distribution tests pass, including five new path-confirmation regressions. The real installed application and capture archive were not used for this test.

## Latest candidate

The reviewed 0.4.8 (63) app passed all 60 registered Release suites and its recorded input hashes matched current source at review. Its subsequent local installation was handled separately. New source edits are underway in another chat; the public candidate must be frozen after those edits finish, assigned a higher build, rebuilt and notarized before release.

## Completion gates

Final public downloads remain pending. Required gates are Developer ID runtime signing with a trusted timestamp, Apple acceptance, stapling, strict signature checks, Gatekeeper, macOS distribution policy, exact ZIP round trips, fresh installation, replacement and rollback checks, quarantined downloads, actual 0.3.18 helper migration, GitHub validation, and anonymous download hash comparison. The heartbeat continues every 30 minutes and must pause only when verified downloads are ready.

Developer ID distribution does not mean App Store or TestFlight approval. Isolated updater verification does not exercise migration of a real user archive at first launch.
