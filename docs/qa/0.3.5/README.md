# DaBin 0.3.5 release evidence

This directory records the final source, functional, visual, package, guide and Store-readiness checks for DaBin 0.3.5 (30).

## Result

- **26/26** registered Release suites passed with **2,038 checks** and no source changes during the run.
- Auto Capture coverage includes **41 service checks**, **116 clipboard/file intake checks**, **25 hourly-grouping checks** and **25 passive robot-presenter checks**.
- The suites verify default-off startup, no import of existing clipboard/folder content, immediate Pause/Off cancellation, permission states, default exclusions, Finder sandbox-grant retention, screenshot/clipboard deduplication, stable image writes, PDF exclusion, partial-failure suppression and source-app sampling at directory activity.
- Hourly grouping verifies the fourth-action threshold, immediate count updates, fixed civil-clock hours, previous-day dates, filters, stable outer identity and the exact **Collapse actions** accessibility label. Weekly state checks verify that expand/collapse preserves the existing Daily scroll anchor.
- **32** production board renders passed. Original-resolution inspection covered Settings → Capture and collapsed/expanded hourly cards in light and dark appearances, including native 2x Settings samples.
- The package exercised isolated fresh installation, replacement, backup, strict signature validation, ZIP extraction, exact executable identity and the embedded helper's LaunchServices document handoff.
- The ARM64 Release build is 0.3.5 (30), source fingerprint `098cfbd3fcc749bce73265e644f92aa48000f789da501b21590eb148d57f7f72`, executable SHA-256 `70ffc44111382fbf9cf63a4e2a22383783681b45e61d8e63dc320f0a2b1230a9`.
- The update ZIP is 3,197,682 bytes, SHA-256 `9b283809330946d3ff58faeab30258502e6478717f80c6c417c36d1fcdfbd5cd`.
- The refreshed A4 one-page guide is 299,724 bytes, SHA-256 `b0068c47a2b72187f07027d949d874148791bed4929d0826d0efed5e3192353a`; its packaged and repository copies are byte-identical.
- Static App Store packaging passed **20/20**. Submission remains blocked by the owner's Apple Developer Team ID and a full Xcode installation.

The direct package is locally ad-hoc signed for this Mac. Developer ID signing and notarization, or Mac App Store signing, remain the public-distribution trust boundary.

## Files

- `full-run/report.json` and adjacent logs: complete registered-suite run.
- `release-ui-renders.json`: 32 production board views.
- `renders/`: selected original-resolution Auto Capture Settings and hourly-group inspection samples.
- `build-receipt-v0.3.5.json`: compiler, SDK, source inputs and executable identity.
- `update-manifest-v0.3.5.json`: exact update asset identity.
- `quick-guide-layout-check.json`: one-page A4 bounds and extraction result.
- `app-store-preflight-static-v0.3.5.log`: 20 passing source packaging checks.
- `app-store-preflight-release-v0.3.5.log`: the two external signing/tooling prerequisites.
