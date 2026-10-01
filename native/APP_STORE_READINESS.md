# DaBin — Mac App Store readiness

Audit: **2 October 2026** · source **0.4.19 (74)** · `com.dabin.mac` · Apple Silicon, macOS 14+

**Status: functional regressions and unsigned Store packaging PASS; NOT ready to submit.** Passing local tests does not guarantee Apple approval. This audit covers applicable requirements for the current native, account-free, local-storage app. A change to accounts, payments, networking or content would require a new review.

The installed personal app and public release have not been changed by this preparation. Public downloads remain 0.3.18. The prior [24 September evidence](../docs/qa/app-store-preflight-2026-09-24/README.md) records 0.3.18 (45) and is historical, not current readiness.

The approved source, guide and preparation documents were pushed to `main` in commit `650ecf664bdabce46120eac5b5a6617a575b1689`. The corrected public privacy policy now matches the bundled source byte-for-byte; both configured and raw URLs returned HTTP 200. [Publication verification](../docs/qa/app-store-2026-10-02/publication.json). This does not publish a binary release or upload/submit an app to Apple.

## Local work and evidence

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

## Applicable review gates

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

These findings map to [Apple's current App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/). They do not establish that every behavior has passed Apple's review.

## Signing: verified assets and remaining blocker

Read-only inspection found matching team `8QG4967CSU`, Apple Development and Apple Distribution identities, plus an unexpired Xcode-managed macOS Store profile for `8QG4967CSU.com.dabin.mac`. **No Mac Installer Distribution / 3rd Party Mac Developer Installer identity is available.** A Developer ID Application certificate is not a substitute.

A Mac App Store upload is a distribution-signed installer package, not an unsigned app or a ZIP of an archive. Xcode's normal development-signed archive is an intermediate input, not the final Store distribution product. Two offline distribution-pinned attempts failed before compilation because signing selections conflicted with the Xcode-managed profile/Automatic workflow. A development archive compiled but signing rejected File Provider metadata; the isolated retry compiled and required owner approval to use the existing key. No completed signed archive is claimed. [Exact signing and cleanup status](../docs/qa/app-store-2026-10-02/packaging/packaging-status.json).

Before release, the owner needs the missing installer-signing asset and a successful Xcode Store export/validation with the matching app-signing profile, followed by App Store Connect processing. No certificate/profile was created or downloaded, no account/keychain changed, and no upload/submission performed. [Apple certificate types](https://developer.apple.com/help/account/certificates/certificates-overview/), [Packaging Mac software](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

## Privacy and capture boundary

The robot's automatic-save sign can display the selected project name. Focus expiry can show an alarm clock and the first three task-title words until dismissed. These labels can be visible to nearby people or screen-recording software. Quiet/Reduce Motion controls animation, not a guarantee that labels are invisible. Window-sharing exclusion is a request, not protection against every recorder.

DaBin does not require Screen Recording, camera, microphone, Accessibility, Contacts, Photos, calendar or location permission. The screenshot channel sees new regular images only in the folder authorized through the system picker, not every system screenshot or a live recording. Clipboard monitoring sees later clipboard changes after opt-in; it does not import the initial clipboard. Both channels stop when paused/disabled or on Quit.

The proposed App Privacy response is **Data Not Collected**, an owner-review inference based on current local processing and no developer receipt of content. Optional manual-link previews contact the chosen websites, which is disclosed. The answer must be confirmed against the exact signed build and Apple's questionnaire. [Apple's data-collection guidance](https://developer.apple.com/app-store/app-privacy-details/).

## Local commands

Run from `native/` with the project's available Python 3.11+ runtime:

```sh
python3 scripts/run_qa.py --configuration Release --timeout 180
python3 scripts/app_store_preflight.py --static-only
python3 scripts/validate_app_store_metadata.py
python3 scripts/validate_app_store_metadata.py --require-complete
python3 -m unittest discover -s Tests -p test_app_store_metadata.py
python3 scripts/test_app_store_preflight.py
```

The completeness validator must currently fail because real owner decisions and external gates are missing. Filling those fields does not establish Apple approval. Use the [evidence README](../docs/qa/app-store-2026-10-02/README.md) for exact commands, receipts, build artifacts and limitations.

## Current Apple references

- [Platform metadata fields and limits](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)
- [Mac screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) — current drafts use 1440 × 900, 16:10.
- [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/) — current age questionnaire, recursive quarantine checks and applicable regional requirements.
- [Age-rating questionnaire](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/)
- [EU trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)
- [Required-reason API descriptions](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Sandbox and user data](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
