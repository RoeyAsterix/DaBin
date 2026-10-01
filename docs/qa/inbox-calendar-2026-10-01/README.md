# Inbox Day / Week — 0.4.5 (59)

## Result

Inbox now owns the Day and Week calendar views. Labeled buttons appear directly beneath the primary navigation, including on the initial Inbox screen. The separate Activity tab has been removed; its calendar, filters and capture actions remain available under Inbox. To organize retains the existing undated triage queue and quick composer.

Week covers the seven dates ending on the selected day. Empty columns remain hidden, following the existing preference. Navigation preserves the selected date, content filter, unfinished note/task drafts and daily scroll anchor. Existing weekly search, day/week exports, column selection, settings/back and window expansion use the same routes as before.

Changed application files: `AppState.swift`, `BoardView.swift`, `InboxScreen.swift` and build metadata. Regression changes: `HeaderInteractionTests.swift`, `WeeklyStateTests.swift`, and `UpdateConfigurationTests.swift`. README and release notes describe the new location.

## Verification

- Final ARM64 Release build succeeds. Build inputs, QA inputs and installed executable hashes match.
- Six focused suites pass: HeaderInteraction (199 checks), WeeklyState (143), WorkInbox (31), DayExportUI (30), UpdateConfiguration (27), and WeeklyWindow.
- The initial header run caught a 15-point accessible To organize target despite its 30-point layout frame. Adding an explicit content shape corrected the hit area; the final run passes without weakening the assertion.
- Native actions cover Inbox → Week → Day → To organize, preservation of dates/filters/drafts, exact seven-date range, keyboard/search/export behavior and compact hit-target bounds.
- Three isolated production-view renders were reviewed at 380 points: [Inbox](inbox-inbox-380.png), [Week](inbox-weekly-380.png), [Day](inbox-daily-380.png). They contain fictional fixtures only.
- Deterministic project validation, whitespace checks and strict code signature verification pass.
- Installed **0.4.5 (59)** in `~/Applications/DaBin.app`. Live accessibility actions verified Inbox → Week → Day → Week. The app is left open in Week, with Inbox selected.
- A private backup verified 228 archive files. All 40 original records are unchanged and all 16 managed attachment originals remain byte-identical.

This is focused regression verification, not a new full-suite cycle. The empty-day policy is unchanged. No installer release or TestFlight submission was performed for build 59.

Evidence: [QA report](qa-report.json), [build receipt](build-receipt.json), [installation verification](installation.json).
