# DaBin 0.3.19 (46) — TestFlight handoff

## Beta app description

DaBin is a private daily board for the links, files, media, notes, screenshots,
and tasks you touch on your Mac. Drop or paste into the purple robot, then browse
your day or week, search local content, add reminders, or turn captures into tasks.

This beta focuses on the robot's camera-island personality and the continuous
robot-to-app transformation. Captures, OCR text, comments, reminders, and tasks
stay in DaBin's local archive.

## What to test

1. Move the pointer to a screen corner or the built-in camera island, then drop a
   file or hover and paste with Command-V or Control-V.
2. Confirm the robot appears only after a successful Auto Capture and eats a
   generic token without showing private capture content.
3. Double-click the robot and confirm it expands continuously into Daily. Close
   with X, Escape, or Command-W and reopen DaBin from Finder or TestFlight.
4. Try Daily and Weekly views, filters, search, day/week export, comments,
   reminders, task conversion, copy, minimize, and removal.
5. Test light/dark themes, transparency, Reduce Motion, Reduce Transparency, an
   external display, and display connect/disconnect where available.
6. Enable Auto Capture only with ordinary test data. Verify Pause and Off stop new
   actions immediately and that existing clipboard/folder contents are not imported.

## Feedback request

Please include the Mac model, macOS version, display arrangement, whether Reduce
Motion is enabled, what you expected, what happened, and reproduction steps. Do
not attach a private capture unless you deliberately choose to share it.

## TestFlight compliance notes

- Version: **0.3.19**
- Build: **46**
- Bundle ID: **com.dabin.mac**
- Platform: **macOS 14+ on Apple Silicon**
- Export compliance: `ITSAppUsesNonExemptEncryption = false`
- No account, analytics, advertising, cloud sync, third-party SDK, or purchase
- Auto Capture defaults off; optional website previews default off
- Store builds compile out the GitHub updater and do not embed its helper
- External testers may require Beta App Review before they can install the build

## Remaining account steps

1. Create or confirm the `com.dabin.mac` App ID and App Store Connect app record.
2. Install an Apple Development/Distribution identity for Team `8QG4967CSU` in
   Xcode Settings → Accounts → Manage Certificates.
3. Run `native/scripts/archive_app_store.sh` and validate the archive in Organizer.
4. Upload the build, wait for processing, complete export compliance and TestFlight
   information, add an internal group, then request Beta App Review for external
   testers.
