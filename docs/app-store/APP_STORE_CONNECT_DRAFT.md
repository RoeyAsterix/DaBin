# DaBin App Store Connect preparation

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
