# DaBin documentation

## User documentation

Current source is **0.4.43 (98)**. It hides all robot artwork and signs while Auto Capture is paused, keeps the expanded board usable, and preserves timer/alarm state for Resume. The compact project/task/caption controls, day/week project calendar, selected-item ZIP export, global search with keyboard paste, native outgoing drag and local Finder actions are retained. [Release notes](RELEASE_NOTES_0.4.43.md).

The last verified local installation is **0.4.42 (97)**; the last verified internal TestFlight build is **0.4.31 (86), Testing**. Build 98 passes 11 selected native Store suites and an exact historical-86 → current-98 fictional data-upgrade fixture. This does not prove an actual TestFlight replacement. Its archive compiled to CodeSign and was interrupted awaiting human Keychain authorization: **98 is not uploaded**, and no public App Store review submission was made. [Validation scope](qa/testflight-upgrade-0.4.43-98-2026-10-06/validation-summary.json), [distribution status](qa/testflight-upgrade-0.4.43-98-2026-10-06/status.json).

The [build 97 security/locality audit](qa/security-locality-2026-10-06/audit-report.json) records bounded local fixes and qualified selected-suite, ZIP, installer and sandbox checks. Saved data/backups are not separately encrypted, clipboard exclusions are best effort, and opt-in previews/updates can contact external hosts. The post-install aggregate digest changed after a normal Drafts.json write; unchanged counts and byte totals do not certify full byte identity. [Preservation qualification](qa/security-locality-2026-10-06/archive-preservation-qualification.json).

The historical [4 October full QA cycle](qa/full-qa-navigation-2026-10-04/README.md) records 110 passing native suite executions against reconciled inputs, 90 offline tests, media/Xcode checks, repairs and remaining performance/platform limits. It is not a build 98 full-suite run. [App Store preparation and outstanding gates](../native/APP_STORE_READINESS.md) remain separate from local installation and Git publication.

Source publication does not publish a new downloadable binary or submit to the App Store. The download links below follow public GitHub releases; they are not build 98. The existing PDF and screenshot drafts are historical assets without verified build 98 parity.

- [Latest in-app update package](https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-Update.zip) — for an existing DaBin installation
- [Latest unsigned Apple Silicon test package](https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-AppleSilicon.zip) — not a notarized public installer
- [DaBin 0.4.43 paused robot fix and upgrade validation](RELEASE_NOTES_0.4.43.md)
- [DaBin 0.4.7 local candidate notes](RELEASE_NOTES_0.4.7.md)
- [DaBin 0.4.8 performance candidate notes](RELEASE_NOTES_0.4.8.md)
- [DaBin 0.4.9 click-to-open candidate notes](RELEASE_NOTES_0.4.9.md)
- [DaBin 0.4.10 capture timestamps candidate notes](RELEASE_NOTES_0.4.10.md)
- [DaBin 0.4.11 robot consistency candidate notes](RELEASE_NOTES_0.4.11.md)
- [DaBin 0.4.12 tooltip restoration candidate notes](RELEASE_NOTES_0.4.12.md)
- [DaBin 0.4.13 capture-trail cleanup candidate notes](RELEASE_NOTES_0.4.13.md)
- [DaBin 0.4.14 robot closing candidate notes](RELEASE_NOTES_0.4.14.md)
- [DaBin 0.4.15 preview-led collection cards](RELEASE_NOTES_0.4.15.md)
- [DaBin 0.4.16 task timer alarm robot](RELEASE_NOTES_0.4.16.md)
- [DaBin 0.4.17 preview-led Explorer cards](RELEASE_NOTES_0.4.17.md)
- [DaBin 0.4.18 two-second UI messages](RELEASE_NOTES_0.4.18.md)
- [DaBin 0.4.19 smooth window corners and resize grips](RELEASE_NOTES_0.4.19.md)
- [Reviewed 0.4.6 candidate notes](RELEASE_NOTES_0.4.6.md)
- [Robot-led quick guide (historical PDF)](DaBin-Quick-Guide.pdf)
- [Friendly product and guide copy](DaBin-Friendly-Copy.txt)
- [Native app guide](../native/README.md)
- [DaBin 0.4.1 local candidate notes](RELEASE_NOTES_0.4.1.md)
- [DaBin 0.4.0 local candidate notes](RELEASE_NOTES_0.4.0.md)
- [59-second walkthrough archive (0.3.19 interface)](walkthrough/README.md)
- [DaBin 0.3.18 release notes](RELEASE_NOTES_0.3.18.md)
- [DaBin 0.3.17 release notes](RELEASE_NOTES_0.3.17.md)
- [DaBin 0.3.16 release notes](RELEASE_NOTES_0.3.16.md)
- [DaBin 0.3.15 release notes](RELEASE_NOTES_0.3.15.md)
- [DaBin 0.3.14 release notes](RELEASE_NOTES_0.3.14.md)
- [DaBin 0.3.13 release notes](RELEASE_NOTES_0.3.13.md)
- [DaBin 0.3.12 release notes](RELEASE_NOTES_0.3.12.md)
- [DaBin 0.3.11 release notes](RELEASE_NOTES_0.3.11.md)
- [DaBin 0.3.10 release notes](RELEASE_NOTES_0.3.10.md)
- [DaBin 0.3.9 release notes](RELEASE_NOTES_0.3.9.md)
- [DaBin 0.3.8 release notes](RELEASE_NOTES_0.3.8.md)
- [Privacy policy](../native/Resources/PrivacyPolicy.md)
- [App Store listing draft and screenshot history](app-store/APP_STORE_CONNECT_DRAFT.md)

## Product and design

- [Navigation and adaptive zoom handoff](NAVIGATION_AND_ZOOM_HANDOFF.md) — retained implementation; see [historical verification and limits](qa/full-qa-navigation-2026-10-04/README.md)
- [Product plan](../PRODUCT_PLAN.md)
- [Current design specification](../design/DESIGN_SPEC.md)
- [Open Design handoff](../OPEN_DESIGN_HANDOFF.md)
- [Design prototype notes](../design/README.md)
- [Open Design redesign notes](../opendesign-redesign/README.md)

The prototype and handoff folders preserve the design process. The native app and [native app guide](../native/README.md) describe current behavior where historical documents differ.

## Engineering and release

- [Architecture](../native/ARCHITECTURE.md)
- [Behavior contract](../native/CONTRACT.md)
- [Implementation notes](../native/IMPLEMENTATION_NOTES.md)
- [Implementation plan](../native/IMPLEMENTATION_PLAN.md)
- [QA results](../native/QA_RESULTS.md)
- [Mac App Store readiness](../native/APP_STORE_READINESS.md)
- [App Store Connect draft](app-store/APP_STORE_CONNECT_DRAFT.md)
- [Build 98 selected Store suites and synthetic upgrade validation](qa/testflight-upgrade-0.4.43-98-2026-10-06/validation-summary.json)
- [Build 98 native test receipt](qa/testflight-upgrade-0.4.43-98-2026-10-06/native-qa-report.json)
- [Build 98 pending signing and upload status](qa/testflight-upgrade-0.4.43-98-2026-10-06/status.json)
- [Build 97 security/locality audit](qa/security-locality-2026-10-06/audit-report.json)
- [Historical build 86 TestFlight distribution status](qa/testflight-0.4.31-2026-10-04/status.json)
- [Historical 4 October full Release tests](qa/full-qa-navigation-2026-10-04/README.md)
- [Historical 4 October Store preparation](qa/app-store-preparation-2026-10-04/README.md)
- [Historical 24 September Store preparation](qa/app-store-preflight-2026-09-24/README.md)
- [Persistence QA notes](../native/Tests/PERSISTENCE_QA.md)
- [Release process](RELEASING.md)
