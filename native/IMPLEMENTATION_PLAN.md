## Current checkpoint —6 October 2026

The application source is 0.4.43 (98). Compact toolbars, populated-day weekly browsing, project day/week filtering, selected-item export, whole-body companion motion and paused companion visibility are implemented. Archive/privacy/updater hardening is included. Eleven affected Store Release suites and the exact86→98 fictional data upgrade/save/two-reopen fixture pass. See `QA_RESULTS.md` and the campaign validation summary for scope and retained failures.

Next release step: run the pinned build 98 signing helper with human-controlled macOS key authorization, finish and validate the archive, upload to the existing internal TestFlight app/group, verify Apple processing and internal availability, then confirm a real Update on a tester Mac. Preserve app/container data and make a local archive backup; do not reinstall or downgrade to86 after saving newer data. Public App Store submission remains withheld. Historical full-suite performance, device acceptance, screenshot/policy parity and owner declaration gates remain recorded in `APP_STORE_READINESS.md`.

The original implementation plan below is retained as history; current behavior is described in `README.md` and `IMPLEMENTATION_NOTES.md`.

# DaBin native implementation

The conversation overrides the attached handoff's resting widget and Capture editor. At rest DaBin is invisible. A pointer or active drag in any display corner reveals one purple robot. Capture goes directly into that robot; success triggers a small digest. Single click focuses for paste, double click opens Daily. There is no capture composer or separate drop area. The opened board stays usable until dismissed.

1. Establish a native SwiftUI/AppKit application and reproducible command-line build using the installed Apple SDK. Supply an Xcode project for machines with full Xcode.
2. Implement durable local capture, immutable calendar identity, classification and contextual search; verify with isolated automated fixtures.
3. Build compact native Daily, Search, Detail, Reminders and Settings views without a sidebar; every capture exposes Comment and Reminder.
4. Integrate four-corner detection, native drops/file promises/explicit paste, metallic robot animation, previews and OS notifications.
5. Build and launch the sandboxed debug app, verify available native interactions, document measured results and remaining OS/toolchain limits, and place the deliverable under Desktop/DaBin.

No account, uploads, telemetry, launch-at-login registration or cloud sync. Link metadata is opt-in. The handoff source is preserved under Handoff/.
