# DaBin — Mac App Store readiness

**Audit date:** 24 September 2026
**Source version:** 0.3.16 (41), direct pre-publication checks passed
**Result: BLOCKED for submission; local app QA is a separate result.**

The source now has a Productivity category, a bundled privacy explanation, privacy manifest, and an Xcode Release configuration that does not force ad-hoc signing. These changes improve readiness. They do not make the locally signed app an App Store distribution build or guarantee approval.

## Results

| Status | Area | Evidence and remaining work |
| --- | --- | --- |
| PARTIAL | App Sandbox and selected-file scope | `Resources/DaBin.entitlements` enables App Sandbox, read/write access only to locations the user explicitly chooses in Open or Save panels, and outgoing network access for optional website previews. Write access is required for the user-selected destination of a day or week text download. The previously inspected local app's embedded entitlements match and has no sandbox exceptions or root privileges. Auto Capture relies on an explicit folder selection and a security-scoped bookmark for the screenshot location; an exported candidate containing this feature still needs entitlement, bookmark-restoration and revoked-access inspection. [Apple sandbox documentation](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) |
| PASS | Store/direct update separation | The generated Xcode Store configuration compiles a Store-managed update stub, has no direct feed key and does not embed the installer. The standalone builder alone enables `DABIN_DIRECT_UPDATES` and creates the GitHub helper. An exported Store candidate still needs binary inspection before submission. Source imports and linked libraries use Apple frameworks; no manually invoked private API was found. [App Review, 2.4.5 and 2.5.1](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility) |
| PARTIAL | Manual and automatic capture controls | Manual clipboard reads remain tied to paste. Auto Capture is a separate opt-in setting that defaults off, takes a clipboard baseline before considering later changes, uses a user-selected screenshot folder, and is intended to stop its observers immediately when paused or disabled. DaBin and common password managers are excluded by default, but source-app attribution is best effort and cannot guarantee origin. Live review must verify first launch, enable, pause, disable, relaunch, exclusion and permission-revocation behavior against the final signed candidate. Robot reveal still needs no camera, Accessibility or Screen Recording permission. |
| PARTIAL | Optional website requests | Website preview fetching defaults off. Settings and the bundled policy explain website contact, URLs, IP addresses, redirects, cancellation and local caching. The Auto Capture design requires automatic links to remain ineligible for preview requests even when previews are enabled. Network instrumentation against the final candidate must verify that separation, including automatic captures created while manual preview fetching is on. |
| PASS | Local notification design | Permission is requested when saving a reminder, not at startup. A denied permission does not prevent capture or saving a reminder record. Notification messages omit capture contents. Actual system delivery remains part of live QA. |
| PASS | Category and icon packaging | `Info.plist` now declares `public.app-category.productivity`. `AppIcon.icns` includes normal/Retina sizes through the 1024-pixel `ic10` entry. [Category key](https://developer.apple.com/documentation/bundleresources/information-property-list/lsapplicationcategorytype), [Mac submission category requirement](https://developer.apple.com/library/archive/releasenotes/General/SubmittingToMacAppStore/) |
| PARTIAL | Privacy and support | The bundle points to the public GitHub privacy policy and repository Issues page, and Settings retains the offline explanation. The policy now describes opt-in clipboard polling, the selected screenshot folder, best-effort source-app attribution, default password-manager exclusions, duplicate suppression, local storage and automatic-link network isolation. The owner must confirm that the public policy matches the final binary, and that support and publisher contact information satisfy the listing and remain maintained. [App Review, 1.5 and 5.1.1](https://developer.apple.com/app-store/review/guidelines/#privacy), [App privacy URL requirement](https://developer.apple.com/help/app-store-connect/reference/app-information/app-privacy) |
| BLOCKED | App Store signing and validation | The inspected development app is ad-hoc signed and has no TeamIdentifier. The generated Release configuration now uses automatic signing; a real Apple Developer team, registered Bundle ID, appropriate distribution signing/profile, and successful Xcode distribution validation remain necessary. `com.dabin.mac` is a local configured ID; availability/ownership was not checked. [Distribution signing for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/), [App Store provisioning](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile) |
| BLOCKED | Archive tooling in this environment | The selected tools are `/Library/Developer/CommandLineTools` with macOS SDK 26.5; `xcrun xcodebuild -version` fails because full Xcode is unavailable. The archive helper cannot run until full Xcode is installed/selected. This is an environment limitation of the supplied Xcode workflow, not a claim that the current SDK is prohibited. |
| BLOCKED | App Store Connect release information | No App Store Connect record or account was accessed. Publisher identity, support and privacy URLs, screenshots, description, age-rating answers, privacy answers, review contact/notes, availability/pricing, and applicable export-compliance answers need owner confirmation and submission validation. Do not submit placeholder URLs. [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information), [App privacy details](https://developer.apple.com/app-store/app-privacy-details/) |
| PARTIAL | Supported machines | The local build is Apple Silicon (`arm64`) and declares macOS 14+. It does not support Intel Macs. Full oldest-supported-macOS, multiple-display, and current distribution-build testing have not been established by this audit. The QA report records the actual machine and tests. |

## Auto Capture review boundary

Auto Capture is sensitive functionality and should be described directly in App Review notes and in the product listing where relevant. It is off by default. Reviewers need a short path to enable it, select a screenshot folder, make a new clipboard change, pause it and turn it off. The explanation should state that monitoring runs only while DaBin is running, saves into DaBin's local archive, and does not upload captured content.

The macOS capability boundary must remain accurate:

- Folder monitoring treats new regular image files in the location the user selected and authorized through the system picker as screenshot captures. It is not a system-wide screenshot feed.
- Screenshots sent to the clipboard can be considered through post-enable clipboard changes. Content already present when monitoring starts is not imported.
- There is no public notification delivered to an ordinary sandboxed app for every screenshot made anywhere on the Mac. DaBin must not advertise universal screenshot capture.
- The source application recorded for an automatic capture is best effort and can be unavailable or imprecise. Default password-manager exclusions reduce accidental capture when attribution is available; they are not proof of origin or a complete data-loss-prevention boundary.
- The short confirmation popup is presented only after the triggering screenshot has been saved and uses the public macOS window-sharing exclusion so it is not composited into screen captures while visible.

Before submission, exercise the final signed candidate with a clean preferences domain and verify: the default-off state; no import of the pre-enable clipboard or pre-existing folder images; immediate observer shutdown on Pause and Off; bookmark restoration and revoked folder access; the default exclusion list; opposite-channel screenshot/clipboard image deduplication without suppressing intentional same-channel repeats; no website request for automatic links while manual previews are enabled; four-action hourly grouping; and the passive confirmation popup. These requirements are documented behavior, not a claim that the current App Store candidate has passed them.

## Privacy manifest: scope and meaning

`Resources/PrivacyInfo.xcprivacy` records no tracking and no developer/SDK data collection, plus these uses:

- `NSPrivacyAccessedAPICategoryUserDefaults` / `CA92.1`: app-owned theme, board placement, robot-home, preview and Auto Capture preferences, including the selected-folder bookmark.
- `NSPrivacyAccessedAPICategorySystemBootTime` / `35F9.1`: elapsed animation time inside the app.

Both build paths include the manifest in `Contents/Resources/`, Apple's macOS location. The source's file-attribute checks read file type; no explicit timestamp API from Apple's covered list was found. [Reasons and API list](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), [Bundle placement](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle).

Apple's current required-reason enforcement text lists iOS, iPadOS, tvOS, visionOS, and watchOS, **not native macOS**. Including accurate declarations is useful preparation; the prior absence is not classified here as a confirmed native macOS rejection. [Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [Required-reason API scope](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

The candidate App Store privacy answer is **Data Not Collected**, based on the intended on-device behavior: the developer receives no manual or automatic captures or analytics. This remains an inference for owner review, not a submitted declaration or a substitute for inspecting the final binary. Apple distinguishes on-device processing from off-device collection. Eligible manual link previews contact user-selected websites; automatic links must never do so. The answer and policy must be revisited if any network behavior changes. [Apple's data-collection definition and on-device guidance](https://developer.apple.com/app-store/app-privacy-details/).

## Release workflow and verified gates

`scripts/build.sh` now defaults to an optimized **Release ARM64** app targeting macOS 14, with compiler warnings treated as errors and symbols stored separately at `build/DaBin.app.dSYM`. `--configuration Debug` is explicit. One sorted source/resource inventory drives local builds, the Xcode project, QA and source fingerprints. The generated project has cohesive source groups and a Release archive action.

`build/build-receipt.json` records the compiler, SDK, configuration, source hashes and executable hash. The local signature remains ad-hoc unless a developer explicitly configures a signing identity. An optimized local build is not an App Store distribution approval.

`scripts/install_app.py` refuses installation while DaBin is running, stages and verifies the copied app, preserves the previous owned app and restores it if installation fails. `scripts/package_standalone.py` creates an app-only ZIP with documentation and an optional explicit PDF. It verifies ARM64/system-library dependencies, stale-build hashes, signature and the extracted ZIP. It never includes the user's archive or removes macOS security controls. These local delivery tools are not inside the app bundle.

`UpdateTools/package_update.py` creates a current-Mac update ZIP with a native **DaBin Update.app** and a public `DaBin-update.json`. The direct app downloads only from the fixed repository path, verifies the published size and SHA-256, then opens its embedded helper through a private, one-use document in the app-owned Updates directory. The helper validates and consumes that handoff, rechecks the package, requests a normal quit, copies without extended metadata, backs up the prior owned app, verifies the staged and installed signatures and rolls back on failure. It never opens the capture archive. This 0.3.4 document handoff supersedes 0.3.3's sandbox-incompatible launch arguments. The generated Xcode Store build compiles out this downloader and does not embed the helper; an App Store build must use Apple's distribution channel.

The standard `scripts/test.sh` runner defaults to Release, compiles a testable module from the production sources and records all requested suite outcomes even after failures. Cached compiler artifacts are hashed before reuse. Reports under `build/qa/runs/` include configuration, OS, Swift/SDK, input hashes and individual logs; source changes invalidate the result. Window-focus failures remain failures. The final functional results belong in `QA_RESULTS.md`.

The offline preflight can be run without credentials or network access:

```sh
python3 scripts/app_store_preflight.py --static-only
python3 scripts/app_store_preflight.py
```

The 0.3.16 source replaces the text Daily/Weekly segment with two native SwiftUI icon buttons. It does not change sandbox, privacy, capture, persistence or update behavior. Its static source/package preflight passed all 20 checks; Store release preflight retains the same two external prerequisites:

- `../docs/qa/0.3.16/app-store-preflight-static-v0.3.16.log`: all 20 source and packaging checks passed.
- `../docs/qa/0.3.16/app-store-preflight-release-v0.3.16.log`: release preflight remains blocked by the Apple Developer Team ID and full Xcode. The configured GitHub policy/support URLs pass offline syntax checks; their content and continuing reachability remain owner responsibilities.

The completed 0.3.15 publication and installed-app verification, plus the 0.3.16 pre-publication evidence, are recorded in `QA_RESULTS.md`.

`bash -n` validated the build/archive shell scripts; Python compilation validated the preflight/project generator; property-list checks passed for Info.plist, entitlements, privacy manifest, and the generated Xcode project. Thirteen offline URL validation cases rejected placeholder, credential-bearing, local/private, malformed-port, whitespace, and invalid-host inputs as intended. URL validation is syntactic; the owner must verify that each published page is reachable and contains the required information.

After the owner provides real values, set `DABIN_DEVELOPMENT_TEAM`, `DABIN_PRIVACY_POLICY_URL`, and `DABIN_SUPPORT_URL` in the terminal environment. The two URLs may instead be supplied using the `DaBinPrivacyPolicyURL` and `DaBinSupportURL` Info.plist keys. Then run:

```sh
./scripts/archive_app_store.sh
```

The helper checks readiness inputs, injects those real URLs into the archive's Info.plist, and requests a Release archive at `build/app-store/DaBin.xcarchive`. It refuses to replace an existing archive. It does not enable automatic provisioning downloads, export, upload, submit, change keychain identities, or claim Apple approval. Distribution signing/export and validation are completed in Xcode Organizer using the owner's account. An exported candidate can additionally be inspected with:

```sh
python3 scripts/app_store_preflight.py --app /absolute/path/to/DaBin.app
```

This rejects ad-hoc/Developer ID signatures, the wrong configured team, non-ARM64/non-Release builds, missing App Sandbox, debugger entitlements, missing resources, and missing release URLs. It is a local check and cannot replace App Store Connect processing or review.

## Reviewer and listing notes to preserve

- DaBin is quiet while idle. Screen corners are the default reveal target; Settings can move the robot below the built-in camera island when macOS exposes compatible safe-area geometry, and displays without it keep using corners. Double-click the robot to open Daily. The app menu also provides Open Daily and Settings. Include these steps in review notes so the initially hidden widget is discoverable.
- The robot uses native character animation for pointer attention, drag acceptance, saving and results. Successful automatic saves select from a shuffled twelve-reaction rotation only after durable persistence, reuse one nonactivating click-through popup for bursts, and never play on failure. The popup is excluded from screen capture and contains no sound. Reduce Motion replaces the full automatic performance with a short static peek, success check and fade, while the interactive robot removes positional, repeated and keyframed movement.
- Manual capture accepts explicit paste/drop. Auto Capture is a separately disclosed, default-off setting for later clipboard changes and a user-authorized screenshot folder; provide review steps for both channels and for Pause/Off. Daily can group four or more successful automatic actions from the same civil-clock hour into an expandable summary. The Daily / Weekly control switches between one selected day and the seven-day range ending on that date; Weekly omits dates with no capture or task and shows one compact empty state when the whole range is empty. Comments and task editors retain normal text editing.
- Weekly Search can target an explicitly selected date or all seven dates in the displayed range. Weekly export can copy or download that selected day or the complete fixed range; file output goes only to the location the user chooses in the system save panel. Search retains the active content filter, while exported text intentionally includes the complete stored scope.
- Explain website-preview networking separately from local capture. Automatically captured links never request a preview; reviewers should be able to verify this while previews for eligible manual links are enabled.
- The current app categorizes by content type; it does not yet perform AI project recognition. Do not advertise automatic AI project assignment or uploading to an AI service.
- Describe Apple Silicon/macOS support accurately. Keep screenshots synthetic and free of personal captures.
- No account means no account-deletion flow is needed. Retention/removal instructions still matter. No payment system or purchase entitlement is present; monetization changes require a separate review.
- The app does not create a Desktop shortcut automatically. A shortcut explicitly requested by the user and created outside the running app is not an app auto-launch/shortcut behavior.

## Limits of this result

The Mac App Store and Developer ID distribution channels have different signing workflows. Developer ID notarization is not a substitute for Mac App Store distribution signing or approval. Likewise, Apple's April 2026 SDK minimum announcement lists the mobile/TV/vision/watch platforms, not macOS; the current upload table lists macOS separately. [SDK announcement](https://developer.apple.com/news/upcoming-requirements/?id=04282026a), [Upload requirements](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

The GitHub source/release channel is separate from App Store distribution. No certificate creation, App Store archive export, upload, or review submission was performed. This document also does not establish that Auto Capture passed live clipboard, folder, exclusion, deduplication, popup or network-isolation QA in a distribution-signed candidate. Functional test results and live QA limits are recorded separately in `QA_RESULTS.md`.

### Prior 0.1.20 real-media integration evidence

The separate `scripts/test_media_integration.sh` runner uses synthetic temporary files and production preview/storage components. The native run passed **39/39** checks: PDFKit produced a two-page PDF thumbnail; QuickLook produced an RTF document thumbnail; AVFoundation encoded/decoded a two-second H.264 movie and produced its preview. Thumbnails contain rendered content, managed/source bytes match, and preview records survive reopening. The production PDF view fits portrait and landscape pages at ordinary and narrow preview sizes in an invisible window that never takes focus. See `build/qa/media-integration-v0.1.20.log`.

An explicit `--link-smoke` run additionally fetched metadata for the generic public Apple homepage: **41/41 total checks**, including those same 39 local checks plus two link checks. The two logs describe overlapping runs, not 80 unique tests. Website access is opt-in in this separate runner, never part of the generic test suite; the runner uses a temporary archive and volatile process-only preferences. See `build/qa/media-integration-link-v0.1.20.log`.

Native media services require scoped access from the agent execution environment: the first restricted run could not encode its synthetic movie; the same executable passed after macOS media/QuickLook service access was allowed. No production media or user capture was read, and no notification or general-clipboard action was performed.
