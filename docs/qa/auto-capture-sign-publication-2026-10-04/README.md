# Auto Capture signs: focused source publication

## Scope

This change adds privacy-safe robot-and-sign confirmations to GitHub main, based on `48fb359`. The separate local project, search, drag-and-drop and App Store work is outside this commit. Existing application version metadata is retained; this is a source update, not a new installer release.

After a successfully saved automatic screenshot or clipboard action, the existing passive robot panel presents a generic icon and confirmation message. It never receives captured text, filenames, source application names, project names or previews. Twelve shuffled reactions exclude the previous three choices. Rapid actions share an accurate current/pending count, with one pending aggregate. Quiet mode, pausing, disabling and shutdown stop confirmations. Opening the app, task timers, display changes and screenshot-tool activity coordinate through the existing presenter lifecycle.

The implementation reuses the current vector robot, native layers and theme colors. Normal animations last approximately 1.8–2 seconds; Reduce Motion uses a static peek and fade. There is no added sound or permission request.

## Verification

**Passed: 8 Release suites and 4,615 checks**, an ARM64 Release build, strict signature verification on a clean copy, generated Xcode inventory and property-list lint. Swift compilation treats warnings as errors. The candidate retains base version metadata **0.4.19 (74)** because no binary release is being issued.

The exact source candidate was verified independently of the larger local working tree. See [verification.json](verification.json), [native test results](native-test-report.json), and [build receipt](build-receipt.json). New sign suites cover motion/rotation, receipt routing, burst counts, interruptions, privacy, Reduce Motion and native rendering. Existing application lifecycle, capture service, presenter, celebration and robot lifecycle suites also pass.

Reviewed native fixtures: [light sign](renders/light-proud-raise-hold.png), [dark sign](renders/dark-proud-bow-hold.png), and [Reduce Motion](renders/external-reduced-motion.png).

## Platform limits

A screenshot confirmation starts after its triggering image has been saved. An already visible overlay may appear in a later screenshot taken by another application or API. System Screenshot UI detection provides best-effort suspension; macOS does not provide a reliable application-level veto over all screenshots. [Apple window sharing documentation](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none).

Display geometry and interruptions use injected fixtures. Physical notch hardware, monitor unplugging and VoiceOver listening were not rechecked for this publication. No installation, notarization, TestFlight upload or binary release is performed by this source push.
