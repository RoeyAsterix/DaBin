# DaBin 0.4.8 (63) - performance update

Explorer no longer normalizes every capture's complete text when the search field is empty. Each view update shares one filtered result between its rows, count and selection. Searches reuse normalized immutable original text while continuing to read current titles, comments, project names and recognized text.

Capture thumbnails and image details use background ImageIO downsampling and a bounded decoded-image cache. AppKit-supported vector formats such as SVG retain a bounded background-rendered preview. File stamps detect replacement at the same path, and archive path validation stays in place. Text thumbnails have bounded layout; complete originals remain available through the normal detail, copy and open actions. Dated-file listing and daily preview reads are also loaded away from the UI thread.

Robot gaze now settles when the pointer stops. Unchanged window geometry and click-through state skip repeated native updates. Actual movement, resizing, drops and project-sign celebrations keep their existing behavior.

## Measured query improvement

In a synthetic Release benchmark with 1,000 captures containing approximately 14 KB of text each, the final frozen module produced identical result counts:

| Explorer query | Before | After |
| --- | ---: | ---: |
| Browsing with an empty search | 119.464 ms | 3.010 ms |
| Repeated content search | 118.774 ms | 6.396 ms |
| First content search | 119.502 ms | 107.470 ms |

This is approximately 40× faster browsing query work and 19× faster repeated searches, not a measurement of total GUI response time. The first content search still pays the initial text-normalization cost. Production-source hashes matched before and after the measurement; module cache fingerprint: `9d31082875f55660f86aa9b15026f2e6523d6e2a1aec4f5fa06e34a3af072557`.

## Verification and local installation

- All 60 registered Release regression suites passed, with no source changes during the run: `native/build/qa/runs/20261001T153547862370Z/report.json`.
- The preview suite passed 15 background/cache checks, including SVG rasterization, orientation, replacement, cancellation, missing files and archive path safety.
- Native visual checks passed: 20 Explorer renders, 24 preview-fit renders and 52 release UI renders, plus the robot personality and automatic-capture reactions. All four corner markers remained visible in the 16 image/document fit checks; the eight PDF snapshots verify layout only because native bitmap snapshots omit PDFKit tiles.
- Preview-fit fixtures use a 680-point viewport to expose the entire media rectangle below the project/title/provenance header. Compact-window scrolling remains covered by the separate responsive interaction suites.
- The optimized ARM64 Release app and updater were signature-verified; installed executable hashes match the build receipt.
- Installed and relaunched `/Users/roeylibfeld/Applications/DaBin.app`; the live About panel reports **0.4.8 (63)**. Previous app: `/Users/roeylibfeld/Applications/.DaBinBackups/20261001-184332-76352b96.app`. The installer did not modify the capture archive; the existing paused Auto Capture state was preserved.

This is a local-only update, not a public release or App Store validation.
