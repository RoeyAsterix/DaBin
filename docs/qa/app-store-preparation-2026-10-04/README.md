# DaBin App Store preparation — 4 October 2026

Subsequent action: the user requested a local update, and the direct-channel 0.4.31 (86) app is now installed. See [local installation](../local-update-0.4.31-2026-10-04/README.md). The original preparation evidence below records the earlier installed 0.4.30 state and does not imply Store signing or submission.

**DaBin 0.4.31 (86): local preparation and verification completed; submission remains blocked.** This work does not establish Apple approval. Nothing was uploaded, submitted or publicly released. The installed personal app is still 0.4.30 (85), with the same executable hash as before this work.

## What changed

- Active Auto Capture now has a persistent red menu-bar recording symbol, with separate Ready, Paused, Off and attention states. It remains indicated with the board closed and tooltips disabled, and when clipboard monitoring continues without screenshot-folder access.
- The privacy policy describes the persistent indicator and removes an unsupported claim that update requests explicitly transmit the installed version. Required-reason API declarations match the audited app-owned use; no tracking/analytics or new SDK was added.
- The QA runner has an explicit Store channel, isolated compilation caches and reports, and Store updater tests that verify disabled actions and zero HTTP requests.
- Current English listing copy, reviewer instructions, fictional screenshot drafts, local export options and an Apple requirements audit are prepared. Owner/private contact fields remain unfilled rather than invented.

## Verified results

| Check | Result and scope |
|---|---|
| Store-channel native Release QA | All **96 registered suites have passing results**. The full run passed 95/96; UpdateConfigurationTests lacked sibling repository workflow/docs fixtures. After copying those fixtures, that same suite passed 41 checks. Production code did not change between runs. Both reports and the original failure remain preserved. |
| Offline Python regression tests | **90 passed**: 58 discovery tests plus 32 preflight tests. The first isolated attempt omitted metadata JSON and produced 15 fixture errors; copying the current metadata resolved them without code changes. |
| Store Release build | **Xcode 27 / SDK 27 / Swift 6.4**, warnings as errors, ARM64, deployment target 14.0. Built on macOS 26.6.2. |
| Unsigned packaging preflight | **51 passed**. Store stub present; direct downloader/helper absent; bundled policy/manifest, category, privacy URLs, architecture, version and quarantine checks pass. This is an unsigned app, not a distributable package. |
| Enforced App Sandbox smoke | **31 assertions passed** across two ad-hoc test processes: own-container save/import, relaunch/reopen/search/day/ZIP export, original-byte preservation, and actual EPERM for ungranted fictional file read/write. The fixture intentionally has a unique test ID and stricter entitlements. It is not the distribution app. |
| Store app GUI smoke | A separate ad-hoc copy of the unsigned app, using production sandbox entitlements and a fresh test ID, opened an empty archive with clipboard/screenshots/previews off. Settings showed Store-managed updates. A fictional note saved and typed search found it. Cmd-Q exited successfully. One fictional note remains only in the test container. |
| Screenshot drafts | Three current native **1440 × 900 opaque RGB PNGs**, fictional data, Store-mode module, source hashes verified. All three inspected at original resolution and passed visual review. Final distribution-app comparison remains pending. |
| Public links | Configured GitHub policy and Issues links returned unauthenticated HTTP 200. The published policy is still the 2 October text; the reviewed 4 October changes need publication. A reachable Issues page does not establish adequate owner contact details. |
| Source / installed app integrity | Frozen build inputs and unsigned executable still match the receipt. The installed personal executable remains unchanged. |

[Native robot motion QA preview](DaBin__MOTION_QA__PREVIEW.mp4) is an automatically rendered test clip, not an App Store promotional preview.

Full evidence: [verification.json](verification.json), [full native run](native-full-run.json), [targeted rerun](native-fixture-rerun.json), [offline results](offline-tests.json), [Store build receipt](unsigned-store-candidate.json), [packaging log](unsigned-packaging-preflight.log), [sandbox receipt](sandbox/runtime-pass.json), [live GUI checks](store-gui-fixture.json), [public URL check](public-url-check.json), [installed app preservation](installed-app-preserved.json).

## Candidate and source scope

The candidate is frozen at `native/build/store-preparation-20261004/native`, based on the verified installed 0.4.30 source plus the owned Store preparation changes. Ten separate tutorial edits remain preserved in the shared checkout and are excluded; see [excluded-independent-edits.json](excluded-independent-edits.json). Building directly from shared source produces a different candidate and requires its own verification.

Unsigned app: `native/build/store-preparation-20261004/native/build/store-unsigned-0.4.31-86/derived-data/Build/Products/Release/DaBin.app`.

- Store source fingerprint: `cda5504ffbd21b7d090c142f54cf635f8d139adedd61be14a3ab85e045ce62c5`
- Unsigned executable SHA-256: `8bd6e628b0efffb2bfd339f84723234aea2e1a03b6b11fb0ceb4eb82895afc3b`
- Current [listing JSON](../../app-store/metadata-en-US.json), [screenshots](../../app-store/screenshots/0.4.31-86/README.md), [Apple audit](../../app-store/APPLE_REQUIREMENTS_2026-10-04.md).

## Concrete remaining gates

1. **Signing:** the existing Apple Development and Apple Distribution identities and matching Store profile are present, but no Mac Installer Distribution identity was found. Archive compilation reached signing. macOS requested protected Keychain authorization; the UI tool explicitly disallows SecurityAgent. No credentials were retrieved or entered. After independent work finished without a user response, only this task's verified waiting codesign process was cancelled, and the archive exited 65. There is no valid archive or exported Store package. Retry with user interaction and a fresh archive destination once signing assets are ready.
2. **Owner and Connect:** legal/copyright holder, maintained support/contact page, public support email, private review contact, pricing, territories, release method and EU trader status remain unresolved. Confirm the app record, build-number availability, current agreements, age rating, privacy labels, encryption and rights declarations in Connect. Private review contact information should not be committed to a public repository.
3. **Public policy:** publish the corrected 4 October policy at the configured URL and verify text parity. Source/publication is separate from uploading an app.
4. **Final acceptance:** run [MANUAL_ACCEPTANCE.md](MANUAL_ACCEPTANCE.md) on the final signed app, including fresh install/upgrade, native file grants and bookmark persistence, real capture/notification consent, physical external drops, supported OS/display matrix, VoiceOver, energy and optional previews over IPv6-only networking. The host runs macOS 26.6.2; macOS 14 and current shipping macOS 27 acceptance were not performed here. Source-module tests and the ad-hoc sandbox fixture do not replace this.
5. **Submission:** compare screenshots against that exact final app, export and validate using Xcode, then obtain authorization for upload/submission. Apple processing and review remain outstanding.

The [strict metadata validator](metadata-strict.json) intentionally fails while these gates remain unresolved. Passing the 13 local copy checks alone does not report readiness.

## Retained failures and tooling limits

- The first archive attempt stopped at preflight because the frozen baseline's generated Xcode project was stale. Regenerated it from the unchanged source inventory; the next attempt compiled and reached the protected signing prompt. Both logs/receipts remain.
- The first sandbox fixture launch inside the tool's outer sandbox aborted before Swift main. The same harness passed outside that outer sandbox while its own App Sandbox remained enforced; both receipts are retained.
- The first full native run's missing-workflow fixture failure and the initial Python missing-metadata errors are documented above; neither is hidden by the successful reruns.
- The desktop tool stalled for 6407 seconds while launching the isolated GUI app despite its requested 15 second timeout. Subsequent native navigation/save/search/quit calls succeeded promptly. This is recorded as a tooling limitation, not an app launch-performance measurement.
- No physical cross-app/browser drop was verified. The preceding [drag verification](../outgoing-drag-verification-2026-10-04/README.md) proves native payloads and cross-process representations, and explicitly preserves the physical-drop gap.

## Reproduce the local checks

From the frozen candidate's `native` directory, in an unlocked macOS GUI session:

```sh
python3 scripts/run_qa.py --distribution app-store --configuration Release
python3 -m unittest discover -s Tests -p 'test_*.py'
python3 scripts/test_app_store_preflight.py
python3 scripts/app_store_preflight.py --unsigned-app build/store-unsigned-0.4.31-86/derived-data/Build/Products/Release/DaBin.app
```

The separate sandbox harness is `Tests/store_sandbox_smoke.py`; supply the verified Store module directory and `--run`. It creates only a unique test app/container and synthetic denial fixture. The exporter in the screenshot directory verifies the frozen Store module before rendering. Do not run native-window exporters concurrently with timing-sensitive UI suites.
