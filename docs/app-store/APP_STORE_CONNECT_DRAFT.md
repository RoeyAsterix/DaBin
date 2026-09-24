# DaBin App Store Connect draft

Use this as a working copy after the Apple Developer account and App Store Connect record exist. Replace every owner field and compare the text with the final signed archive before upload.

## Product page

- **Name:** DaBin — availability is not confirmed
- **Subtitle:** A private daily capture board
- **Primary category:** Productivity
- **Platforms:** macOS 14 or later, Apple Silicon
- **Privacy policy URL:** `https://github.com/RoeyAsterix/DaBin/blob/main/native/Resources/PrivacyPolicy.md`
- **Support URL:** replace with a maintained page that contains a real contact method
- **Copyright:** replace with the legal rights holder shown by the developer account
- **Price and availability:** owner decision

### Promotional text

Drop it, paste it, or capture it. DaBin keeps a private timeline of the links, files, media, notes, and tasks you touched on your Mac.

### Description

DaBin is a friendly purple robot bin for everything you work with during the day.

Drag files, images, videos, PDFs, links, or selected text onto the robot. You can also paste directly into the robot or the Daily window. Every capture joins a private calendar board on your Mac, ordered by the moment it was saved.

Browse Daily or Weekly, filter by text, links, files, media, or tasks, and search text recognized locally in supported images, PDFs, and documents. Add comments and reminders, turn any capture into a task, or export a complete day or week as plain text.

Auto Capture is optional and off by default. If enabled, it can save later clipboard changes and new images from a screenshot folder you choose. A visible menu bar status lets you pause or resume monitoring at any time. DaBin excludes itself and common password managers by default.

Your captures and searchable text stay in DaBin's local archive. There is no account, analytics, advertising, or cloud sync. Optional previews for links you save manually can contact those websites and are off by default.

DaBin supports dark mode, theme colors, adjustable transparency, keyboard navigation, Reduce Motion, and Reduce Transparency.

### Keywords

`daily board,clipboard,screenshot,notes,files,reminders,tasks,productivity,local,private`

## App privacy and compliance draft

- **Tracking:** No
- **Developer data collection:** Data Not Collected, based on the current local-only implementation; owner must confirm in App Store Connect
- **Accounts:** None
- **Third-party SDKs:** None found in the final local audit
- **Encryption:** `ITSAppUsesNonExemptEncryption = false`; no non-exempt encryption is implemented
- **Age rating:** answer the current questionnaire from the signed build's actual content; the app has no built-in objectionable content
- **Accessibility labels:** only claim VoiceOver, Full Keyboard Access, Reduce Motion, and Reduce Transparency after manual verification of the signed archive

## Review notes draft

DaBin is a menu bar utility and floating daily board. It opens Daily once on first launch. After the board is hidden, use the DaBin menu bar item and choose **Open Daily**, or move the pointer into a screen corner to reveal the purple robot. Double-click the robot to open Daily.

Manual capture test:

1. Copy ordinary text or drag a test file from Finder.
2. Reveal the robot at a screen corner and paste with Command-V or Control-V, or drop onto the robot.
3. Open Daily to see the capture on today's date.
4. The same paste and drop actions also work directly in the Daily window.

Auto Capture test:

1. Open **Settings → Capture**. Auto Capture starts off.
2. Enable it, read the local-storage explanation, and choose a dedicated temporary screenshot folder through the macOS picker.
3. Copy new test content after enablement or save a new screenshot image into that folder. Existing clipboard and folder content is not imported.
4. The menu bar icon and menu show the current state. Choose **Pause Auto Capture** to stop both monitors immediately; Resume and Off are also available.
5. DaBin and common password managers are excluded by default. Source-application attribution is best effort.

Other review boundaries:

- Auto Capture does not provide a universal system screenshot feed. It observes new images only in the user-selected folder and later clipboard changes.
- Automatic links never fetch website previews. Manual link previews are optional and off by default.
- Captures, OCR/search text, comments, tasks, reminders, and exports are processed locally.
- Notification permission is requested only when saving a reminder.
- Store builds compile out the GitHub update downloader and do not embed its helper. Updates are delivered by the Mac App Store.
- The success robot appears only after a capture is durably saved, is click-through, and is excluded from screen capture.
- No login, demo account, purchase, camera, microphone, Contacts, Photos, calendar, location, Accessibility permission, or Screen Recording permission is required.

## Assets

The three drafts in [`screenshots/1440x900`](screenshots/1440x900/README.md) are 1440 × 900 RGB PNGs without alpha and contain fictional isolated data. Recheck every image against the signed archive before upload.

## Final submission checklist

- Confirm the app name and reserve the Bundle ID.
- Install and select full Xcode; add the owner account and Team ID.
- Replace support and copyright placeholders with real owner information.
- Freeze and bump the release version/build, then tag the exact archived commit.
- Archive with `native/scripts/archive_app_store.sh`.
- Pass distribution preflight and Xcode Organizer validation.
- Test the signed archive on macOS 14 and current macOS with a clean standard account.
- Test VoiceOver, Full Keyboard Access, Reduce Motion, Reduce Transparency, folder permission revocation, Auto Capture pause/off, multiple displays, and built-in camera-island placement.
- Complete privacy, age-rating, availability, pricing, review-contact, and accessibility forms from the final binary.
- Upload to TestFlight, complete a clean install/update pass, then submit for review.
