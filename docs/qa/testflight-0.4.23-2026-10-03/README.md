# Final checks and TestFlight attempt — 3 October 2026

Target: **DaBin 0.4.23 (78)**, `com.dabin.mac`, team `8QG4967CSU`, ARM64/macOS 14+. The owner requested beta review, interpreted as **TestFlight only**. Public App Store release, public beta links and tester invitations are not part of this attempt.

**Status: NOT UPLOADED / NOT SUBMITTED.** No signed distribution product has been created in this attempt. No Apple account, Keychain, installed app, personal archive or public release was changed. No certificate was created, revoked or downloaded; no legal agreement was accepted.

## Final local results

- **85/85 offline Python tests pass**, including eight new archive-destination regressions; **30/30 static packaging checks** and **13/13 draft metadata checks** pass. [Post-fix evidence](offline/20261003T121149Z-post-fix/README.md). The stricter public-listing completeness validator still reports 12 unresolved gates; this is not a TestFlight-specific validator.
- **Store-only Release compile succeeds; 51/51 unsigned packaging checks pass** against unchanged final inputs. [Exact receipt](store-candidate-receipt.json). The compiled payload contains only the main executable, Info/PkgInfo, icon, robot SVG and privacy policy/manifest. There is no direct updater, private capture archive, fixture or diagnostic hook.
- **Fresh full native run: 73/77 suites passed, four failed.** [Exact report](native-report.json). The runner reports unchanged inputs and the same 196-input native fingerprint as the prior 77/77 run. This attempt is not an all-green result.
- `git diff --check` passes. Production Swift, resources and native test assertions were not changed during this attempt.

### GUI failures preserved

CUA reported that the Mac was locked and automatic unlock failed. The native runner explicitly requires an unlocked, logged-in session for window suites. The failures below require an unlocked rerun; the lock is relevant evidence, not proof that every failure is environmental.

| Suite | Observed failure |
| --- | --- |
| WindowTests | Two assertions: hover grants robot key focus; returning restores hover paste focus. |
| DailyCaptureTests | Daily panel did not become key for native Edit routing; test executable terminated on its top-level thrown assertion. |
| RobotWindowTransitionTests | Preparation did not advance into expansion within the test condition. |
| DetailPreviewInteractionTests | Generic file preview's mouse click did not invoke the opener exactly once. |

Logs remain in `native/build/qa/runs/20261003T120838504181Z/`. Preserve them. The earlier [77/77 receipt and 1,000-capture stress result](../performance-0.4.23-2026-10-02/verification.json) remain historical evidence, not a replacement for today's failed GUI checks. The non-fatal native table warning remains documented; large/animated screenshot-folder images and signed Store sandbox behavior need further coverage.

## Packaging correction and final artifact

The archive destination validator now rejects `..` path components before ancestry checks. Previously, a missing component before `..` could conceal a source-tree destination. Eight dedicated Python cases and the unchanged original probe pass after the fix. No user archive was involved.

Only this packaging script changed the production build inventory. The first Store compile (`store-unsigned-20261003T120834Z`) is retained but superseded. The final source-matched compile is:

`native/build/store-unsigned-20261003T121354Z/derived-data/Build/Products/Release/DaBin.app`

- Built: `2026-10-03T12:14:38.658525+00:00`.
- Source fingerprint: `3eefa8d6e62a3528eef930437c04c7d7895d58b3642d0bd390cd11044eb92e8d`.
- Executable SHA-256: `7561de70d2d837df308433c43b3ff0586a77b5a2d1b6ef1143455928a9afd3c2`.
- Receipt SHA-256: `b728e8694f2da97799647a9b62094e84bbc395d9ddea8baa456a318015697cb0`.
- Native report SHA-256: `1e8ded03537e0dc69e360e478b8e8ee23d9fabd4d6db52c05feaed8ac3d64ceb`.

This app is **unsigned**, not an exported installer or uploadable distribution product. The installed direct-channel app is not a Store substitute. The packaging-only fix does not change its runtime behavior; it was not replaced.

## Concrete submission blockers

1. **Apple account access:** App Store Connect opens at `https://appstoreconnect.apple.com/login`; no authenticated app/build record was visible. The tab is retained for owner sign-in. Name availability, Bundle ID record, previously uploaded build numbers, account role and current agreements are unverified.
2. **Installer signing:** elevated read-only `security find-identity -v -p codesigning` and `-p basic` show Apple Distribution, Apple Development and Developer ID Application identities, but **no Mac Installer Distribution / 3rd Party Mac Developer Installer identity**. The sandbox-only identity query returned zero and was not treated as evidence of absence; the elevated result is the relevant observation. Existing keys were not read or changed.
3. **Signed-candidate validation:** no distribution-signed archive/export, sandbox runtime test or Apple validation/upload exists for this attempt. Resolve signing and test the exact signed candidate, including folder access/relaunch/revocation and the GUI failures above. macOS 14 runtime testing is not established by a macOS 26 compile.
4. **Beta information:** confirm or supply feedback email and review-contact name/email/international phone, and applicable export-compliance answers in the real Connect record. No personal contact or compliance statement was invented. The [friendly beta copy and test plan](../../app-store/TESTFLIGHT_0.4.23.md) are ready locally.

## Resume

Unlock the Mac and sign in to App Store Connect. Use Xcode's signing workflow with owner approval for any new signing identity or required key access. Rerun the four failed suites in the unlocked session; do not weaken their assertions. Validate the exact distribution product, upload, wait for successful processing, then submit **TestFlight App Review** with the confirmed beta details. Leave automatic tester notification/public invitation links off and do not submit a public App Store version. Record the actual Apple status after each stage.

Apple references checked 3 October 2026: [TestFlight information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/), [upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), [external beta review](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).
