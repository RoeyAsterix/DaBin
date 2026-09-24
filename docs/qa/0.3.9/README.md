# DaBin 0.3.9 release evidence

This directory records the completed functional, visual, build, package and Store-readiness checks for DaBin 0.3.9 (34). Publication and live-installation records are added after the release is public.

## Result

- **29/29** registered Release suites passed with **2,132 checks** and no source changes during the final run.
- Weekly coverage passed **118 state checks** and **95 native window checks**. It covers empty and sparse ranges, nonconsecutive active dates, carried and reminder-day tasks, filter stability, content-sized widths from zero through seven dates, both unfolding directions, screen clamping, range navigation, detail return and compact restoration.
- **34** production interface renders and **6** focused empty Daily/Weekly renders passed. Original-resolution review covered compact 380 × 290 point empty weeks and 428-point two-day weeks in light and dark appearances, plus a 380-point constrained two-column layout.
- The optimized ARM64 Release build is 0.3.9 (34), source fingerprint `07a81ba16f933d992e95ca80d105409375557e6495d05bebaa53787834025d84`, executable SHA-256 `afcc90d51fce5e5768247ac8606acfe32184e4d5b4537feefe6fe7a0ef8fdc01`.
- The update ZIP is **3,279,344 bytes**, SHA-256 `e653928f65287cbb48ada20316d90cfab169483b0b7074317fb50fd0909890e6`. Package QA passed isolated fresh installation, replacement, backup, strict clean-copy signature validation, extraction, manifest round trip, exact executable identity and document handoff.
- The unchanged one-page A4 PDF guide is **299,779 bytes**, SHA-256 `61c0a585b5a978a317ae9b2f133401e587027d57e9aaded4871ac5e0f9d36291`; its retained geometry and extraction check remains one page with no boundary failure.
- Static App Store packaging passed **20/20**. Release preflight remains blocked by two external prerequisites: the owner's Apple Developer Team ID and a full Xcode installation.

The direct package is locally ad-hoc signed for this Mac. Developer ID signing and notarization, or Mac App Store signing, remain the public-distribution trust boundary.

## Files

- `full-run/report.json` and adjacent compile/suite logs: complete 29-suite optimized Release run and stable input hashes.
- `full-run/WeeklyStateTests.log`: 118 logical-range, sparse-date, task and data-integrity checks.
- `full-run/WeeklyWindowTests.log`: 95 geometry, animation, screen and native panel checks.
- `release-ui-renders.json`: manifest for 34 production interface renders.
- `weekly-entry-renders.json`: manifest for six focused compact empty Daily/Weekly renders.
- `renders/`: selected sparse and empty Weekly samples in light and dark appearances.
- `build-receipt-v0.3.9.json`: compiler, SDK, source inputs, source fingerprint and executable identity.
- `update-manifest-v0.3.9.json`: exact release version, filename, byte count, checksum and intended release URLs.
- `quick-guide-layout-check.json`: retained one-page A4 guide geometry and text extraction evidence for the byte-identical PDF.
- `app-store-preflight-static-v0.3.9.log`: 20 passing static source and packaging checks.
- `app-store-preflight-release-v0.3.9.log`: the two external signing and tooling prerequisites.
- `release-publication.json`: added after public release verification.
- `live-install-v0.3.9.json`: added after the installed 0.3.8 app completes its verified update.
