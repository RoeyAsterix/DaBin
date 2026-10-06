# DaBin App Store Connect preparation

## Current source candidate —0.4.43 (98), 6 October 2026

The current listing JSON targets 0.4.43 (98). Auto Capture Pause hides robot/sign/save feedback and expanded-board decoration immediately while leaving workspace content usable. Timer reminders remain pending until Resume. Eleven affected Store Release suites and the exact uploaded 86→98 fictional data upgrade/save/two-reopen fixture pass. [Validated scope](../qa/testflight-upgrade-0.4.43-98-2026-10-06/validation-summary.json).

The signed archive attempt compiled to CodeSign and was stopped awaiting human macOS signing authorization. Build 98 has not been uploaded, processed or assigned to internal testers; no public App Store review was submitted. The last verified Personal Testing build is0.4.31 (86). [Current signing and upload status](../qa/testflight-upgrade-0.4.43-98-2026-10-06/status.json), [release notes](../RELEASE_NOTES_0.4.43.md).

The delivered Word/PDF/content pack and screenshots below were rendered for 0.4.41 (96) and remain historical review drafts. They do not establish signed-build 98 parity. The 6 October privacy changes, current copy, signed runtime/device acceptance and owner declarations must be reconciled before any public review submission. Prior strict zoom performance remains an open gate.


## Historical 0.4.41 (96) review-pack preparation

Prepared 6 October 2026 locally. Apple references were verified 5 October 2026 UTC. The canonical draft copy is [metadata-en-US.json](metadata-en-US.json). The planned candidate incorporates the compact Captions, Tasks and Projects controls, day/week project date picker, selected-items ZIP export and clickable companion. Production source is locked by the [final candidate freeze](../qa/full-review-2026-10-05/final-candidate/source-freeze.json). The final full Store QA run is complete with one performance failure; supplemental checks and asset regeneration remain pending. This preparation performs no upload, submission or publication.

The [final Release app-store QA report](../../native/build/qa/runs/20261005T213352249116Z-app-store/report.json) passes 125 of 126 suites with unchanged source inputs. Workspace Zoom Performance is the only failure: the [30-second synthetic native fixture](../qa/full-review-2026-10-05/final-store/zoom-performance/performance.json) records input-to-layout p95 of 51.3154 ms against the unchanged 50 ms budget and steady zoom timer p95 of 61.2394 ms against 33 ms. These measurements do not establish physical input-to-display latency or the separate 600-second stress result. The [sequential supplement plan](../qa/full-review-2026-10-05/supplement-plan.json) covers that longer run, the unsigned Release build, XCTest, enforced sandbox and privacy renders; results remain pending.

Live note accessibility/content regression verification passed. The earlier integration failure concerned observing the displayed excerpt through its explicit AX action label; visual staleness was not established. Frozen production exposes displayed non-media text as its AX value. The [focused direct-channel functional report](../../native/build/qa/runs/20261005T213022192993Z-direct/report.json) passes all three selected suites with unchanged inputs: Project Workspace View (918 checks), Project Workspace Card (782) and Native Content Drag (38). The final full Store run also passes those functional suites. Strict performance, supplemental, physical input/drop, signing and owner requirements remain release gates. This candidate is a draft with `submissionReady: false`. [Prepared asset and authoring arguments](../qa/full-review-2026-10-05/review-pack-authoring-plan.json) pin the exact Store module and failed QA result; native exports and final artifact authoring remain paused until the coordinated asset stage is released.

Use the parameterized [local asset workflow](../../design/app-store-pack/README.md) after coordinated Store-channel QA. It generates fictional native screenshots, refreshes the two-page customer guide and creates a new versioned content pack. Preserve the existing [0.4.31 content pack](submission-pack-0.4.31-86/) and [0.4.31 screenshot set](screenshots/0.4.31-86/README.md) as historical material. The delivered [Quick Guide PDF](../DaBin-Quick-Guide.pdf) was rebuilt and visually reviewed for 0.4.41 (96); it remains a historical review draft pending final current signed-build parity.

Current copy instructions are single-click opening and **Export Selected** for checked items only. Manual companion movement follows the pointer near the selected edge or island. Successful automatic saves use generic acknowledgements, with rapid saves sharing a count. Quiet mode and Reduce Motion use a static expression. Active recording status can show the destination project. While Auto Capture is paused, the robot and sign remain hidden. Timer alarms can show the first three task-title words locally after Resume.

The owner still needs to provide the legal/copyright holder, public support URL/contact, private App Review contact, price, territories, release method and EU trader status. Keep private review details out of a public repository. Confirm agreements, the app record/build availability, age rating, privacy, encryption and rights in App Store Connect rather than inferring them from signing certificates.

The bundled privacy policy is **Updated 5 October 2026**. The [local publication copy](privacy-policy-2026-10-05.md) matches its current bytes. The public URL returns HTTP 200 but still serves the **4 October** text, so publication and byte-for-byte parity remain pending. No policy publication is performed here.

Before submission, publish and verify parity with the final bundled policy, prepare and validate the exact distribution-signed package, finish signed fresh-install/upgrade and supported-OS checks, and compare each screenshot with that app. The [4 October requirements audit](APPLE_REQUIREMENTS_2026-10-04.md) is historical evidence and needs a current candidate-specific refresh. Current tests or screenshot drafts do not establish Apple approval.

## Historical preparation — superseded copy and evidence

Historical target: **0.4.23 (78), TestFlight beta review only**, authorized on 3 October 2026. No upload or submission has occurred. Use the [beta handoff draft](TESTFLIGHT_0.4.23.md) and [latest checks/blockers](../qa/testflight-0.4.23-2026-10-03/README.md); the 0.4.19 preparation below is historical. Production-listing owner fields are not all prerequisites for a TestFlight beta, but real beta feedback/review contacts and current compliance answers must be supplied or confirmed in Connect.

Updated 2 October 2026 for source 0.4.19 (74). This is a local submission draft, not an uploaded app or an Apple approval.

The approved source and docs are now on GitHub `main` (`650ecf6`). The public privacy policy returned HTTP 200 and exactly matches the corrected local source. [Publication receipt](../qa/app-store-2026-10-02/publication.json). No binary release, App Store upload or submission was made.

The canonical English fields are in [metadata-en-US.json](metadata-en-US.json). Run `native/scripts/validate_app_store_metadata.py` to check copy lengths and source version alignment. `--require-complete` deliberately fails while owner decisions and external verification remain pending.

## Product page draft

- Name: DaBin; App Store name availability is unconfirmed.
- Subtitle: Save, organize and focus.
- Primary category: Productivity.
- Requirements: Apple Silicon, macOS 14 or later. Intel is not supported.
- Privacy URL: https://github.com/RoeyAsterix/DaBin/blob/main/native/Resources/PrivacyPolicy.md.
- Support URL: owner must provide a maintained public page with actual contact information. The currently bundled GitHub Issues URL is reachable but contact adequacy is not established.
- Copyright: owner must confirm the legal rights holder, not just the DaBin product name.
- Price, territories and release method: owner decisions; no choice has been made on the owner's behalf.

### Promotional text

A little robot for the useful bits of your day. Save ideas, links and files, keep projects together, and give one task your attention - all on your Mac.

### Description

DaBin is a little robot for the useful bits of your day. Keep ideas, links, images and files together on your Mac, then find them when you need them.

SAVE NOW. SORT LATER.
Drop something onto the robot or paste it into Inbox. Browse your captures by Day or Week, add a note, or turn a capture into a task. File previews let you open DaBin's saved copy.

KEEP A PROJECT TOGETHER.
Choose a project and give it a color. Matching card frames help you see what belongs together. Explorer puts previews first, while Notes, Clipboard and Shelf keep your thoughts, copied things and useful files close by. Search can also find text recognized locally in supported images, PDFs and documents.

GIVE ONE TASK YOUR ATTENTION.
Plan your day in Today, add checklist steps and reminders, or start a focus timer. When time is up, the robot holds an alarm clock and a sign with the task's first three words. Click the robot to send it home; your task stays open until you mark it done.

CHOOSE WHAT TO CAPTURE.
Auto Capture is optional and off by default. Turn on Clipboard, Screenshots, or both. It saves later clipboard changes and new images in a screenshot folder you choose, not existing content or a live screen recording. Check the visible destination to see which project will receive new automatic captures. The menu bar shows the capture state and lets you pause or resume it. Source-app exclusions are best effort, not a guarantee against saving sensitive copied content.

YOUR THINGS STAY ON YOUR MAC.
No account, advertising, analytics or cloud sync. Captures and searchable text are kept locally. Website previews are optional and off by default; previews for manually saved links contact those websites. Automatic links never fetch website previews.

Make DaBin comfortable with dark mode, theme colors and optional tooltips. Your saved captures can be exported, backed up or removed through Recently Deleted.

Requires an Apple Silicon Mac running macOS 14 or later.

### Keywords

`clipboard,screenshots,notes,files,tasks,projects,focus,reminders,organizer,local,robot`

## Review notes draft

DaBin is a native menu bar utility with a floating robot and a capture/project board. No login, purchases or demo account are required.

FIRST LAUNCH: Inbox opens once. Later use the DaBin menu bar item > Open DaBin, or move the pointer to a screen corner and double-click the robot. Camera-island placement is optional in Settings, with a corner fallback.

MANUAL CAPTURE: Copy ordinary test text. Hover over the robot and press Command-V, or use Paste in Inbox. You can also drop a test file onto the robot or choose Files in Inbox. Open a card to add a note, select its project or inspect its saved file preview. Inbox > Day/Week browses capture dates; Today plans tasks; Projects > Explorer, Clipboard, Shelf and Notes organize related work.

AUTO CAPTURE: Open Settings > Automatic capture. Clipboard and Screenshots have separate explicit opt-in switches, both off by default. The first activation presents a shared local-storage explanation; later channel changes use their own switches. Clipboard requires no folder. Screenshots require a folder selected in the macOS picker; use a dedicated temporary folder. Make a new clipboard change or add a new image after enabling. Existing contents are not imported. The persistent menu bar indicator/menu shows the state; Pause Auto Capture stops both selected channels. Off disables a channel. Capture only runs while the app runs.

The visible Destination determines the project for new automatic captures, or Unfiled. DaBin and common password managers are excluded by default, but source-app attribution is best effort. Auto Capture observes later clipboard changes and new image files in the authorized folder, not a universal screenshot feed or live screen recording.

PRIVACY: Captures, OCR/search text, notes and tasks stay locally; exports are written to a location the user chooses. DaBin does not upload them, but the chosen location may be synced by another service. Optional website previews are off by default and only manually saved links are eligible. Automatically captured links never fetch website previews. The robot's automatic-save sign can show the selected project name. An expired focus timer shows an alarm clock and the first three task-title words; click it to dismiss without completing the task. These labels may be visible to people looking at the screen.

REMINDERS: Notification permission is requested only when a reminder is saved. Denial does not prevent saving captures. Notification messages omit capture content.

STORE BUILD: This build does not contain DaBin's direct GitHub update installer/downloader. Updates are managed by the Mac App Store. It requires no camera, microphone, Contacts, Photos, calendar, location, Accessibility or Screen Recording permission.

QUIT: Settings > Quit DaBin or the menu bar > Quit DaBin stops capture and closes the robot/board. The archive is retained. Requires Apple Silicon and macOS 14 or later.

## Declarations requiring owner confirmation

- App privacy: candidate answer is Data Not Collected, inferred from the on-device implementation and no developer telemetry. Optional manual website previews contact websites; this is disclosed in the policy. Reassess the exact signed binary before answering Apple's form.
- Tracking, advertising, accounts and purchases: none in the audited source. There is no public social network or shared user-content service.
- Encryption: source declares no non-exempt encryption; system networking uses Apple's frameworks. Confirm the current export-compliance questions.
- Age rating: complete the current questionnaire from the real behavior. Do not assume a legacy numeric rating or treat the robot as a kids-category product.
- Accessibility: evaluate the exact signed app against Apple's criteria before claiming any Accessibility Nutrition Label. Source tests are not a complete VoiceOver audit.
- Ownership: confirm rights to the app, name, robot artwork/icon and every submitted screenshot. Use fictional examples; no private KARI material or personal captures.
- EU availability: confirm trader/non-trader status and applicable contact verification. Do not invent a legal address or identity.

## Screenshots

The existing [24 September drafts](screenshots/1440x900/README.md) are preserved as historical assets and are not current submission screenshots. The [current 0.4.19 drafts](screenshots/0.4.19-74/README.md) use current native UI and fictional fixtures. After visual review, compare or recapture from the exact signed candidate before upload. Mac screenshots must match Apple's accepted 16:10 dimensions; this project uses 1440 x 900 RGB PNGs without alpha.

## Final release gates

1. Confirm the App Store Connect app record, app name, Bundle ID and version/build history. Local profile matching is not a check of the current Connect record.
2. Confirm support/contact, legal copyright, review contact (name/email/international phone), price and territories. Remove every unresolved owner field before copying metadata into Connect.
3. **Policy publication resolved:** the corrected 2 October policy is published at the configured URL and verified byte-for-byte against the source. The original audit's older-policy observation is preserved; the separate publication receipt records the later authorized push. Recheck parity if the policy changes.
4. Prepare the exact source-matched Xcode development archive, then export the Store-distribution-signed app/installer. Inspect the exported product's distribution signature, sandbox entitlements, Store provisioning profile, resources, quarantine metadata and absence of the direct updater/helper. Xcode Organizer/App Store Connect validation remains separate from local checks.
5. Test the exact signed sandboxed candidate with a clean account on macOS 14 and current macOS: first launch/relaunch, capture/drag/paste, saved-file access, bookmark restoration/revocation, Auto Capture enable/pause/off and automatic-link network isolation.
6. Test VoiceOver, keyboard navigation, reduced motion/transparency, multiple displays and optional camera-island placement. Confirm monitoring stays visibly indicated even when celebrations are quiet. Measure signed-build idle/active energy, CPU, memory and disk use; test IPv6-only and offline preview/capture behavior.
7. Compare current screenshots with that exact app, and complete age-rating, privacy, encryption, accessibility and applicable EU trader/agreements/tax/banking information.
8. Complete signed clean-install/update testing, upload processing and Apple review. TestFlight is recommended for project QA, not required by Apple before production review. Source/documentation and privacy-policy publication were authorized and completed; binary publication, App Store upload/submission and account changes were not performed. These remain separately authorized steps. [Apple's upload workflow](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

## Apple references checked 2 October 2026

[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) cover completeness, accurate metadata, Mac sandbox/self-contained packaging, Store-managed updates, consent/recording indication, privacy and support. [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/) defines the name/copy/contact fields. [Mac screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) define allowed dimensions. [App privacy details](https://developer.apple.com/app-store/app-privacy-details/) explain the data-collection declaration. [Current age-rating workflow](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/) and [EU trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/) remain owner submission obligations.
