# Apple requirements audit — 4 October 2026

Candidate: **DaBin 0.4.31 (86), Mac App Store channel**, `com.dabin.mac`, Apple Silicon, macOS 14+. This is a preparation audit, not Apple approval. The current evidence and blocking gates are in [the QA report](../qa/app-store-preparation-2026-10-04/README.md).

## Applicable requirements and acceptance evidence

| Area | DaBin implementation / evidence to verify | Release gate |
|---|---|---|
| Complete, stable app and accurate metadata | Store-channel Release suites, Xcode build, current listing and reviewer walkthrough | Signed install/upgrade and supported-OS acceptance still needed |
| Mac sandbox and self-contained package | Four scoped sandbox entitlements; archive and signed-bundle checks | Real file-picker/bookmark workflows and distribution export |
| Store-only updates and public APIs | Store compilation omits direct updater/helper; disabled update actions and binary inspection | Validate exact exported package |
| Monitoring consent and visible status | Auto Capture starts off; explicit consent; folder choice; persistent red Recording indicator, Pause and Off | Real consent/revocation and closed-board acceptance |
| Privacy policy and data minimization | Bundled policy, deletion instructions, minimal permissions, local OCR/search | Publish corrected policy, confirm support/contact and final declarations |
| Privacy labels and manifest | No tracking/analytics SDK; app-owned preferences, elapsed timing and file dates declared | Account owner confirms labels for the exact final app and optional website previews |
| Screenshots and product page | Current native interface with fictional data; opaque 1440 × 900 PNG drafts | Compare with final signed app and confirm artwork rights |
| Support, intellectual property and review contact | Existing GitHub Issues is public; owner fields deliberately unfilled | Real maintained contact details and legal owner confirmation |
| Signing and installation | Configured team, app distribution/development identities and matching profile | Mac Installer Distribution identity, export, validation and processing |
| Age rating, encryption and territories | No account/social feed/IAP/custom encryption found; system HTTPS only | Current Connect questionnaire, exempt-encryption confirmation, pricing/territories, agreements and EU trader declaration |
| Accessibility, energy and networking | Existing keyboard/Reduce Motion coverage; optional system URL preview networking | VoiceOver pass, realistic energy checks and IPv6-only validation; do not claim untested accessibility labels |

## Current Apple sources

Reviewed the following official pages on 4 October 2026. Recheck before upload because requirements can change.

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): applicable sections include 1.5, 2.1, 2.3, 2.4.2, 2.4.5, 2.5.1, 2.5.14, 5.1 and 5.2. These govern completeness, accurate presentation, Mac packaging, monitoring consent, privacy and rights.
- [Submitting apps](https://developer.apple.com/app-store/submitting/) and [upcoming requirements](https://developer.apple.com/news/upcoming-requirements/): check the current SDK/toolchain and supported operating systems. Do not misapply iOS-only minimum-deployment rules to this Mac app. The local build records its actual Xcode/SDK versions. Mac uploads must not carry the quarantine extended attribute.
- [Current macOS platform](https://developer.apple.com/macos/): Apple documents macOS 27. The local host is 26.6.2, so final current-OS runtime acceptance remains outstanding.
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/): Mac screenshots accept 1440 × 900; PNG/JPEG must have no alpha/transparency. Screenshots must show the app as it actually works.
- [App Privacy details](https://developer.apple.com/app-store/app-privacy-details/): App Store privacy answers concern off-device collection, including integrated third-party behavior; the owner remains responsible for the final answers. Local-only storage is distinguished from optional website requests in the draft policy.
- [Required-reason API definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype): source audit matches CA92.1 for app-owned defaults, 35F9.1 for elapsed app events, and C617.1 for owned file timestamps. No new SDK or undisclosed API category was identified.
- [EU trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/): the account owner must determine and verify applicable trader status and contact information for EU distribution.
- [Distribution workflow](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases): local archive/export preparation is separate from App Store Connect upload, processing and review.

No account agreement, legal declaration, pricing decision, upload, release or submission is performed by this audit. No guarantee of acceptance is made; Apple reviews the final submitted binary and metadata.
