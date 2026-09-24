# DaBin 0.3.11 release evidence

This directory records the functional, visual, build, package and Store-readiness checks completed for DaBin 0.3.11 (36).

## Result

- **30/30** registered Release suites passed with **2,559 checks** and no source changes during the final run.
- The automatic-capture celebration model has 12 reactions, shuffled rotation, previous-three exclusion, bounded timing/gaze/entrance variation, normal 1.8–2.6 second plans and a 0.74 second Reduce Motion plan. The focused model suite passed **489 checks**.
- Presenter coverage passed **36 checks** for real camera-island attachment, built-in fallback, external-display placement, nonactivation, click-through behavior, screen-capture exclusion, rapid-count reuse, Reduce Motion, cancellation and cleanup. Auto Capture service coverage passed **41 checks** and keeps success presentation after durable storage only.
- Native robot QA rendered **42** Retina artifacts: every reaction against light and dark backgrounds, all four normal phases, the reduced-motion confirmation and the complete island popup with a rapid-capture `×3` badge. All 12 reaction peaks produced distinct rasters; active motion changed pixels, while hidden and Reduce Motion probes remained still.
- **34** release interface renders and **62** broader native interface renders passed. Original-resolution review covered both complete popup appearances, reaction and phase contact sheets, reduced-motion checkmarks, and representative Daily and Weekly views.
- The optimized ARM64 Release build is 0.3.11 (36), source fingerprint `397ec7f2133b857114262ca2a12020ff643f5fc983411d30bf1b152bb0fc8a22`, executable SHA-256 `0c735ddde9ef87c4a0ff464f0fd8dd6b2c967de582420c70ec52b3dafa6b4ad2`.
- The update ZIP is **3,314,777 bytes**, SHA-256 `81a691c6e5f9cfbfe82afe95f151a795b3e2737e678d4a01d8263ae4ccfc02ec`. Package QA passed isolated fresh installation, replacement, backup, strict clean-copy signature validation, extraction, manifest round trip, exact executable identity and document handoff.
- The unchanged one-page A4 PDF guide is **299,779 bytes**, SHA-256 `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291`; its retained geometry and extraction check remains one page with no boundary failure.
- Static App Store packaging passed **20/20** checks. Release preflight remains blocked by two external prerequisites: the owner's Apple Developer Team ID and a full Xcode installation.

The direct package is locally ad-hoc signed for this Mac. Developer ID signing and notarization, or Mac App Store signing, remain the public-distribution trust boundary.

## Files

- `full-run/report.json` and adjacent compile/suite logs: complete 30-suite optimized Release run and stable input hashes.
- `full-run/AutoCaptureRobotCelebrationTests.log`: shuffled rotation, reaction inventory, timing, variation and Reduce Motion plan coverage.
- `full-run/AutoCaptureRobotPresenterTests.log`: display placement, burst reuse, focus/click safety, capture exclusion and lifecycle coverage.
- `full-run/AutoCaptureServiceTests.log`: save-success and failure routing coverage.
- `robot-personality-renders.json`: manifest for 42 direct native robot artifacts and lifecycle probes.
- `release-ui-renders.json`: manifest for 34 release interface renders.
- `native-view-renders.json`: manifest for 62 broader native interface renders.
- `renders/`: all automatic celebration peaks, phases, reduced-motion samples, popup samples, contact sheets and representative board views.
- `build-receipt-v0.3.11.json`: compiler, SDK, source inputs, source fingerprint and executable identity.
- `update-manifest-v0.3.11.json`: exact release version, filename, byte count, checksum and intended release URLs.
- `quick-guide-layout-check.json`: retained one-page A4 guide geometry and text extraction evidence for the byte-identical PDF.
- `app-store-preflight-static-v0.3.11.log`: 20 passing static source and packaging checks.
- `app-store-preflight-release-v0.3.11.log`: the two external signing and tooling prerequisites.

