# DaBin — Mac App Store readiness

## Current internal TestFlight preparation — 6 October 2026

**0.4.43 (98): locally validated for the next internal TestFlight archive; NOT uploaded.** The current authorization covers an internal tester update, not public App Store review. The last verified internal build is **0.4.31 (86), Testing** in Personal Testing; the last verified local installation is **0.4.42 (97)**. [Current status](../docs/qa/testflight-upgrade-0.4.43-98-2026-10-06/status.json), [historical build 86 status](../docs/qa/testflight-0.4.31-2026-10-04/status.json).

Build 98 hides all robot artwork and project/confirmation/timer signs while Auto Capture is paused. Hover, peeks, queued saves, placement changes and late feedback cannot reveal them; the expanded board stays usable. Timer and unacknowledged alarm state is retained for Resume. It retains the preceding compact toolbar, date picker, search/paste, native drag, selected-item export and security/locality changes. [Release notes](../docs/RELEASE_NOTES_0.4.43.md).

The final campaign passes **11/11 selected native Store suites** against unchanged inputs. The exact historical build-86 production writer → current build-98 reader fixture also passes with fictional capture IDs, Unicode text, task planning, original-file hashes, project/scratchpad state and unfinished drafts, then a current save and two independent reopens. Bundle `com.dabin.mac`, team `8QG4967CSU`, the Core Data model and the local sandbox archive namespace remain unchanged. This supports forward data continuity; it is not an Apple-signed application or actual TestFlight replacement test. **Downgrade to build 86 after a current save is unsupported** because build 86 rejects capture schema 11. [Validation scope](../docs/qa/testflight-upgrade-0.4.43-98-2026-10-06/validation-summary.json), [native receipt](../docs/qa/testflight-upgrade-0.4.43-98-2026-10-06/native-qa-report.json), [synthetic upgrade receipt](../docs/qa/testflight-upgrade-0.4.43-98-2026-10-06/passed-synthetic-upgrade/report.json).

The archive attempt compiled to **CodeSign** and was interrupted while awaiting human authorization to use the protected signing key. No completed signed archive, uploaded build 98, processing completion or internal availability is claimed. Signing/export/upload and an actual same-container TestFlight update remain pending. No public App Store review submission was made. The [human signing handoff](../docs/qa/testflight-upgrade-0.4.43-98-2026-10-06/human-signing-handoff.json) records the exact tested-source continuation.

Build 97's preceding [security/locality audit](../docs/qa/security-locality-2026-10-06/audit-report.json) passes 36 selected Store suites, four direct suites, 96 Python tests, 93 ZIP adversarial checks and an isolated ad-hoc sandbox fixture. It is not a full registered-suite rerun, packet-capture campaign or distribution-signed acceptance. Managed storage permissions, non-following descriptor checks, capture exclusions, preview consent and updater extraction/rollback protections are retained in build 98. Saved data/backups are not separately encrypted; unmarked secrets can still enter opted-in clipboard capture, and other services may sync user-selected exports/backups. The local install kept counts and total archive bytes unchanged, but normal old-app quit wrote Drafts.json; an aggregate-only baseline cannot certify complete post-install byte identity. [Preservation qualification](../docs/qa/security-locality-2026-10-06/archive-preservation-qualification.json).

Public-release gates remain separate: exact signed-build runtime/update acceptance, supported macOS and accessibility review, current policy publication/parity, owner/Connect declarations and review submission. Existing PDF and screenshot assets are historical; **build 98 parity has not been verified**. Historical strict zoom performance and platform limits remain documented rather than treated as resolved by these selected tests.

## Historical Store preparation — 4 October 2026

**0.4.31 (86), Store channel: local preparation verified; NOT ready for public App Store review at this checkpoint.** This historical candidate was frozen from the verified installed 0.4.30 source plus the Store preparation fixes. Ten independent tutorial edits were preserved in the shared checkout and excluded from it. The local/direct application was subsequently updated to 0.4.31 (86); [installation and preserved-data verification](../docs/qa/local-update-0.4.31-2026-10-04/README.md). Build 86 was later uploaded and made available for internal TestFlight testing, as recorded in the status linked above.

That source added persistent red menu-bar Recording status, distinct Ready/Paused/Off states, corrected privacy wording, and explicit Store-channel QA. Its unsigned Xcode 27 Release build passed 51 packaging checks. A separate ad-hoc sandbox fixture passed 31 checks across two processes, including denied ungranted file access; it was not the distribution app. All 96 then-registered native Store suites have passing results (95 in the full run plus one fixture-corrected rerun), 90 offline tests passed, and three screenshots passed visual review. These results are recorded in the [historical evidence](../docs/qa/app-store-preparation-2026-10-04/README.md), not as build 98 full-suite or screenshot acceptance.

At that preparation checkpoint, signing/export, supported-macOS signed-app acceptance, policy publication and owner/Connect declarations were unresolved; the waiting archive attempt was cancelled. Later build 86 distribution supersedes that checkpoint's no-upload status. The [4 October Apple requirements audit](../docs/app-store/APPLE_REQUIREMENTS_2026-10-04.md), [listing/reviewer draft](../docs/app-store/metadata-en-US.json) and [build 86 screenshots](../docs/app-store/screenshots/0.4.31-86/README.md) retain their historical scope. Local passing tests do not guarantee Apple approval.

## Historical TestFlight attempt — 3 October 2026

The target of that historical attempt was **0.4.23 (78), TestFlight beta review only**. The owner authorized that upload/submission, not a public App Store release. It was **not uploaded or submitted in that attempt**: App Store Connect was at sign-in, the Mac was locked, and read-only Keychain inspection found no Mac Installer Distribution identity. That attempt did not complete distribution signing/export or signed Sandbox runtime QA.

Its fresh native run reported **73/77 suites passed, four failed** while the desktop was locked; those failures remain preserved. Do not replace that result with the earlier 77/77 passing receipt. The archive destination traversal guard was hardened with eight new regressions. See the [historical attempt and evidence](../docs/qa/testflight-0.4.23-2026-10-03/README.md) and [beta handoff draft](../docs/app-store/TESTFLIGHT_0.4.23.md). The audit below is historical 0.4.19 preparation, not evidence for build 98.

## Historical Store preparation — 2 October 2026

Audit: **2 October 2026** · source **0.4.19 (74)** · `com.dabin.mac` · Apple Silicon, macOS 14+

**Status: functional regressions and unsigned Store packaging PASS; NOT ready to submit.** Passing local tests does not guarantee Apple approval. This audit covers applicable requirements for the current native, account-free, local-storage app. A change to accounts, payments, networking or content would require a new review.

The installed personal app and public release have not been changed by this preparation. Public downloads remain 0.3.18. The prior [24 September evidence](../docs/qa/app-store-preflight-2026-09-24/README.md) records 0.3.18 (45) and is historical, not current readiness.

The approved source, guide and preparation documents were pushed to `main` in commit `650ecf664bdabce46120eac5b5a6617a575b1689`. The corrected public privacy policy now matches the bundled source byte-for-byte; both configured and raw URLs returned HTTP 200. [Publication verification](../docs/qa/app-store-2026-10-02/publication.json). This does not publish a binary release or upload/submit an app to Apple.

## Historical 2 October local work and evidence

- **73/73 final registered Release suites pass**, with 87,546 reported assertions and unchanged inputs. Many are pixel/animation checks, not independent workflows. The tests use the direct-channel test module; signed Store Sandbox runtime review remains separate. [Final receipt and scope](../docs/qa/app-store-2026-10-02/tests/README.md).
- **39/39 final synthetic-media checks and 77 offline Python tests pass.** The later packaging-only archive-entitlement correction also passes 27 scoped UpdateConfiguration checks; native/resource/test inputs still match the full-run receipt.
- Corrected the privacy manifest for app-owned file timestamp access (`C617.1`), alongside app-owned preferences (`CA92.1`) and animation timing (`35F9.1`).
- Updated the bundled policy for visible project-name and task-title signs, and made the in-app policy date come from the bundled document.
- Clarified that optional website previews apply only to manually saved links. Automatic links remain ineligible.
- Removed automatic provisioning updates from the archive helper; strengthened exact-source, entitlements, profile, certificate, quarantine, privacy-resource and Store/direct-updater checks.
- Added an isolated unsigned Xcode Store-candidate builder and offline metadata validation. Neither claims distribution readiness.
- Refreshed the [listing and reviewer instructions](../docs/app-store/APP_STORE_CONNECT_DRAFT.md) and [machine-readable metadata draft](../docs/app-store/metadata-en-US.json). Owner fields remain explicitly blank.
- The final unsigned Xcode Store Release build passes **51/51 packaging checks**, with current source/resources and no direct updater/helper. It is an unsigned intermediate, not a distribution-signed app or Sandbox runtime pass. [Packaging receipt](../docs/qa/app-store-2026-10-02/packaging/README.md).
- Three current 1440 × 900 RGB native-interface screenshot drafts have been visually inspected with fictional data. They still require comparison or recapture from the exact signed candidate before upload.
- Policy-view QA passes 11 assertions and two light/dark top/date inspections, but both bottom offscreen snapshots clip the heading/Done control and are withheld. This is not an established production defect; signed live policy scrolling remains unverified. [Evidence](../docs/qa/app-store-2026-10-02/privacy/privacy-render-provenance.json).
- Final tests, current screenshot drafts and archive results are recorded in the [2 October evidence](../docs/qa/app-store-2026-10-02/README.md), with raw failures preserved rather than hidden.

## Historical review matrix and remaining release gates

This matrix preserves the 2 October audit's findings and Apple references. Current build 98 evidence and its pending signing/update checks are listed above; historical policy publication, screenshot review and packaging passes do not establish parity or acceptance for newer sources.

| Area | Local finding | Gate before submission |
| --- | --- | --- |
| Completeness and usable functionality — 2.1, 4.2 | Native capture, organization, search, task and reminder workflows have regression coverage; no account or demo login is needed. | Exercise the exact signed sandboxed build from a clean install and update, with no crashes, missing assets or placeholder controls. |
| Mac packaging and public APIs — 2.4.5, 2.5.1 | Minimal Sandbox entitlements; selected-file access and app-scoped bookmarks; Apple frameworks; no private API found by targeted source inspection. Store compilation excludes the direct GitHub downloader and installer. | Validate the final Apple-distribution-signed product, provisioning and installer package in Xcode/App Store Connect. Source inspection and an unsigned compile are not runtime Sandbox evidence. |
| Monitoring consent and indication — 2.5.14, 5.1 | Clipboard and screenshot-folder channels are independently off by default, require explicit opt-in and establish a baseline. Menu bar state and Pause/Off remain available. | Verify first launch, relaunch, Pause/Off/Quit, source exclusions and folder authorization/revocation in the signed candidate. Attribution/exclusions are best effort, not a sensitive-data guarantee. |
| Data minimization and control — 5.1 | Captures and OCR stay local; no account, tracking, analytics, cloud sync or third-party SDK found. Recently Deleted, permanent removal, export and backup exist. | Confirm actual signed-build traffic, retention/removal and owner's current App Privacy answers. No account means account deletion does not currently apply. |
| Website requests | Default-off previews only for manually saved links; automatic links never request previews. The policy describes URL/IP disclosure to chosen sites. | Network-instrument the signed build, including automatically captured links while manual previews are on, and cancellation after disabling. |
| Power/resources and network compatibility — 2.4.2, 2.5.5 | Cache/bounded-work regressions and local media checks pass; default-off network previews do not gate core capture. | Measure signed-build idle/active energy, CPU, memory and disk behavior; exercise IPv6-only and offline preview/capture behavior. These are not established by source assertions or offscreen animation recordings. |
| Privacy policy — 5.1.1 | Updated offline policy is in the source and build resources. After the authorized push, configured and raw policy URLs returned HTTP 200 and the raw policy exactly matched the 2 October source, including robot-sign disclosures. | Publication/parity is resolved for this source. Maintain parity for any future policy change and verify access from the exact signed app. |
| Support, metadata and screenshots — 1.5, 2.3 | Friendly current copy, accurate capture boundaries and Apple Silicon/macOS 14 support. Local validator checks Apple's field limits. Screenshots use fictional fixtures. | Provide a real maintained support page/contact, legal copyright owner, review name/email/phone; compare or recapture screenshots from the exact signed candidate. No personal captures, unlicensed imagery or inaccurate claims. |
| Accessibility and UI | Native keyboard/accessibility labels, Reduce Motion/Transparency and multi-display regressions are covered locally. | Manually evaluate the final build with VoiceOver, keyboard-only operation, text/display settings, both themes and multiple displays before making accessibility declarations. |
| Compatibility | Local host macOS 26.6.2; Xcode 27.0, SDK 27.0, Swift 6.4. Build is ARM64 and declares macOS 14+. | Test macOS 14 and current macOS on supported hardware. Do not advertise Intel support. The April 2026 SDK minimum announcement is not a native macOS requirement. |
| Business/legal/content — 3, 5.2 | No in-app payment, subscription, advertising, social feed or user account implementation found. | Owner confirms price/territories, app name/Bundle ID, rights to name/robot/icon/code and listing assets, current agreements and applicable tax/banking. New digital-purchase functionality would need Apple's purchase rules. |
| Connect declarations and regional compliance | Draft has no invented numeric age rating, trader status or legal details. Platform cryptography is declared as non-exempt-encryption false in the source, subject to owner's confirmation. | Complete current age-rating, privacy, export-compliance and accessibility questionnaires; EU trader verification if applicable; upload processing and App Review. TestFlight is a recommended project QA route, not an Apple-mandatory prerequisite. |

These historical findings map to [Apple's App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/). They do not establish that every behavior has passed Apple's review.

## Historical signing inspection — 2 October 2026

At that checkpoint, read-only inspection found matching team `8QG4967CSU`, Apple Development and Apple Distribution identities, plus an unexpired Xcode-managed macOS Store profile for `8QG4967CSU.com.dabin.mac`. **No Mac Installer Distribution / 3rd Party Mac Developer Installer identity was available in that inspection.** A Developer ID Application certificate is not a substitute. Later build 86 upload/Testing status is separate evidence; this historical inspection does not describe current Keychain inventory.

A Mac App Store upload is a distribution-signed installer package, not an unsigned app or a ZIP of an archive. Xcode's normal development-signed archive is an intermediate input, not the final Store distribution product. Two offline distribution-pinned attempts failed before compilation because signing selections conflicted with the Xcode-managed profile/Automatic workflow. A development archive compiled but signing rejected File Provider metadata; the isolated retry compiled and required owner approval to use the existing key. No completed signed archive is claimed. [Exact signing and cleanup status](../docs/qa/app-store-2026-10-02/packaging/packaging-status.json).

The historical attempt left installer signing and successful Xcode Store export/validation unresolved. It created/downloaded no certificate/profile, changed no account/Keychain setting and performed no upload/submission. Current build 98 awaits protected-key authorization and a completed signed archive/export; it does not claim that all historical signing blockers still apply. [Apple certificate types](https://developer.apple.com/help/account/certificates/certificates-overview/), [Packaging Mac software](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

## Privacy and capture boundary

While Auto Capture is unpaused, the project-recording sign can display the selected project name and task-timer alarms can show a task title until acknowledged. These labels can be visible to nearby people or screen-recording software. Build 98 hides all robots and signs while paused, retaining the timer/alarm state for Resume. Quiet mode and Reduce Motion control movement; window-sharing exclusion is a request, not protection against every recorder.

DaBin does not require Screen Recording, camera, microphone, Accessibility, Contacts, Photos, calendar or location permission. The screenshot channel sees new regular images only in the folder authorized through the system picker, not every system screenshot or a live recording. Clipboard monitoring sees later clipboard changes after opt-in; it does not import the initial clipboard. Both channels stop when paused/disabled or on Quit.

The proposed App Privacy response is **Data Not Collected**, an owner-review inference based on current local processing and no developer receipt of content. Optional manual-link previews contact the chosen websites, which is disclosed. The answer must be confirmed against the exact signed build and Apple's questionnaire. [Apple's data-collection guidance](https://developer.apple.com/app-store/app-privacy-details/).

## Local commands

Run from `native/` with the project's available Python 3.11+ runtime:

```sh
python3 scripts/run_qa.py --distribution app-store --configuration Release --timeout 180
python3 scripts/app_store_preflight.py --static-only
python3 scripts/validate_app_store_metadata.py
python3 scripts/validate_app_store_metadata.py --require-complete
python3 -m unittest discover -s Tests -p test_app_store_metadata.py
python3 scripts/test_app_store_preflight.py
```

Submission completeness, owner decisions and external acceptance are separate from native QA; filling metadata fields does not establish Apple approval. Use the [build 98 validation summary](../docs/qa/testflight-upgrade-0.4.43-98-2026-10-06/validation-summary.json) for current scope and the [2 October evidence README](../docs/qa/app-store-2026-10-02/README.md) for historical commands, artifacts and limitations.

## Apple references retained from the historical audit

- [Platform metadata fields and limits](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [Mac screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) — current drafts use 1440 × 900, 16:10.
- [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) — current age questionnaire, recursive quarantine checks and applicable regional requirements.
- [Age-rating questionnaire](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/)
- [EU trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)
- [Required-reason API descriptions](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Sandbox and user data](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
