# DaBin documentation

## User documentation

Current **App Store preparation** has 73 passing Release suites and source privacy/tooling updates, but is not yet submission-ready. It did not replace the installed app described below. [Current readiness and outstanding gates](../native/APP_STORE_READINESS.md), [final tests](qa/app-store-2026-10-02/tests/README.md).

The installed local candidate is **0.4.19 (74)**, with shared continuous window corners, a thin vector rim and easier visible-edge/outer-corner resize grips that preserve header controls. It retains two-second messages, preview-led cards, the click-to-dismiss task alarm, recovery controls and configurable tooltips. All 18 selected Release suites pass across two frozen-input reports: 17 valid passing batch suites and the final focused closing suite's 400 checks. Chrome evidence covers 16 native drags and eight light/dark 1×/2× fixtures; earlier CPU recording failures and corrected sampling are documented, not presented as live FPS. [Local installation verification](qa/local-install-0.4.19-2026-10-02/verification.json) records matching installed hashes and live version/preferences/Expand/Restore checks. It has not been published. The permanent downloads below still contain public **0.3.18**, and public installation still requires distribution signing and notarization.

- [Latest in-app update package](https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-Update.zip) — for an existing DaBin installation
- [Latest unsigned Apple Silicon test package](https://github.com/RoeyAsterix/DaBin/releases/latest/download/DaBin-Latest-AppleSilicon.zip) — not a notarized public installer
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
- [Robot-led quick guide (PDF)](DaBin-Quick-Guide.pdf)
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
- [Current App Store listing and screenshot preparation](app-store/APP_STORE_CONNECT_DRAFT.md)

## Product and design

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
- [Current full Release tests](qa/app-store-2026-10-02/tests/README.md)
- [Current Store preparation evidence and unresolved gates](qa/app-store-2026-10-02/README.md)
- [Historical 24 September Store preparation](qa/app-store-preflight-2026-09-24/README.md)
- [Persistence QA notes](../native/Tests/PERSISTENCE_QA.md)
- [Release process](RELEASING.md)
