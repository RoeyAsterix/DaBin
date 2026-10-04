# DaBin 0.4.23 (78) — TestFlight handoff

Prepared 3 October 2026. Target: **TestFlight beta review only**, not a public App Store release. This document is a draft; it is not evidence of an upload or submission.

## Beta description

DaBin is a little robot for the useful bits of your day. Save text, links, images and files on your Mac, organize them into colorful projects, and find them again with local text search. Plan tasks and try the robot's focus-timer reminder.

Automatic capture is optional and off by default. Choose clipboard changes, new images in a folder you authorize, or both. Pause it at any time from the menu bar. Use fictional, non-sensitive content for this beta: source-app exclusions are best effort and are not a guarantee against saving sensitive clipboard content.

Requires an Apple Silicon Mac running macOS 14 or later. No account or purchase is required. Captures and searchable text stay on the Mac. Optional previews for manually saved website links contact those websites; automatically captured links never fetch website previews.

## What to test

1. Save test text and files, reopen their previews, and confirm the original capture date and time.
2. Create a project, choose its color, and verify project-only search and day/week/date-range search, including text in supported PDFs, DOCX and TXT files.
3. Enable Auto Capture with non-sensitive fixtures and an empty dedicated screenshot folder. Check the destination project, Pause/Resume/Off, relaunch and folder permission changes.
4. While new captures arrive, scroll Explorer, use arrow keys and Return, switch grouping and projects, and repeatedly open/close the robot's full view. Report stalls, jumps, unexpected selection changes or memory growth.
5. Try tooltip settings, a focus timer, both themes and Reduce Motion. Verify the robot returns to the island when the completed-timer reminder is clicked.

Known investigation areas: a non-fatal native table warning during the large forced-layout soak; large or animated images in the screenshot folder are not covered by the small-image stress results. Signed Store sandbox behavior and the macOS 14 compatibility run remain separate checks.

## Review information

Use the workflow instructions in [APP_STORE_CONNECT_DRAFT.md](APP_STORE_CONNECT_DRAFT.md). No sign-in credentials or demo account are needed. Do not submit the locally installed GitHub-channel app: the Store build must exclude the direct updater.

Required owner/account inputs remain unconfirmed: feedback email; beta-review contact name, email and international phone number; the correct App Store Connect app record and current build history; applicable encryption/compliance answers. Do not infer these from unrelated files or personal captures.

## Submission boundary

- Validate/export the exact Store-distribution-signed product with the matching team, profile and installer-signing identity.
- Upload through App Store Connect, not “TestFlight Internal Only,” if submitting for external beta review.
- Wait for successful processing, supply beta test/review information, and submit the selected build for TestFlight App Review.
- Do not create a public invitation link, send tester invitations, enable automatic tester notifications, or publish an App Store version as part of this handoff.
- Record Apple's actual build and review status. Upload, processing, review submission and approval are distinct stages.

Apple references checked 3 October 2026: [upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/), [provide beta information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/), [external testing and beta review](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).
